@tool
class_name BTApplyMovement extends ActionLeaf
## 物理移動適用（move_and_slide + 重力）


func tick(actor: Node, blackboard: Blackboard) -> int:
	var delta := get_physics_process_delta_time()
	var move_dir: Vector3 = blackboard.get_value("move_direction", Vector3.ZERO)

	if move_dir.length_squared() > 0.01:
		var anim_ctrl = actor.get_anim_controller()
		var speed: float = anim_ctrl.get_current_speed() if anim_ctrl else CharacterAnimationController.WALK_SPEED
		actor.velocity = move_dir * speed
	else:
		actor.velocity.x = 0
		actor.velocity.z = 0

	if not actor.is_on_floor():
		actor.velocity.y -= 9.8 * delta

	actor.move_and_slide()
	return SUCCESS
