@tool
class_name BTApplyMovement extends ActionLeaf
## 物理移動適用（move_and_slide + 重力）
## 速度は blackboard 状態から直接決定（アニメーションblend依存を排除）


var _debug_count: int = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var delta := get_physics_process_delta_time()
	var move_dir: Vector3 = blackboard.get_value("move_direction", Vector3.ZERO)

	if move_dir.length_squared() > 0.01:
		var anim_ctrl = actor.get_anim_controller()
		# アクション中（melee/throw/door等）は移動しない
		if anim_ctrl and anim_ctrl.is_action_locked():
			actor.velocity.x = 0
			actor.velocity.z = 0
		else:
			var is_sprinting: bool = blackboard.get_value("is_sprinting", false)
			var speed: float = CharacterAnimationController.SPRINT_SPEED if is_sprinting else CharacterAnimationController.WALK_SPEED
			if _debug_count < 3:
				_debug_count += 1
				print("[BTApplyMovement] %s move_dir=%s speed=%.1f sprint=%s locked=%s" % [actor.name, move_dir, speed, is_sprinting, anim_ctrl.is_action_locked() if anim_ctrl else "no_ctrl"])
			actor.velocity = move_dir * speed
	else:
		actor.velocity.x = 0
		actor.velocity.z = 0

	if not actor.is_on_floor():
		actor.velocity.y -= 9.8 * delta

	actor.move_and_slide()
	return SUCCESS
