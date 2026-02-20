@tool
class_name BTCombatMove extends ActionLeaf
## 戦闘中の移動制御（接近・ストレイフ・後退・待機）

enum CombatState { APPROACH, STRAFE, RETREAT, HOLD }

# 距離パラメータ
const IDEAL_DISTANCE_MIN := 3.0
const IDEAL_DISTANCE_MAX := 5.0
const RETREAT_DISTANCE := 2.0
const SPRINT_DISTANCE := 8.0

# ヒステリシス（ジッター防止）
const APPROACH_ENTER := 5.0
const APPROACH_EXIT := 4.5
const RETREAT_ENTER := 2.0
const RETREAT_EXIT := 2.5

# HP閾値
const LOW_HP_RATIO := 0.3

# ストレイフ
const STRAFE_SWITCH_MIN := 1.5
const STRAFE_SWITCH_MAX := 3.0

# ホールド
const HOLD_TIME_MIN := 0.5
const HOLD_TIME_MAX := 1.5

# 最小状態持続時間
const MIN_STATE_DURATION := 0.4

# 壁チェック（bt_wander.gdと同じ方式）
const WALL_CHECK_DISTANCE := 1.5
const RAY_CHECK_INTERVAL := 0.15
const FAN_RAY_ANGLE := deg_to_rad(30.0)


var _debug_logged: bool = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var body := actor as CharacterBody3D
	var delta := get_physics_process_delta_time()

	# 敵方向を向く（BTFaceTargetの役割を引き継ぐ）
	var look_dir: Vector3 = blackboard.get_value("look_direction", Vector3.ZERO)
	if look_dir.length_squared() > 0.01:
		actor.set_facing_direction_vec(look_dir)

	# ターゲット取得
	var target_node: Node = null
	if actor.combat_awareness and actor.combat_awareness.has_method("get_current_target"):
		target_node = actor.combat_awareness.get_current_target()

	if not target_node or not is_instance_valid(target_node):
		# ターゲットなし → FAILURE で WanderBranch にフォールバック
		return FAILURE

	if not _debug_logged:
		_debug_logged = true
		print("[BTCombatMove] %s has target=%s" % [actor.name, target_node.name])

	# 初期化
	if not blackboard.has_value("combat_state"):
		blackboard.set_value("combat_state", CombatState.APPROACH)
		blackboard.set_value("combat_state_timer", 0.0)
		blackboard.set_value("strafe_direction", 1)  # 1=右, -1=左
		blackboard.set_value("strafe_switch_timer", randf_range(STRAFE_SWITCH_MIN, STRAFE_SWITCH_MAX))
		blackboard.set_value("combat_ray_timer", randf() * RAY_CHECK_INTERVAL)

	var char_pos: Vector3 = body.global_position
	var enemy_pos: Vector3 = target_node.global_position
	var to_enemy: Vector3 = enemy_pos - char_pos
	to_enemy.y = 0.0
	var dist: float = to_enemy.length()

	if dist < 0.01:
		blackboard.set_value("move_direction", Vector3.ZERO)
		return SUCCESS

	var dir_to_enemy: Vector3 = to_enemy.normalized()
	var current_state: int = blackboard.get_value("combat_state")
	var state_timer: float = blackboard.get_value("combat_state_timer") + delta
	blackboard.set_value("combat_state_timer", state_timer)

	# HP判定
	var low_hp := false
	if actor.has_method("get_health_ratio"):
		low_hp = actor.get_health_ratio() < LOW_HP_RATIO

	# 状態遷移（最小持続時間を超えた場合のみ）
	if state_timer >= MIN_STATE_DURATION:
		var next_state: int = _evaluate_transition(current_state, dist, low_hp)
		if next_state != current_state:
			current_state = next_state
			blackboard.set_value("combat_state", current_state)
			blackboard.set_value("combat_state_timer", 0.0)
			state_timer = 0.0
			if current_state == CombatState.STRAFE:
				blackboard.set_value("strafe_switch_timer", randf_range(STRAFE_SWITCH_MIN, STRAFE_SWITCH_MAX))
			elif current_state == CombatState.HOLD:
				blackboard.set_value("combat_state_timer", -randf_range(HOLD_TIME_MIN, HOLD_TIME_MAX))

	# 移動方向決定
	var move_dir := Vector3.ZERO

	match current_state:
		CombatState.APPROACH:
			move_dir = dir_to_enemy
			if dist > SPRINT_DISTANCE:
				blackboard.set_value("is_sprinting", true)

		CombatState.STRAFE:
			var strafe_dir: int = blackboard.get_value("strafe_direction")
			var strafe_timer: float = blackboard.get_value("strafe_switch_timer") - delta
			blackboard.set_value("strafe_switch_timer", strafe_timer)
			if strafe_timer <= 0.0:
				strafe_dir = -strafe_dir
				blackboard.set_value("strafe_direction", strafe_dir)
				blackboard.set_value("strafe_switch_timer", randf_range(STRAFE_SWITCH_MIN, STRAFE_SWITCH_MAX))
			# 敵に対して横方向（右 or 左）
			move_dir = dir_to_enemy.rotated(Vector3.UP, PI * 0.5 * strafe_dir)

		CombatState.RETREAT:
			move_dir = -dir_to_enemy

		CombatState.HOLD:
			move_dir = Vector3.ZERO

	# 壁チェック（レイキャスト間引き）
	if move_dir.length_squared() > 0.01:
		var ray_timer: float = blackboard.get_value("combat_ray_timer") - delta
		blackboard.set_value("combat_ray_timer", ray_timer)
		if ray_timer <= 0.0:
			blackboard.set_value("combat_ray_timer", RAY_CHECK_INTERVAL)
			if _is_movement_blocked(body, move_dir):
				move_dir = _resolve_wall_avoidance(body, move_dir, current_state, blackboard, dir_to_enemy)

	blackboard.set_value("move_direction", move_dir)
	return SUCCESS


## 状態遷移の評価
func _evaluate_transition(current: int, dist: float, low_hp: bool) -> int:
	# HP低い → RETREAT優先
	if low_hp and dist < IDEAL_DISTANCE_MAX:
		return CombatState.RETREAT

	# 近すぎ → RETREAT
	if dist < RETREAT_ENTER:
		return CombatState.RETREAT

	# 遠すぎ → APPROACH
	if current != CombatState.APPROACH and dist > APPROACH_ENTER:
		return CombatState.APPROACH
	if current == CombatState.APPROACH and dist > APPROACH_EXIT:
		return CombatState.APPROACH

	# 理想距離内
	if dist >= RETREAT_EXIT and dist <= APPROACH_EXIT:
		if current == CombatState.RETREAT or current == CombatState.APPROACH:
			# STRAFEかHOLDへ遷移（ランダム）
			if randf() < 0.7:
				return CombatState.STRAFE
			else:
				return CombatState.HOLD
		if current == CombatState.HOLD:
			# HOLDタイマー完了でSTRAFEへ
			return CombatState.STRAFE

	return current


## 前方3方向ファンレイキャストで壁チェック
func _check_wall_ahead(body: CharacterBody3D, move_dir: Vector3) -> bool:
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if not space_state:
		return false

	var origin: Vector3 = body.global_position + Vector3.UP * 0.5
	var dirs: Array[Vector3] = [move_dir]
	dirs.append(move_dir.rotated(Vector3.UP, FAN_RAY_ANGLE))
	dirs.append(move_dir.rotated(Vector3.UP, -FAN_RAY_ANGLE))

	for dir in dirs:
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + dir * WALL_CHECK_DISTANCE
		)
		query.collision_mask = MapBase.WALL_COLLISION_LAYER
		if not space_state.intersect_ray(query).is_empty():
			return true

	return false


## 進行方向の先に床がないかチェック
func _check_no_floor_ahead(body: CharacterBody3D, move_dir: Vector3) -> bool:
	var space_state := body.get_world_3d().direct_space_state
	if not space_state:
		return false
	var check_pos := body.global_position + move_dir * WALL_CHECK_DISTANCE
	var from := Vector3(check_pos.x, check_pos.y + 2.0, check_pos.z)
	var to := Vector3(check_pos.x, check_pos.y - 0.5, check_pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = MapBase.GROUND_COLLISION_LAYER
	return space_state.intersect_ray(query).is_empty()


## 壁または床なしで進行不可かチェック
func _is_movement_blocked(body: CharacterBody3D, move_dir: Vector3) -> bool:
	return _check_wall_ahead(body, move_dir) or _check_no_floor_ahead(body, move_dir)


## 壁回避: ストレイフ反転 or 状態切替
func _resolve_wall_avoidance(body: CharacterBody3D, move_dir: Vector3, state: int, blackboard: Blackboard, dir_to_enemy: Vector3) -> Vector3:
	match state:
		CombatState.STRAFE:
			# ストレイフ方向を反転
			var strafe_dir: int = blackboard.get_value("strafe_direction")
			strafe_dir = -strafe_dir
			blackboard.set_value("strafe_direction", strafe_dir)
			blackboard.set_value("strafe_switch_timer", randf_range(STRAFE_SWITCH_MIN, STRAFE_SWITCH_MAX))
			var new_dir: Vector3 = dir_to_enemy.rotated(Vector3.UP, PI * 0.5 * strafe_dir)
			# 反転方向も壁or床なしなら停止
			if _is_movement_blocked(body, new_dir):
				return Vector3.ZERO
			return new_dir

		CombatState.RETREAT:
			# 真後ろが壁or床なし → 横に逃げる
			var side := dir_to_enemy.rotated(Vector3.UP, PI * 0.5)
			if not _is_movement_blocked(body, side):
				return side
			side = dir_to_enemy.rotated(Vector3.UP, -PI * 0.5)
			if not _is_movement_blocked(body, side):
				return side
			return Vector3.ZERO

		CombatState.APPROACH:
			# 壁の先に敵 → 停止してストレイフ遷移
			blackboard.set_value("combat_state", CombatState.STRAFE)
			blackboard.set_value("combat_state_timer", 0.0)
			blackboard.set_value("strafe_switch_timer", randf_range(STRAFE_SWITCH_MIN, STRAFE_SWITCH_MAX))
			var strafe_dir: int = blackboard.get_value("strafe_direction")
			return dir_to_enemy.rotated(Vector3.UP, PI * 0.5 * strafe_dir)

	return Vector3.ZERO
