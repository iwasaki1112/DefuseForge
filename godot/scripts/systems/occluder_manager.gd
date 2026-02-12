class_name OccluderManager
extends Node
## Light2D用のLightOccluder2D管理システム
## 3Dマップの壁/ドアをSubViewport内の2Dオクルーダーに変換

## シグナル
signal occluder_updated

## 内部ノード
var _occluder_parent: Node2D = null
var _viewport: SubViewport = null

## オクルーダー管理
var _wall_occluders: Array[LightOccluder2D] = []
var _door_occluders: Dictionary[Node3D, LightOccluder2D] = {}  # door_node -> LightOccluder2D
var _smoke_occluders: Dictionary[Node3D, LightOccluder2D] = {}  # smoke_area -> LightOccluder2D

## 座標変換パラメータ
var _map_size: Vector2 = Vector2(40, 40)
var _texture_resolution: int = 256
var _scale_factor: float = 1.0

## 壁コリジョンレイヤー
const WALL_COLLISION_LAYER: int = 2

## この高さ未満の障害物はFoW遮蔽しない（目線=1.5mより低い障害物は見越せる）
const MIN_OCCLUSION_HEIGHT: float = 1.2


## セットアップ
## @param viewport: 描画先のSubViewport
## @param map_size: マップサイズ（ワールド座標）
## @param resolution: テクスチャ解像度
func setup(viewport: SubViewport, map_size: Vector2, resolution: int) -> void:
	_viewport = viewport
	_map_size = map_size
	_texture_resolution = resolution
	_scale_factor = float(resolution) / maxf(map_size.x, map_size.y)

	# オクルーダー親ノードを作成
	if _occluder_parent:
		_occluder_parent.queue_free()

	_occluder_parent = Node2D.new()
	_occluder_parent.name = "OccluderParent"
	_viewport.add_child(_occluder_parent)


## マップからオクルーダーを抽出
## @param map_node: マップのルートノード
func extract_occluders_from_map(map_node: Node3D) -> void:
	if not _occluder_parent:
		push_error("OccluderManager: setup() must be called before extract_occluders_from_map()")
		return

	if Debug.enabled: print("[FOW] OccluderManager.extract_occluders_from_map - map: ", map_node.name, ", map_size: ", _map_size, ", scale_factor: ", _scale_factor)

	# 既存のオクルーダーをクリア
	_clear_wall_occluders()

	# マップを再帰的に探索
	_extract_occluders_recursive(map_node)

	if Debug.enabled: print("[FOW] Extracted wall occluders: ", _wall_occluders.size(), ", door occluders: ", _door_occluders.size())
	occluder_updated.emit()


## ドアオクルーダーの有効/無効を切り替え
## @param door: ドアノード
## @param enabled: trueでオクルーダー有効（ドア閉）、falseで無効（ドア開）
func set_door_occluder_enabled(door: Node3D, enabled: bool) -> void:
	if door in _door_occluders:
		_door_occluders[door].visible = enabled


## スモークエリアのオクルーダーを追加
## @param smoke_area: スモークエリアノード
func add_smoke_occluder(smoke_area: Node3D) -> void:
	if smoke_area in _smoke_occluders:
		return

	if not smoke_area.has_method("get_current_radius"):
		push_warning("OccluderManager: smoke_area must have get_current_radius() method")
		return

	var occluder := LightOccluder2D.new()
	var polygon := OccluderPolygon2D.new()
	polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED

	# 円形ポリゴン生成
	var center := _world_to_viewport(smoke_area.global_position)
	var radius: float = smoke_area.get_current_radius() * _scale_factor
	polygon.polygon = _generate_circle_polygon(center, radius)

	occluder.occluder = polygon
	_occluder_parent.add_child(occluder)
	_smoke_occluders[smoke_area] = occluder


## スモークエリアのオクルーダーを削除
## @param smoke_area: スモークエリアノード
func remove_smoke_occluder(smoke_area: Node3D) -> void:
	if smoke_area in _smoke_occluders:
		var occluder: LightOccluder2D = _smoke_occluders[smoke_area]
		occluder.queue_free()
		_smoke_occluders.erase(smoke_area)


## スモークエリアの半径を更新
## @param smoke_area: スモークエリアノード
func update_smoke_radius(smoke_area: Node3D) -> void:
	if smoke_area not in _smoke_occluders:
		return

	if not smoke_area.has_method("get_current_radius"):
		return

	var occluder: LightOccluder2D = _smoke_occluders[smoke_area]
	var center := _world_to_viewport(smoke_area.global_position)
	var radius: float = smoke_area.get_current_radius() * _scale_factor
	occluder.occluder.polygon = _generate_circle_polygon(center, radius)


## 全オクルーダーをクリア
func clear_all_occluders() -> void:
	_clear_wall_occluders()
	_clear_door_occluders()
	_clear_smoke_occluders()


## マップサイズを更新
func set_map_size(new_size: Vector2) -> void:
	_map_size = new_size
	_scale_factor = float(_texture_resolution) / maxf(new_size.x, new_size.y)


## テクスチャ解像度を更新
func set_texture_resolution(resolution: int) -> void:
	_texture_resolution = resolution
	_scale_factor = float(resolution) / maxf(_map_size.x, _map_size.y)


# ============================================
# 内部メソッド - オクルーダー抽出
# ============================================

## CollisionShape3Dのワールド空間での上端Y座標を取得
func _get_obstacle_world_height(collision_shape: CollisionShape3D) -> float:
	var shape := collision_shape.shape
	var t := collision_shape.global_transform

	if shape is BoxShape3D:
		return t.origin.y + shape.size.y / 2.0
	elif shape is CylinderShape3D:
		return t.origin.y + shape.height / 2.0
	elif shape is ConvexPolygonShape3D:
		var max_y := -INF
		for point in shape.points:
			var world_y: float = (t * point).y
			if world_y > max_y:
				max_y = world_y
		return max_y

	# 未対応のシェイプはデフォルトで高いとみなす（遮蔽する）
	return INF


## MeshInstance3DのAABBからワールド空間での上端Y座標を取得
func _get_mesh_world_height(mesh_instance: MeshInstance3D) -> float:
	var aabb := mesh_instance.get_aabb()
	var t := mesh_instance.global_transform
	var local_top := Vector3(0, aabb.position.y + aabb.size.y, 0)
	return (t * local_top).y


func _extract_occluders_recursive(node: Node) -> void:
	var node_name_lower := node.name.to_lower()
	var parent: Node = node.get_parent()
	var parent_name_lower := parent.name.to_lower() if parent else ""

	# 壁/ドアの判定（名前プレフィックスで検出）
	var is_wall := node_name_lower.begins_with("wall_") or parent_name_lower.begins_with("wall_")
	var is_door := node_name_lower.begins_with("door_") or parent_name_lower.begins_with("door_")

	if is_wall or is_door:
		# StaticBody3DのCollisionShape3Dを探索
		if node is StaticBody3D:
			for child in node.get_children():
				if child is CollisionShape3D:
					# 高さフィルター: 低い障害物はFoW遮蔽しない
					var height := _get_obstacle_world_height(child)
					if height < MIN_OCCLUSION_HEIGHT:
						if Debug.enabled: print("[FOW] Skip low obstacle: ", node.name, " (height=", snapped(height, 0.01), " < min=", MIN_OCCLUSION_HEIGHT, ")")
						continue
					var occluder := _create_occluder_from_shape(child)
					if occluder:
						_occluder_parent.add_child(occluder)
						if is_door:
							var door_node: Node3D = (node if node_name_lower.begins_with("door_") else parent) as Node3D
							_door_occluders[door_node] = occluder
						else:
							_wall_occluders.append(occluder)

		# MeshInstance3Dの場合、AABBからオクルーダーを生成
		elif node is MeshInstance3D:
			# 高さフィルター: 低い障害物はFoW遮蔽しない
			var height := _get_mesh_world_height(node as MeshInstance3D)
			if height < MIN_OCCLUSION_HEIGHT:
				if Debug.enabled: print("[FOW] Skip low obstacle: ", node.name, " (height=", snapped(height, 0.01), " < min=", MIN_OCCLUSION_HEIGHT, ")")
			else:
				var occluder := _create_occluder_from_mesh(node as MeshInstance3D)
				if occluder:
					_occluder_parent.add_child(occluder)
					if is_door:
						var door_node: Node3D = (node if node_name_lower.begins_with("door_") else parent) as Node3D
						_door_occluders[door_node] = occluder
					else:
						_wall_occluders.append(occluder)

	# 子ノードを再帰的に処理
	for child in node.get_children():
		_extract_occluders_recursive(child)


func _create_occluder_from_shape(collision_shape: CollisionShape3D) -> LightOccluder2D:
	var shape := collision_shape.shape
	if not shape:
		return null

	var polygon_2d: PackedVector2Array

	if shape is BoxShape3D:
		polygon_2d = _extract_box_polygon(collision_shape)
	elif shape is ConvexPolygonShape3D:
		polygon_2d = _extract_convex_polygon(collision_shape)
	elif shape is CylinderShape3D:
		polygon_2d = _extract_cylinder_polygon(collision_shape)
	else:
		# 未対応の形状
		return null

	if polygon_2d.size() < 3:
		return null

	var occluder := LightOccluder2D.new()
	var occluder_polygon := OccluderPolygon2D.new()
	occluder_polygon.polygon = polygon_2d
	occluder_polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED
	occluder.occluder = occluder_polygon
	# Light2Dのshadow_item_cull_mask (default=1) とマッチさせる
	occluder.occluder_light_mask = 1

	return occluder


func _create_occluder_from_mesh(mesh_instance: MeshInstance3D) -> LightOccluder2D:
	var aabb := mesh_instance.get_aabb()
	if aabb.size.length() < 0.01:
		return null

	var transform := mesh_instance.global_transform
	var half := aabb.size / 2.0
	var center := aabb.position + half

	# AABBの4隅（Y=0平面に投影）
	var corners_3d := [
		Vector3(center.x - half.x, 0, center.z - half.z),
		Vector3(center.x + half.x, 0, center.z - half.z),
		Vector3(center.x + half.x, 0, center.z + half.z),
		Vector3(center.x - half.x, 0, center.z + half.z)
	]

	var polygon_2d := PackedVector2Array()
	for corner in corners_3d:
		var world: Vector3 = transform * corner
		polygon_2d.append(_world_to_viewport(world))

	if polygon_2d.size() < 3:
		return null

	var occluder := LightOccluder2D.new()
	var occluder_polygon := OccluderPolygon2D.new()
	occluder_polygon.polygon = polygon_2d
	occluder_polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED
	occluder.occluder = occluder_polygon
	occluder.occluder_light_mask = 1

	return occluder


func _extract_box_polygon(collision_shape: CollisionShape3D) -> PackedVector2Array:
	var shape := collision_shape.shape as BoxShape3D
	var half := shape.size / 2.0
	var transform := collision_shape.global_transform

	# 3Dボックスの4隅（Y=0平面）
	var corners_3d := [
		Vector3(-half.x, 0, -half.z),
		Vector3(half.x, 0, -half.z),
		Vector3(half.x, 0, half.z),
		Vector3(-half.x, 0, half.z)
	]

	var result := PackedVector2Array()
	for corner in corners_3d:
		var world: Vector3 = transform * corner
		result.append(_world_to_viewport(world))

	return result


func _extract_convex_polygon(collision_shape: CollisionShape3D) -> PackedVector2Array:
	var shape := collision_shape.shape as ConvexPolygonShape3D
	var points := shape.points
	var transform := collision_shape.global_transform

	# XZ平面に投影
	var result := PackedVector2Array()
	for point in points:
		var world: Vector3 = transform * point
		result.append(_world_to_viewport(world))

	# 凸包を計算（重複頂点を除去）
	if result.size() >= 3:
		result = Geometry2D.convex_hull(result)

	return result


func _extract_cylinder_polygon(collision_shape: CollisionShape3D) -> PackedVector2Array:
	var shape := collision_shape.shape as CylinderShape3D
	var transform := collision_shape.global_transform
	var center := _world_to_viewport(transform.origin)
	var radius := shape.radius * _scale_factor

	return _generate_circle_polygon(center, radius)


# ============================================
# 内部メソッド - ユーティリティ
# ============================================

func _world_to_viewport(world_pos: Vector3) -> Vector2:
	# ワールドXZ座標をビューポート座標に変換
	var half_map := _map_size / 2.0
	var uv_x := (world_pos.x + half_map.x) / _map_size.x
	var uv_y := (world_pos.z + half_map.y) / _map_size.y
	return Vector2(uv_x * _texture_resolution, uv_y * _texture_resolution)


func _generate_circle_polygon(center: Vector2, radius: float, segments: int = 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := float(i) * TAU / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _clear_wall_occluders() -> void:
	for occluder in _wall_occluders:
		if is_instance_valid(occluder):
			occluder.queue_free()
	_wall_occluders.clear()


func _clear_door_occluders() -> void:
	for occluder in _door_occluders.values():
		if is_instance_valid(occluder):
			occluder.queue_free()
	_door_occluders.clear()


func _clear_smoke_occluders() -> void:
	for occluder in _smoke_occluders.values():
		if is_instance_valid(occluder):
			occluder.queue_free()
	_smoke_occluders.clear()
