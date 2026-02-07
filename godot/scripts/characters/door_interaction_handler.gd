class_name DoorInteractionHandler
extends RefCounted
## ドアインタラクションハンドラ
## PathFollowingControllerからドア関連ロジックを分離

## ドア状態
var is_waiting_for_door: bool = false
var is_waiting_for_closed_door: bool = false
var waiting_door: Node3D = null

## 参照
var _controller: Node = null  # PathFollowingController
var _character: CharacterBody3D = null


## セットアップ
func setup(controller: Node, character: CharacterBody3D) -> void:
	_controller = controller
	_character = character


## 状態リセット
func reset() -> void:
	is_waiting_for_door = false
	is_waiting_for_closed_door = false
	waiting_door = null


## ドアポイントのチェックと処理
## @return: ドアポイントに到達してパスを停止した場合はtrue
func check_door_points(progress: float, door_points: Array[Dictionary], door_index_ref: Array[int]) -> bool:
	const END_TOLERANCE: float = 0.03
	const POINT_REACH_DISTANCE: float = 0.8

	while door_index_ref[0] < door_points.size():
		var dp = door_points[door_index_ref[0]]
		var target_ratio = dp.path_ratio

		var ratio_reached = false
		if target_ratio > 0.97:
			ratio_reached = progress >= (target_ratio - END_TOLERANCE)
		else:
			ratio_reached = progress >= target_ratio

		if ratio_reached:
			var actually_reached = true
			if dp.has("anchor") and _character:
				var char_pos = _character.global_position
				char_pos.y = 0
				var anchor = dp.anchor
				anchor.y = 0
				var distance = char_pos.distance_to(anchor)
				actually_reached = distance < POINT_REACH_DISTANCE

			if actually_reached:
				is_waiting_for_door = true
				door_index_ref[0] += 1

				var door = dp.door_node if dp.has("door_node") else null
				if _controller:
					_controller.door_point_reached.emit(door_index_ref[0] - 1, door)
				return true
			else:
				break
		else:
			break
	return false


## ドアキック完了後にパス追従を再開
func resume_after_door() -> void:
	is_waiting_for_door = false


## 移動方向に閉じたドアがあるかチェック
func check_closed_door_ahead(move_dir: Vector3) -> Node3D:
	if not _character:
		return null

	var space_state = _character.get_world_3d().direct_space_state
	if not space_state:
		return null

	var from = _character.global_position + Vector3(0, 0.5, 0)
	var to = from + move_dir.normalized() * 0.8

	var query = PhysicsRayQueryParameters3D.create(from, to, 2)
	query.exclude = [_character.get_rid()]
	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return null

	var collider = result.collider
	if not collider:
		return null

	var door = _find_closed_door_in_hierarchy(collider)
	return door


## 待機中のドアが開いたかチェック
func check_waiting_door_opened() -> bool:
	if not is_instance_valid(waiting_door):
		return true
	return waiting_door.is_in_group("open_doors")


## 指定されたドアがDoorポイントに設定されているかチェック
func is_door_in_points(door: Node3D, door_points: Array[Dictionary]) -> bool:
	if not door:
		return false

	for dp in door_points:
		if dp.has("door_node") and dp.door_node == door:
			return true
	return false


## ========================================
## 内部ヘルパー
## ========================================

func _find_closed_door_in_hierarchy(node: Node) -> Node3D:
	while node:
		if node.is_in_group("doors"):
			if not node.is_in_group("open_doors"):
				return node as Node3D
			else:
				return null
		node = node.get_parent()
	return null
