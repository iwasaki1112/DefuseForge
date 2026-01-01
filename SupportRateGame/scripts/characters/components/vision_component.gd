class_name VisionComponent
extends Node

## 視野コンポーネント
## キャラクターの視野を管理し、視界内のポイントを計算
## 参考: https://ncase.me/sight-and-light/

signal visibility_changed(visible_points: Array)

@export_group("視野設定")
@export var fov_angle: float = 120.0  # 視野角（度）
@export var view_distance: float = 15.0  # 視野距離
@export var height_offset: float = 1.5  # レイキャストの高さオフセット

@export_group("精度設定")
@export var arc_segments: int = 32  # FOV弧を分割するセグメント数
@export var corner_offset: float = 0.0001  # コーナーへのレイのオフセット角度（ラジアン）

@export_group("更新設定")
@export var update_interval: float = 0.0  # 視野更新間隔（秒）- 0で毎フレーム更新

# 親キャラクター参照
var character: CharacterBody3D = null

# 視野ポリゴンを構成する点のリスト
var visible_points: Array = []  # Array of Vector3
var _visible_points_size: int = 0

# 壁検出用コリジョンマスク
var collision_mask: int = 2  # デフォルトは地形レイヤー

# 更新タイマー
var _update_timer: float = 0.0

# キャッシュされた障害物コーナー
var _obstacle_corners: Array = []  # Array of Vector3


func _ready() -> void:
	character = get_parent() as CharacterBody3D
	if not character:
		push_error("[VisionComponent] Parent must be CharacterBody3D")
		return

	# 敵チームの場合は即座に処理を無効化
	if not _should_register_with_fog():
		set_physics_process(false)
		print("[VisionComponent] Disabled for enemy team: %s" % character.name)
		return

	# FogOfWarManagerへの登録を遅延実行
	_deferred_register.call_deferred()


## 遅延登録
func _deferred_register() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not _should_register_with_fog():
		set_physics_process(false)
		return

	var fow = _get_fog_of_war_manager()
	if fow:
		fow.register_vision_component(self)
		print("[VisionComponent] Registered to FogOfWarManager: %s" % character.name)
	else:
		push_warning("[VisionComponent] FogOfWarManager not found for: %s" % character.name)

	# 初回計算
	_calculate_visibility()


func _exit_tree() -> void:
	var fow = _get_fog_of_war_manager()
	if fow:
		fow.unregister_vision_component(self)


func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


func _should_register_with_fog() -> bool:
	if character and character.has_method("is_player") and not character.is_player():
		return false
	if character and character.is_in_group("enemies"):
		return false
	return true


func _physics_process(delta: float) -> void:
	if not character:
		return

	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_calculate_visibility()


## 視界を計算（Sight & Lightアルゴリズム）
func _calculate_visibility() -> void:
	if not character or not character.is_inside_tree():
		_visible_points_size = 0
		return

	var origin := character.global_position + Vector3(0, height_offset, 0)
	var forward := character.global_transform.basis.z  # +Z方向
	var forward_angle := atan2(forward.x, forward.z)
	var half_fov := deg_to_rad(fov_angle / 2.0)

	# FOVの境界角度
	var min_angle := forward_angle - half_fov
	var max_angle := forward_angle + half_fov

	# 障害物コーナーを収集
	_collect_obstacle_corners(origin)

	# レイを発射する角度を収集
	var ray_angles: Array[float] = []

	# 1. FOV境界のレイ
	ray_angles.append(min_angle)
	ray_angles.append(max_angle)

	# 2. FOV弧に沿ったレイ（滑らかな外縁のため）
	for i in range(1, arc_segments):
		var t := float(i) / float(arc_segments)
		var angle := min_angle + (max_angle - min_angle) * t
		ray_angles.append(angle)

	# 3. 各障害物コーナーに向かうレイ（+ オフセットレイ）
	for i in range(_obstacle_corners.size()):
		var corner: Vector3 = _obstacle_corners[i]
		var to_corner: Vector3 = corner - origin
		var corner_angle: float = atan2(to_corner.x, to_corner.z)

		# 角度がFOV内かチェック
		if _is_angle_in_fov(corner_angle, forward_angle, half_fov):
			ray_angles.append(corner_angle)
			ray_angles.append(corner_angle - corner_offset)
			ray_angles.append(corner_angle + corner_offset)

	# 角度でソート
	ray_angles.sort()

	# 重複を除去
	var unique_angles: Array[float] = []
	for angle in ray_angles:
		if unique_angles.is_empty() or absf(angle - unique_angles[-1]) > 0.00001:
			unique_angles.append(angle)

	# レイキャストを実行して交点を収集
	var intersection_points: Array = []
	intersection_points.append(character.global_position)  # 中心点

	var space_state := character.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [character]
	query.collide_with_bodies = true
	query.collide_with_areas = false

	for angle in unique_angles:
		var direction := Vector3(sin(angle), 0, cos(angle))
		var end_point := origin + direction * view_distance

		query.from = origin
		query.to = end_point

		var result := space_state.intersect_ray(query)

		if result:
			intersection_points.append(result.position)
		else:
			intersection_points.append(end_point)

	visible_points = intersection_points
	_visible_points_size = visible_points.size()
	visibility_changed.emit(visible_points)


## 角度がFOV内かどうかをチェック
func _is_angle_in_fov(angle: float, forward_angle: float, half_fov: float) -> bool:
	var diff := angle_difference(angle, forward_angle)
	return absf(diff) <= half_fov


## 障害物のコーナーを収集
func _collect_obstacle_corners(origin: Vector3) -> void:
	_obstacle_corners.clear()

	# シーン内の障害物（collision_layer = 2）を取得
	var obstacles := get_tree().get_nodes_in_group("obstacles")

	# グループがない場合は、物理クエリで取得
	if obstacles.is_empty():
		_collect_corners_from_physics(origin)
		return

	for obstacle in obstacles:
		if obstacle is StaticBody3D or obstacle is CSGShape3D:
			_extract_corners_from_node(obstacle, origin)


## 物理クエリでコーナーを収集
func _collect_corners_from_physics(origin: Vector3) -> void:
	var space_state := character.get_world_3d().direct_space_state

	# 球形状でオーバーラップチェック
	var shape := SphereShape3D.new()
	shape.radius = view_distance

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = collision_mask

	var results := space_state.intersect_shape(params, 32)

	for result in results:
		var collider = result.collider
		if collider:
			_extract_corners_from_node(collider, origin)


## ノードからコーナーを抽出
func _extract_corners_from_node(node: Node, origin: Vector3) -> void:
	# CollisionShape3Dを探す
	for child in node.get_children():
		if child is CollisionShape3D:
			var col_shape: CollisionShape3D = child
			var shape: Shape3D = col_shape.shape
			var shape_transform: Transform3D = col_shape.global_transform

			if shape is BoxShape3D:
				_extract_box_corners(shape as BoxShape3D, shape_transform, origin)
			elif shape is CylinderShape3D:
				_extract_cylinder_corners(shape as CylinderShape3D, shape_transform, origin)
			# 他の形状も必要に応じて追加


## BoxShape3Dのコーナーを抽出
func _extract_box_corners(shape: BoxShape3D, transform: Transform3D, origin: Vector3) -> void:
	var half_size := shape.size / 2.0

	# ボックスの8頂点（ローカル座標）
	var local_corners := [
		Vector3(-half_size.x, 0, -half_size.z),
		Vector3(half_size.x, 0, -half_size.z),
		Vector3(half_size.x, 0, half_size.z),
		Vector3(-half_size.x, 0, half_size.z),
	]

	for local_corner in local_corners:
		var world_corner: Vector3 = transform * local_corner
		world_corner.y = origin.y  # 高さを合わせる

		# 視野距離内かチェック
		if origin.distance_to(world_corner) <= view_distance * 1.5:
			_obstacle_corners.append(world_corner)


## CylinderShape3Dのコーナーを抽出（円周上の点）
func _extract_cylinder_corners(shape: CylinderShape3D, transform: Transform3D, origin: Vector3) -> void:
	var radius := shape.radius
	var segments := 8  # 円周を8分割

	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		var local_point := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var world_point: Vector3 = transform * local_point
		world_point.y = origin.y

		if origin.distance_to(world_point) <= view_distance * 1.5:
			_obstacle_corners.append(world_point)


## 指定した位置が視野内かどうかを判定
func is_position_visible(target_pos: Vector3) -> bool:
	if not character:
		return false

	var origin := character.global_position + Vector3(0, height_offset, 0)
	var to_target := target_pos - origin
	to_target.y = 0

	# 距離チェック
	if to_target.length() > view_distance:
		return false

	# 角度チェック
	var forward := character.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	to_target = to_target.normalized()

	var angle := forward.angle_to(to_target)
	if angle > deg_to_rad(fov_angle / 2.0):
		return false

	# 視線が遮られていないかチェック
	var space_state := character.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, target_pos + Vector3(0, height_offset, 0))
	query.collision_mask = collision_mask
	query.exclude = [character]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


## 指定したキャラクターが視野内かどうかを判定
func is_character_visible(target: CharacterBody3D) -> bool:
	if not target:
		return false
	return is_position_visible(target.global_position)


## デバッグ用：視野を描画
func get_visibility_polygon_2d(camera: Camera3D) -> PackedVector2Array:
	var points := PackedVector2Array()

	if not camera:
		return points

	for point in visible_points:
		if camera.is_position_behind(point):
			continue
		points.append(camera.unproject_position(point))

	return points
