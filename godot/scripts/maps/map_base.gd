class_name MapBase
extends Node3D
## マップ基底クラス
## 壁/ドアのコリジョン設定とFoWオクルーダー抽出の共通処理

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

		# ノード自体が wall_ または door_ プレフィックスを持つ場合
		if node_name_lower.begins_with("wall_") or node_name_lower.begins_with("door_"):
			node.collision_layer = WALL_COLLISION_LAYER
			if node_name_lower.begins_with("door_"):
				node.add_to_group(GameConstants.GROUP_DOORS)
				print("[%s] Added door to group: %s" % [_map_name, node.name])
		else:
			# 親ノードが wall_ または door_ プレフィックスを持つ場合
			var parent: Node = node.get_parent()
			if parent:
				var parent_name_lower := parent.name.to_lower()
				if parent_name_lower.begins_with("wall_") or parent_name_lower.begins_with("door_"):
					node.collision_layer = WALL_COLLISION_LAYER
				if parent_name_lower.begins_with("door_"):
					parent.add_to_group(GameConstants.GROUP_DOORS)
					print("[%s] Added door to group: %s" % [_map_name, parent.name])

	for child in node.get_children():
		_setup_collisions(child)


## FoWシステムにオクルーダー抽出を通知
func _notify_fow_system() -> void:
	# VisionServiceを探す（GameScreen経由）
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	print("[%s] _notify_fow_system - game_screen: %s" % [_map_name, game_screen != null])
	if game_screen and game_screen.has_method("get_vision_service"):
		var vision_service = game_screen.get_vision_service()
		print("[%s] vision_service: %s, fow_system: %s" % [_map_name, vision_service != null, vision_service.fog_of_war_system != null if vision_service else false])
		if vision_service and vision_service.fog_of_war_system:
			vision_service.fog_of_war_system.extract_occluders_from_map(self)
			print("[%s] Extracted occluders for FoW system" % _map_name)
		else:
			# FoWシステムが準備できていない場合は遅延呼び出し
			print("[%s] FoW system not ready, scheduling deferred call" % _map_name)
			call_deferred("_notify_fow_system_deferred")
	else:
		print("[%s] game_screen not ready, scheduling deferred call" % _map_name)
		call_deferred("_notify_fow_system_deferred")


## 遅延オクルーダー抽出
func _notify_fow_system_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	if game_screen and game_screen.has_method("get_vision_service"):
		var vision_service = game_screen.get_vision_service()
		if vision_service and vision_service.fog_of_war_system:
			vision_service.fog_of_war_system.extract_occluders_from_map(self)
			print("[%s] Extracted occluders for FoW system (deferred)" % _map_name)
