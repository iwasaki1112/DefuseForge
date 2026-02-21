@tool
class_name BTWander extends ActionLeaf
## 徘徊処理（壁回避・スタック検知含む）

enum WanderState { IDLE, WALKING }

const WANDER_RADIUS := 6.0
const IDLE_TIME_MIN := 1.5
const IDLE_TIME_MAX := 4.0
const ARRIVAL_THRESHOLD := 0.5
const STUCK_TIME := 2.0
const SPRINT_DISTANCE_THRESHOLD := 3.5
const WALL_CHECK_DISTANCE := 2.0
const RAY_CHECK_INTERVAL := 0.15
const FAN_RAY_ANGLE := deg_to_rad(30.0)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var body := actor as CharacterBody3D
	var delta := get_physics_process_delta_time()

	# 初期化
	if not blackboard.has_value("wander_state"):
		blackboard.set_value("wander_state", WanderState.IDLE)
		blackboard.set_value("wander_target", Vector3.ZERO)
		blackboard.set_value("wander_timer", randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX))
		blackboard.set_value("wander_stuck_pos", body.global_position)
		blackboard.set_value("wander_stuck_timer", 0.0)
		blackboard.set_value("wander_ray_timer", randf() * RAY_CHECK_INTERVAL)

	var state: int = blackboard.get_value("wander_state")

	if state == WanderState.IDLE:
		var timer: float = blackboard.get_value("wander_timer") - delta
		blackboard.set_value("wander_timer", timer)
		if timer <= 0.0:
			var target: Vector3 = _pick_random_target(body)
			var _target_dist: float = Vector3(target.x - body.global_position.x, 0.0, target.z - body.global_position.z).length()
			blackboard.set_value("wander_target", target)
			blackboard.set_value("wander_state", WanderState.WALKING)
			blackboard.set_value("wander_stuck_pos", body.global_position)
			blackboard.set_value("wander_stuck_timer", 0.0)
			blackboard.set_value("wander_ray_timer", 0.0)
		blackboard.set_value("move_direction", Vector3.ZERO)
		return SUCCESS

	# WALKING
	var target_pos: Vector3 = blackboard.get_value("wander_target")
	var char_pos: Vector3 = body.global_position
	var to_target: Vector3 = target_pos - char_pos
	to_target.y = 0.0
	var dist: float = to_target.length()

	# 到着判定
	if dist < ARRIVAL_THRESHOLD:
		blackboard.set_value("wander_state", WanderState.IDLE)
		blackboard.set_value("wander_timer", randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX))
		blackboard.set_value("move_direction", Vector3.ZERO)
		return SUCCESS

	var move_dir: Vector3 = to_target.normalized()

	# スタック検知
	var stuck_timer: float = blackboard.get_value("wander_stuck_timer") + delta
	blackboard.set_value("wander_stuck_timer", stuck_timer)
	if stuck_timer >= STUCK_TIME:
		var stuck_pos: Vector3 = blackboard.get_value("wander_stuck_pos")
		var moved: float = Vector3(char_pos.x - stuck_pos.x, 0.0, char_pos.z - stuck_pos.z).length()
		if moved < 0.3:
			blackboard.set_value("wander_state", WanderState.IDLE)
			blackboard.set_value("wander_timer", randf_range(0.5, 1.0))
			blackboard.set_value("move_direction", Vector3.ZERO)
			return SUCCESS
		blackboard.set_value("wander_stuck_pos", char_pos)
		blackboard.set_value("wander_stuck_timer", 0.0)

	# レイキャスト間引き: 壁チェック
	var ray_timer: float = blackboard.get_value("wander_ray_timer") - delta
	blackboard.set_value("wander_ray_timer", ray_timer)
	if ray_timer <= 0.0:
		blackboard.set_value("wander_ray_timer", RAY_CHECK_INTERVAL)
		if _check_wall_ahead(body, move_dir) or _check_no_floor_ahead(body, move_dir):
			var new_target: Vector3 = _pick_random_target(body)
			blackboard.set_value("wander_target", new_target)
			blackboard.set_value("wander_stuck_pos", char_pos)
			blackboard.set_value("wander_stuck_timer", 0.0)
			var new_dir: Vector3 = new_target - char_pos
			new_dir.y = 0.0
			if new_dir.length_squared() > 0.01:
				move_dir = new_dir.normalized()
			else:
				move_dir = Vector3.ZERO

	# 目標地点が遠い場合はスプリント
	if dist > SPRINT_DISTANCE_THRESHOLD:
		blackboard.set_value("is_sprinting", true)

	blackboard.set_value("move_direction", move_dir)
	return SUCCESS


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


## 指定位置に床タイルがあるかレイキャストで確認
func _has_floor_at(body: CharacterBody3D, pos: Vector3) -> bool:
	var space_state := body.get_world_3d().direct_space_state
	if not space_state:
		return true  # チェックできない場合は許可
	var from := Vector3(pos.x, pos.y + 2.0, pos.z)
	var to := Vector3(pos.x, pos.y - 0.5, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = MapBase.GROUND_COLLISION_LAYER
	return not space_state.intersect_ray(query).is_empty()


## 進行方向の先に床がないかチェック
func _check_no_floor_ahead(body: CharacterBody3D, move_dir: Vector3) -> bool:
	var check_pos := body.global_position + move_dir * WALL_CHECK_DISTANCE
	return not _has_floor_at(body, check_pos)


## ランダムな徘徊目標地点を選択
func _pick_random_target(body: CharacterBody3D) -> Vector3:
	var char_pos: Vector3 = body.global_position
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state

	# 通常距離(2-6m)で5回試行
	for _attempt in range(5):
		var angle := randf() * TAU
		var radius := randf_range(2.0, WANDER_RADIUS)
		var target := Vector3(
			char_pos.x + cos(angle) * radius,
			char_pos.y,
			char_pos.z + sin(angle) * radius
		)

		if space_state:
			var origin: Vector3 = char_pos + Vector3.UP * 0.5
			var target_h: Vector3 = target + Vector3.UP * 0.5
			var query := PhysicsRayQueryParameters3D.create(origin, target_h)
			query.collision_mask = MapBase.WALL_COLLISION_LAYER
			if not space_state.intersect_ray(query).is_empty():
				continue

		# 床タイルがない場所は除外
		if not _has_floor_at(body, target):
			continue

		return target

	# 短距離フォールバック(1-2m)で3回試行
	for _attempt in range(3):
		var angle := randf() * TAU
		var radius := randf_range(1.0, 2.0)
		var target := Vector3(
			char_pos.x + cos(angle) * radius,
			char_pos.y,
			char_pos.z + sin(angle) * radius
		)

		if space_state:
			var origin: Vector3 = char_pos + Vector3.UP * 0.5
			var target_h: Vector3 = target + Vector3.UP * 0.5
			var query := PhysicsRayQueryParameters3D.create(origin, target_h)
			query.collision_mask = MapBase.WALL_COLLISION_LAYER
			if not space_state.intersect_ray(query).is_empty():
				continue

		# 床タイルがない場所は除外
		if not _has_floor_at(body, target):
			continue

		return target

	# 全試行失敗: 現在地に留まる（マップ外への移動を防止）
	return char_pos
