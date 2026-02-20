@tool
class_name BTApplyMovement extends ActionLeaf
## 物理移動適用（move_and_slide + 重力）
## 速度は blackboard 状態から直接決定（アニメーションblend依存を排除）

const FLOOR_CHECK_INTERVAL := 0.15
const FLOOR_CHECK_DISTANCE := 1.0

var _debug_count: int = 0
var _floor_timer: float = 0.0
var _floor_blocked: bool = false


func tick(actor: Node, blackboard: Blackboard) -> int:
	var body := actor as CharacterBody3D
	var delta := get_physics_process_delta_time()
	var move_dir: Vector3 = blackboard.get_value("move_direction", Vector3.ZERO)

	if move_dir.length_squared() > 0.01:
		var anim_ctrl = actor.get_anim_controller()
		# アクション中（melee/throw/door等）は移動しない
		if anim_ctrl and anim_ctrl.is_action_locked():
			body.velocity.x = 0
			body.velocity.z = 0
		else:
			# 床境界チェック（間引き）: 進行方向に床がなければ停止
			_floor_timer -= delta
			if _floor_timer <= 0.0:
				_floor_timer = FLOOR_CHECK_INTERVAL
				_floor_blocked = _check_no_floor_ahead(body, move_dir)

			if _floor_blocked:
				body.velocity.x = 0
				body.velocity.z = 0
			else:
				var is_sprinting: bool = blackboard.get_value("is_sprinting", false)
				var speed: float = CharacterAnimationController.SPRINT_SPEED if is_sprinting else CharacterAnimationController.WALK_SPEED
				if _debug_count < 3:
					_debug_count += 1
					print("[BTApplyMovement] %s move_dir=%s speed=%.1f sprint=%s locked=%s" % [actor.name, move_dir, speed, is_sprinting, anim_ctrl.is_action_locked() if anim_ctrl else "no_ctrl"])
				body.velocity = move_dir * speed
	else:
		body.velocity.x = 0
		body.velocity.z = 0
		_floor_blocked = false

	if not body.is_on_floor():
		body.velocity.y -= 9.8 * delta

	body.move_and_slide()
	return SUCCESS


## 進行方向の先に床がないかチェック
func _check_no_floor_ahead(body: CharacterBody3D, move_dir: Vector3) -> bool:
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if not space_state:
		return false
	var check_pos: Vector3 = body.global_position + move_dir * FLOOR_CHECK_DISTANCE
	var from := Vector3(check_pos.x, check_pos.y + 2.0, check_pos.z)
	var to := Vector3(check_pos.x, check_pos.y - 0.5, check_pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = MapBase.GROUND_COLLISION_LAYER
	return space_state.intersect_ray(query).is_empty()
