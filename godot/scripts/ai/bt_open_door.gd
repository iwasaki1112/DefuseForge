@tool
class_name BTOpenDoor extends ActionLeaf
## ドア開けアクション（ドアに接近 → 開ける）
## 常に SUCCESS を返し UpdateAnimation/ApplyMovement を毎tick通す
## (RUNNING は AlwaysSucceedDecorator を貫通し後段をスキップするため不可)

const APPROACH_ARRIVAL := 0.3  ## 接近完了の余裕マージン


func tick(actor: Node, blackboard: Blackboard) -> int:
	var door: Node3D = blackboard.get_value("nearby_door", null)
	if not door or not is_instance_valid(door):
		blackboard.erase_value("nearby_door")
		return FAILURE

	# 既に開いているなら終了
	if door.is_in_group("open_doors"):
		blackboard.erase_value("nearby_door")
		return FAILURE

	var anim_ctrl = actor.get_anim_controller()
	if not anim_ctrl:
		return FAILURE

	# ドア開けアニメ再生中は待機（is_action_locked()がApplyMovementを止める）
	if anim_ctrl.is_opening_door():
		return SUCCESS

	# パネル中心位置
	var door_pos: Vector3 = door.global_position + door.global_transform.basis * Vector3(-0.5, 0.0, 0.0)
	var dist: float = actor.global_position.distance_to(door_pos)

	# まだ遠い → ドアに向かって歩く（SUCCESSでApplyMovementを通す）
	if dist > GameConstants.DOOR_OPEN_DISTANCE + APPROACH_ARRIVAL:
		var move_dir: Vector3 = (door_pos - actor.global_position).normalized()
		move_dir.y = 0.0
		blackboard.set_value("move_direction", move_dir)
		actor.set_facing_direction_vec(move_dir)
		return SUCCESS

	# 十分近い → ドア開けアニメ開始
	var dir: Vector3 = (door_pos - actor.global_position).normalized()
	dir.y = 0.0
	actor.set_facing_direction_vec(dir)
	blackboard.set_value("move_direction", Vector3.ZERO)

	anim_ctrl.play_door_open()

	# impact シグナルで実際にドアを開く
	var game_screen = actor.get_tree().get_first_node_in_group("game_screen")
	if game_screen and game_screen.game_manager and game_screen.game_manager.door_service:
		var door_service = game_screen.game_manager.door_service
		var captured_door := door
		var captured_actor := actor
		anim_ctrl.door_open_impact.connect(
			func(): door_service.on_door_open_done(captured_door, captured_actor),
			CONNECT_ONE_SHOT
		)

	blackboard.erase_value("nearby_door")
	return SUCCESS
