@tool
class_name BTUpdateAnimation extends ActionLeaf
## アニメーション更新


var _debug_logged: bool = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var anim_ctrl = actor.get_anim_controller()
	if not anim_ctrl:
		if not _debug_logged:
			_debug_logged = true
			print("[BTUpdateAnimation] %s FAILURE: no anim_ctrl" % actor.name)
		return FAILURE

	var delta := get_physics_process_delta_time()
	var move_dir: Vector3 = blackboard.get_value("move_direction", Vector3.ZERO)
	var look_dir: Vector3 = blackboard.get_value("look_direction", Vector3.ZERO)
	var is_sprinting: bool = blackboard.get_value("is_sprinting", false)

	anim_ctrl.update_animation(move_dir, look_dir, is_sprinting, delta)
	return SUCCESS
