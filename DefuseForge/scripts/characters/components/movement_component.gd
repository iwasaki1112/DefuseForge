class_name MovementComponent
extends Node

## 移動管理コンポーネント
## パス追従、速度管理を担当

signal waypoint_reached(index: int)
signal path_completed
signal locomotion_changed(state: int)  # 0=idle, 1=walk, 2=run

@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var rotation_speed: float = 10.0
@export var waypoint_threshold: float = 0.3

## 移動状態
enum LocomotionState { IDLE, WALK, RUN }

var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var is_moving: bool = false
var is_running: bool = false
var locomotion_state: LocomotionState = LocomotionState.IDLE

## キャラクター参照
var _character: CharacterBody3D

## リアルタイム入力モード用
var _input_direction: Vector3 = Vector3.ZERO
var _use_input_mode: bool = false


func _ready() -> void:
	# 親がCharacterBody3Dであることを期待
	_character = get_parent() as CharacterBody3D
	if _character == null:
		push_error("[MovementComponent] Parent must be CharacterBody3D")


## パスを設定して移動開始
## @param points: 移動先のポイント配列
## @param run: 走るかどうか
func set_path(points: Array[Vector3], run: bool = false) -> void:
	if points.is_empty():
		stop()
		return

	waypoints = points.duplicate()
	current_waypoint_index = 0
	is_running = run
	is_moving = true
	_update_locomotion_state()


## 単一の目標地点に移動
## @param target: 移動先
## @param run: 走るかどうか
func move_to(target: Vector3, run: bool = false) -> void:
	var points: Array[Vector3] = [target]
	set_path(points, run)


## 移動を停止
func stop() -> void:
	waypoints.clear()
	current_waypoint_index = 0
	is_moving = false
	is_running = false
	_update_locomotion_state()


## 走る/歩くを切り替え
func set_running(running: bool) -> void:
	if is_running != running:
		is_running = running
		_update_locomotion_state()


## 直接入力による移動（WASD等のリアルタイム入力用）
## @param direction: 移動方向（正規化済み、長さ0で停止）
## @param run: 走るかどうか
func set_input_direction(direction: Vector3, run: bool = false) -> void:
	_input_direction = direction
	is_running = run
	is_moving = direction.length_squared() > 0.001
	_use_input_mode = true
	_update_locomotion_state()


## 毎フレーム更新（CharacterBaseから呼ばれる）
## @param delta: フレーム時間
## @return: velocity
func update(delta: float) -> Vector3:
	if _character == null:
		return Vector3.ZERO

	# リアルタイム入力モードの場合
	if _use_input_mode:
		return _update_input_mode(delta)

	# パス追従モードの場合
	if not is_moving or waypoints.is_empty():
		return Vector3.ZERO

	var current_target = waypoints[current_waypoint_index]
	var current_pos = _character.global_position
	current_pos.y = 0
	var target_xz = Vector3(current_target.x, 0, current_target.z)

	var direction = (target_xz - current_pos).normalized()
	var distance = current_pos.distance_to(target_xz)

	# ウェイポイント到達チェック
	if distance < waypoint_threshold:
		waypoint_reached.emit(current_waypoint_index)
		current_waypoint_index += 1

		if current_waypoint_index >= waypoints.size():
			stop()
			path_completed.emit()
			return Vector3.ZERO

		# 次のウェイポイントに向けて更新
		current_target = waypoints[current_waypoint_index]
		target_xz = Vector3(current_target.x, 0, current_target.z)
		direction = (target_xz - current_pos).normalized()

	# 回転処理
	_rotate_toward(direction, delta)

	# 速度計算
	var speed = run_speed if is_running else walk_speed
	var velocity = direction * speed

	# 重力を適用
	if not _character.is_on_floor():
		velocity.y = _character.velocity.y - 9.8 * delta
	else:
		velocity.y = 0

	return velocity


## 現在の速度を取得（アニメーション用）
func get_current_speed() -> float:
	if not is_moving:
		return 0.0
	return run_speed if is_running else walk_speed


## 目標方向に向かって回転
func _rotate_toward(direction: Vector3, delta: float) -> void:
	if _character == null or direction.length_squared() < 0.001:
		return

	var target_angle = atan2(direction.x, direction.z)
	var current_rotation = _character.rotation.y
	var angle_diff = wrapf(target_angle - current_rotation, -PI, PI)

	_character.rotation.y += angle_diff * rotation_speed * delta


## 移動状態を更新
func _update_locomotion_state() -> void:
	var new_state: LocomotionState
	if not is_moving:
		new_state = LocomotionState.IDLE
	elif is_running:
		new_state = LocomotionState.RUN
	else:
		new_state = LocomotionState.WALK

	if new_state != locomotion_state:
		locomotion_state = new_state
		locomotion_changed.emit(int(locomotion_state))


## リアルタイム入力モードの更新処理
func _update_input_mode(delta: float) -> Vector3:
	var speed = run_speed if is_running else walk_speed
	var velocity = _input_direction * speed

	# 移動方向に回転
	if _input_direction.length_squared() > 0.001:
		_rotate_toward(_input_direction, delta)

	# 重力を適用
	if not _character.is_on_floor():
		velocity.y = _character.velocity.y - 9.8 * delta
	else:
		velocity.y = 0

	return velocity
