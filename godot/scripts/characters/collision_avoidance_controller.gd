class_name CollisionAvoidanceController
extends RefCounted
## 衝突回避コントローラー
## PathFollowingControllerから衝突回避ロジックを分離
## Door Kickers 2スタイルの味方回避（側方回避・優先度ベース）

## 側方回避設定
const SIDESTEP_DURATION: float = 0.5
const SIDESTEP_DISTANCE: float = 0.8
const HEAD_ON_THRESHOLD: float = -0.5
const SIDESTEP_SPEED_FACTOR: float = 1.0
const AVOIDANCE_COOLDOWN: float = 0.5

## 衝突回避状態
var is_avoiding_collision: bool = false
var is_sidestepping: bool = false
var sidestep_direction: Vector3 = Vector3.ZERO
var sidestep_timer: float = 0.0
var avoidance_blocker: Node = null
var avoidance_timer: float = 0.0
var avoidance_cooldown_timer: float = 0.0

## 参照
var _controller: Node = null  # PathFollowingController
var _character: CharacterBody3D = null


## セットアップ
func setup(controller: Node, character: CharacterBody3D) -> void:
	_controller = controller
	_character = character


## 状態リセット
func reset() -> void:
	is_avoiding_collision = false
	is_sidestepping = false
	sidestep_direction = Vector3.ZERO
	sidestep_timer = 0.0
	avoidance_blocker = null
	avoidance_timer = 0.0


## 味方との距離を取得
func get_distance_to_ally(ally: Node) -> float:
	if not _character or not ally:
		return INF
	var char_pos: Vector3 = _character.global_position
	char_pos.y = 0
	var ally_pos: Vector3 = ally.global_position
	ally_pos.y = 0
	return char_pos.distance_to(ally_pos)


## 前方の味方キャラクターを検出
func detect_ally_ahead(move_dir: Vector3, characters_cache: Array, check_radius: float, check_distance: float) -> Node:
	if not _character or move_dir.length_squared() < 0.001:
		return null

	var char_pos: Vector3 = _character.global_position
	char_pos.y = 0

	for other in characters_cache:
		if other == _character:
			continue
		if not is_instance_valid(other):
			continue
		if "is_alive" in other and not other.is_alive:
			continue
		if not is_ally(other):
			continue

		var other_pos: Vector3 = other.global_position
		other_pos.y = 0

		var distance: float = char_pos.distance_to(other_pos)
		if distance > check_distance:
			continue

		var to_other: Vector3 = (other_pos - char_pos).normalized()
		var dot: float = move_dir.normalized().dot(to_other)
		if dot < 0.5:
			continue

		var perpendicular: Vector3 = to_other - move_dir.normalized() * dot
		if perpendicular.length() > check_radius:
			continue

		return other

	return null


## 相手に道を譲るべきかを判定
func should_yield_to(other: Node) -> bool:
	if not other or not _controller:
		return false

	var other_controller: Node = _find_other_controller(other)

	if not other_controller:
		return false

	if not other_controller.is_following_path():
		return false

	var other_priority: int = other_controller.get_movement_priority()
	var my_priority: int = _controller._movement_priority

	if my_priority != other_priority:
		return my_priority > other_priority

	var my_progress: float = _controller._calculate_path_progress()
	var other_progress: float = 0.0
	if other_controller.has_method("get_current_progress"):
		other_progress = other_controller.get_current_progress()

	if absf(my_progress - other_progress) > 0.05:
		return my_progress < other_progress

	return _character.get_instance_id() > other.get_instance_id()


## 相手が sidestep 中かチェック
func is_other_sidestepping(other: Node) -> bool:
	if not other:
		return false

	var other_controller: Node = _find_other_controller(other)
	if not other_controller:
		return false

	# ハンドラー経由でアクセス（リファクタリング後は_collision_avoidanceハンドラーに状態がある）
	if "_collision_avoidance" in other_controller and other_controller._collision_avoidance:
		return other_controller._collision_avoidance.is_sidestepping
	# fallback: 旧形式の直接アクセス
	return other_controller._is_sidestepping if "_is_sidestepping" in other_controller else false


## 衝突が解消されたかチェック
func check_avoidance_resolved() -> bool:
	if not avoidance_blocker:
		return true

	if not is_instance_valid(avoidance_blocker):
		return true

	if "is_alive" in avoidance_blocker and not avoidance_blocker.is_alive:
		return true

	# 相手がパス追従を完了した場合
	var other_controller := _find_other_controller(avoidance_blocker)
	if other_controller and not other_controller.is_following_path():
		return true

	# 相手との距離が離れた場合
	if _character and _controller:
		var char_pos: Vector3 = _character.global_position
		char_pos.y = 0
		var blocker_pos: Vector3 = avoidance_blocker.global_position
		blocker_pos.y = 0
		if char_pos.distance_to(blocker_pos) > _controller.collision_check_distance * 1.5:
			return true

	return false


## Head-on（対面）衝突かどうかを判定
func is_head_on_collision() -> bool:
	if not avoidance_blocker or not _character:
		return false

	if not is_instance_valid(avoidance_blocker):
		return false

	var other_controller := _find_other_controller(avoidance_blocker)
	if not other_controller:
		return false

	if not other_controller.is_following_path():
		return false

	# 相手も衝突回避中（待機中）ならhead-on
	var other_avoiding := false
	if "_collision_avoidance" in other_controller and other_controller._collision_avoidance:
		other_avoiding = other_controller._collision_avoidance.is_avoiding_collision
	elif "_is_avoiding_collision" in other_controller:
		other_avoiding = other_controller._is_avoiding_collision
	if other_avoiding:
		return true

	if _check_moving_toward_each_other(other_controller):
		return true

	return false


## 相手がすれ違ったか判定
func has_passed_blocker() -> bool:
	if not avoidance_blocker or not is_instance_valid(avoidance_blocker):
		return true

	if not _character or not _controller:
		return false

	var my_pos: Vector3 = _character.global_position
	my_pos.y = 0
	var blocker_pos: Vector3 = avoidance_blocker.global_position
	blocker_pos.y = 0

	var my_move_dir: Vector3 = Vector3.ZERO
	if _controller._path_index < _controller._current_path.size():
		var target = _controller._current_path[_controller._path_index]
		target.y = 0
		my_move_dir = (target - my_pos).normalized()

	if my_move_dir.length_squared() < 0.001:
		return false

	var to_blocker: Vector3 = blocker_pos - my_pos
	to_blocker.y = 0

	return my_move_dir.dot(to_blocker.normalized()) < -0.3


## 衝突回避の待機を開始
func start_collision_halt(blocker: Node) -> void:
	is_avoiding_collision = true
	avoidance_blocker = blocker
	avoidance_timer = 0.0

	if _character:
		_character.velocity = Vector3.ZERO


## 衝突回避の待機を終了
func end_collision_halt() -> void:
	is_avoiding_collision = false
	avoidance_blocker = null
	avoidance_timer = 0.0


## 側方回避を開始
func start_sidestep() -> void:
	if not _character or not avoidance_blocker:
		return

	sidestep_direction = _calculate_sidestep_direction()
	if sidestep_direction.length_squared() < 0.001:
		return

	is_sidestepping = true
	is_avoiding_collision = false
	sidestep_timer = 0.0


## 側方回避を実行
func execute_sidestep(delta: float) -> void:
	if not _character:
		return

	var anim_ctrl = _character.get_anim_controller()
	if not anim_ctrl:
		return

	var speed: float = anim_ctrl.get_current_speed() * SIDESTEP_SPEED_FACTOR

	_character.velocity.x = sidestep_direction.x * speed
	_character.velocity.z = sidestep_direction.z * speed

	if not _character.is_on_floor():
		_character.velocity.y -= 9.8 * delta

	_character.move_and_slide()

	var look_dir: Vector3 = Vector3.ZERO
	if _controller:
		look_dir = _controller._forced_look_direction if _controller._forced_look_direction.length_squared() > 0.1 else sidestep_direction
	else:
		look_dir = sidestep_direction
	anim_ctrl.update_animation(sidestep_direction, look_dir, false, delta)


## 側方回避を終了
func end_sidestep() -> void:
	is_sidestepping = false
	sidestep_direction = Vector3.ZERO
	sidestep_timer = 0.0
	avoidance_blocker = null
	avoidance_timer = 0.0
	avoidance_cooldown_timer = AVOIDANCE_COOLDOWN


## 味方判定
func is_ally(other: Node) -> bool:
	if not _character or not other:
		return false
	if _character is GameCharacter and other is GameCharacter:
		return _character.team == other.team
	if _controller:
		var player_state = _controller.get_node_or_null("/root/PlayerState")
		if player_state and player_state.has_method("is_friendly"):
			return player_state.is_friendly(_character) == player_state.is_friendly(other)
	return false


## ========================================
## 内部ヘルパー
## ========================================

func _find_other_controller(other: Node) -> Node:
	if not other or not _controller:
		return null

	var other_id: int = other.get_instance_id()
	var path_exec_manager = _controller.get_node_or_null("/root/GameScreen/PathExecutionManager")
	if path_exec_manager and "_path_controllers" in path_exec_manager:
		var controllers: Dictionary = path_exec_manager._path_controllers
		if controllers.has(other_id):
			return controllers[other_id]

	# fallback: 親ノードから探す
	var parent = _controller.get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling != _controller and sibling.has_method("is_following_path"):
				if "_character" in sibling and sibling._character:
					if sibling._character.get_instance_id() == other_id:
						return sibling

	return null


func _check_moving_toward_each_other(other_controller: Node) -> bool:
	if not _character or not avoidance_blocker:
		return false

	var my_pos: Vector3 = _character.global_position
	my_pos.y = 0
	var other_pos: Vector3 = avoidance_blocker.global_position
	other_pos.y = 0

	var to_other: Vector3 = (other_pos - my_pos).normalized()

	if other_controller._current_path.size() == 0:
		return false

	var other_path_index: int = other_controller._path_index
	if other_path_index >= other_controller._current_path.size():
		return false

	var other_target: Vector3 = other_controller._current_path[other_path_index]
	other_target.y = 0

	var other_move_dir: Vector3 = (other_target - other_pos).normalized()

	var dot: float = other_move_dir.dot(to_other)
	return dot < HEAD_ON_THRESHOLD


func _calculate_sidestep_direction() -> Vector3:
	if not _character or not avoidance_blocker or not _controller:
		return Vector3.ZERO

	var char_pos: Vector3 = _character.global_position
	char_pos.y = 0

	var my_move_dir: Vector3 = Vector3.ZERO
	if _controller._path_index < _controller._current_path.size():
		var target = _controller._current_path[_controller._path_index]
		target.y = 0
		my_move_dir = (target - char_pos).normalized()

	if my_move_dir.length_squared() < 0.001:
		return Vector3.ZERO

	# 右側通行ルール
	var right: Vector3 = Vector3(my_move_dir.z, 0, -my_move_dir.x)

	if _is_direction_clear(right):
		return right
	elif _is_direction_clear(-right):
		return -right

	return Vector3.ZERO


func _is_direction_clear(direction: Vector3) -> bool:
	if not _character:
		return false

	var space_state = _character.get_world_3d().direct_space_state
	if not space_state:
		return true

	var from: Vector3 = _character.global_position + Vector3(0, 0.5, 0)
	var to: Vector3 = from + direction.normalized() * SIDESTEP_DISTANCE

	var query = PhysicsRayQueryParameters3D.create(from, to, 2)
	query.exclude = [_character.get_rid()]
	var result = space_state.intersect_ray(query)

	return result.is_empty()
