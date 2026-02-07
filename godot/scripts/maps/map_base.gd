class_name MapBase
extends Node3D
## マップ基底クラス
## 壁/ドア/床のコリジョン設定とFoWオクルーダー抽出の共通処理

const GROUND_COLLISION_LAYER: int = 1
const WALL_COLLISION_LAYER: int = 2

## マップ名（ログ用、サブクラスでオーバーライド）
var _map_name: String = "MAP"


func _ready() -> void:
	_setup_collisions(self)
	_notify_fow_system()


## コリジョンレイヤーを設定
func _setup_collisions(node: Node) -> void:
	if node is StaticBody3D:
		var node_name_lower := node.name.to_lower()

		# ノード自体のプレフィックスをチェック
		if node_name_lower.begins_with("ground_"):
			# 床オブジェクトはレイヤー1（床コリジョン）
			node.collision_layer = GROUND_COLLISION_LAYER
		elif node_name_lower.begins_with("wall_") or node_name_lower.begins_with("door_"):
			# 壁/ドアオブジェクトはレイヤー2（壁コリジョン）
			node.collision_layer = WALL_COLLISION_LAYER
			if node_name_lower.begins_with("door_"):
				node.add_to_group(GameConstants.GROUP_DOORS)
				if Debug.enabled: print("[%s] Added door to group: %s" % [_map_name, node.name])
		else:
			# 親ノードのプレフィックスをチェック
			var parent: Node = node.get_parent()
			if parent:
				var parent_name_lower := parent.name.to_lower()
				if parent_name_lower.begins_with("ground_"):
					node.collision_layer = GROUND_COLLISION_LAYER
				elif parent_name_lower.begins_with("wall_") or parent_name_lower.begins_with("door_"):
					node.collision_layer = WALL_COLLISION_LAYER
				if parent_name_lower.begins_with("door_"):
					parent.add_to_group(GameConstants.GROUP_DOORS)
					if Debug.enabled: print("[%s] Added door to group: %s" % [_map_name, parent.name])

	for child in node.get_children():
		_setup_collisions(child)


## FoWシステムにオクルーダー抽出を通知
func _notify_fow_system() -> void:
	# VisionServiceを探す（GameScreen経由）
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	if Debug.enabled: print("[%s] _notify_fow_system - game_screen: %s" % [_map_name, game_screen != null])
	if game_screen and game_screen.has_method("get_vision_service"):
		var vision_service = game_screen.get_vision_service()
		var fow_str := str(vision_service.fog_of_war_system != null) if vision_service else "false"
		if Debug.enabled: print("[%s] vision_service: %s, fow_system: %s" % [_map_name, vision_service != null, fow_str])
		if vision_service and vision_service.fog_of_war_system:
			# ground_ノードからマップサイズを計算してFoWに設定
			var ground_size := _calculate_ground_bounds()
			if ground_size != Vector2.ZERO:
				vision_service.fog_of_war_system.set_map_size(ground_size)
				if Debug.enabled: print("[%s] Set FoW map_size from ground bounds: %s" % [_map_name, ground_size])
			vision_service.fog_of_war_system.extract_occluders_from_map(self)
			if Debug.enabled: print("[%s] Extracted occluders for FoW system" % _map_name)
		else:
			# FoWシステムが準備できていない場合は遅延呼び出し
			if Debug.enabled: print("[%s] FoW system not ready, scheduling deferred call" % _map_name)
			call_deferred("_notify_fow_system_deferred")
	else:
		if Debug.enabled: print("[%s] game_screen not ready, scheduling deferred call" % _map_name)
		call_deferred("_notify_fow_system_deferred")


## 遅延オクルーダー抽出
func _notify_fow_system_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	if game_screen and game_screen.has_method("get_vision_service"):
		var vision_service = game_screen.get_vision_service()
		if vision_service and vision_service.fog_of_war_system:
			# ground_ノードからマップサイズを計算してFoWに設定
			var ground_size := _calculate_ground_bounds()
			if ground_size != Vector2.ZERO:
				vision_service.fog_of_war_system.set_map_size(ground_size)
				if Debug.enabled: print("[%s] Set FoW map_size from ground bounds (deferred): %s" % [_map_name, ground_size])
			vision_service.fog_of_war_system.extract_occluders_from_map(self)
			if Debug.enabled: print("[%s] Extracted occluders for FoW system (deferred)" % _map_name)


## ground_プレフィックスノードからマップの床サイズを計算
func _calculate_ground_bounds() -> Vector2:
	var bounds := {
		"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF),
		"found": false
	}

	_collect_ground_bounds(self, bounds)

	if not bounds["found"]:
		if Debug.enabled: print("[%s] No ground_ nodes found for bounds calculation" % _map_name)
		return Vector2.ZERO

	# X-Z平面でのサイズを返す（Yは高さなので無視）
	var size_x: float = bounds["max"].x - bounds["min"].x
	var size_z: float = bounds["max"].z - bounds["min"].z
	if Debug.enabled: print("[%s] Ground bounds: min=%s, max=%s, size=(%s, %s)" % [_map_name, bounds["min"], bounds["max"], size_x, size_z])
	return Vector2(size_x, size_z)


## 再帰的にground_ノードを探索してバウンディングボックスを収集
func _collect_ground_bounds(node: Node, bounds: Dictionary) -> void:
	var node_name_lower := node.name.to_lower()
	var is_ground := node_name_lower.begins_with("ground_")

	# 親がground_の場合も対象
	if not is_ground and node.get_parent():
		var parent_name_lower := node.get_parent().name.to_lower()
		is_ground = parent_name_lower.begins_with("ground_")

	if is_ground and node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var aabb := mesh_instance.get_aabb()
		var gtransform := mesh_instance.global_transform

		# AABBの8頂点をグローバル座標に変換してmin/maxを更新
		for i in range(8):
			var corner := aabb.position
			if i & 1: corner.x += aabb.size.x
			if i & 2: corner.y += aabb.size.y
			if i & 4: corner.z += aabb.size.z
			var global_corner: Vector3 = gtransform * corner

			bounds["min"].x = minf(bounds["min"].x, global_corner.x)
			bounds["min"].y = minf(bounds["min"].y, global_corner.y)
			bounds["min"].z = minf(bounds["min"].z, global_corner.z)
			bounds["max"].x = maxf(bounds["max"].x, global_corner.x)
			bounds["max"].y = maxf(bounds["max"].y, global_corner.y)
			bounds["max"].z = maxf(bounds["max"].z, global_corner.z)
		bounds["found"] = true

	for child in node.get_children():
		_collect_ground_bounds(child, bounds)
