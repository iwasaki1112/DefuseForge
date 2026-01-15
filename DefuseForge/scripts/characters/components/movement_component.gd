class_name MovementComponent
extends Node

## 移動管理コンポーネント
## パス追従、速度管理、移動マーカー表示を担当
## Slice the Pie: 視線ポイントに基づく上半身回転

signal waypoint_reached(index: int)
signal path_completed
signal locomotion_changed(state: int)  # 0=idle, 1=walk, 2=run
signal vision_direction_changed(direction: Vector3)  # 視線方向変更時

const MovementMarkerScript = preload("res://scripts/effects/movement_marker.gd")

@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var rotation_speed: float = 10.0
@export var waypoint_threshold: float = 0.3
@export var show_movement_marker: bool = true  ## 移動時にマーカーを表示するか

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

## ストレイフモード（視線と移動を分離）
var strafe_mode: bool = false
var _facing_direction: Vector3 = Vector3.FORWARD  # 視線方向（ストレイフ時に固定）

## 視線ポイント（Slice the Pie）用
## 各ポイント: { "path_ratio": float, "anchor": Vector3, "direction": Vector3 }
var _vision_points: Array[Dictionary] = []
var _total_path_length: float = 0.0
var _current_distance_traveled: float = 0.0
var _has_vision_points: bool = false
var _current_vision_direction: Vector3 = Vector3.ZERO

## 移動マーカー
var _movement_marker: MeshInstance3D = null


func _ready() -> void:
	# 親がCharacterBody3Dであることを期待
	_character = get_parent() as CharacterBody3D
	if _character == null:
		push_error("[MovementComponent] Parent must be CharacterBody3D")

	# 移動マーカーを作成（シーンのルートに追加）
	_setup_movement_marker()


## 移動マーカーをセットアップ
func _setup_movement_marker() -> void:
	if not show_movement_marker:
		return

	_movement_marker = MeshInstance3D.new()
	_movement_marker.set_script(MovementMarkerScript)
	_movement_marker.name = "MovementMarker"

	# シーンのルートに追加（キャラクターの子にすると一緒に動いてしまう）
	if _character:
		var root = _character.get_tree().current_scene
		if root:
			root.add_child.call_deferred(_movement_marker)


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
	_total_path_length = _calculate_path_length(points)
	_current_distance_traveled = 0.0
	_has_vision_points = false
	_vision_points.clear()
	_current_vision_direction = Vector3.ZERO
	_update_locomotion_state()

	# 移動マーカーを表示
	_show_movement_marker()


## 視線ポイント付きでパスを設定（Slice the Pie）
## @param movement_points: 移動先のポイント配列
## @param vision_pts: 視線ポイント配列 [{ path_ratio, anchor, direction }, ...]
## @param run: 走るかどうか
func set_path_with_vision_points(movement_points: Array[Vector3], vision_pts: Array, run: bool = false) -> void:
	if movement_points.is_empty():
		stop()
		return

	# 移動パスを設定
	waypoints = movement_points.duplicate()
	current_waypoint_index = 0
	is_running = run
	is_moving = true
	_total_path_length = _calculate_path_length(movement_points)
	_current_distance_traveled = 0.0

	# 視線ポイントを設定
	_vision_points.clear()
	for pt in vision_pts:
		_vision_points.append(pt.duplicate())

	if _vision_points.size() > 0:
		_has_vision_points = true
		# 最初の視線方向は前方（または最初のポイントが0なら最初のポイントの方向）
		_current_vision_direction = Vector3.ZERO
		print("[MovementComponent] Vision points set: %d points" % _vision_points.size())
	else:
		_has_vision_points = false
		_current_vision_direction = Vector3.ZERO

	_update_locomotion_state()
	_show_movement_marker()


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
	_has_vision_points = false
	_vision_points.clear()
	_current_distance_traveled = 0.0
	_current_vision_direction = Vector3.ZERO
	_update_locomotion_state()

	# 移動マーカーを非表示
	_hide_movement_marker()


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


## ストレイフモードを有効化
## @param facing_dir: 視線方向（ワールド座標）
func enable_strafe_mode(facing_dir: Vector3) -> void:
	strafe_mode = true
	_facing_direction = facing_dir.normalized()
	_facing_direction.y = 0


## ストレイフモードを無効化
func disable_strafe_mode() -> void:
	strafe_mode = false


## ストレイフブレンド座標を計算（キャラクターのローカル座標に投影）
## @return: Vector2(x, y) - x: 左右成分, y: 前後成分
func get_strafe_blend() -> Vector2:
	if not is_moving or _input_direction.length_squared() < 0.001:
		return Vector2(0, 1)  # デフォルトは前進

	if _character == null:
		return Vector2(0, 1)

	# キャラクターのローカル座標系を取得
	# このプロジェクトでは +Z が前方（ドキュメント参照）
	var char_forward = _character.global_transform.basis.z  # 前方向（+Z）
	char_forward.y = 0
	if char_forward.length_squared() > 0.001:
		char_forward = char_forward.normalized()
	else:
		char_forward = Vector3.FORWARD

	var char_right = _character.global_transform.basis.x  # 右方向（+X）
	char_right.y = 0
	if char_right.length_squared() > 0.001:
		char_right = char_right.normalized()
	else:
		char_right = Vector3.RIGHT

	# 移動方向（ワールド座標）
	var move_dir = _input_direction.normalized()
	move_dir.y = 0

	# 移動方向をキャラクターのローカル座標に投影
	var forward_component = move_dir.dot(char_forward)  # 前後成分
	var right_component = move_dir.dot(char_right)      # 左右成分

	return Vector2(right_component, forward_component)


## 毎フレーム更新（CharacterBaseから呼ばれる）
## @param delta: フレーム時間
## @return: velocity
func update(delta: float) -> Vector3:
	if _character == null:
		return Vector3.ZERO

	# 移動マーカーの位置を更新
	_update_movement_marker()

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

	# 移動距離を追跡（視線ポイント用）
	var frame_distance = speed * delta
	_current_distance_traveled += frame_distance

	# 視線方向を更新
	if _has_vision_points:
		_update_vision_direction()

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

	# ストレイフモードでなければ移動方向に回転
	if _input_direction.length_squared() > 0.001 and not strafe_mode:
		_rotate_toward(_input_direction, delta)

	# 重力を適用
	if not _character.is_on_floor():
		velocity.y = _character.velocity.y - 9.8 * delta
	else:
		velocity.y = 0

	return velocity


## ========================================
## 移動マーカー管理
## ========================================

## 移動マーカーを表示
func _show_movement_marker() -> void:
	if _movement_marker and show_movement_marker:
		_movement_marker.show_marker()


## 移動マーカーを非表示
func _hide_movement_marker() -> void:
	if _movement_marker:
		_movement_marker.hide_marker()


## 移動マーカーの位置を更新
func _update_movement_marker() -> void:
	if _movement_marker and _character and is_moving:
		_movement_marker.update_position(_character.global_position)


## ========================================
## 視線ポイント（Slice the Pie）API
## ========================================

## 視線ポイントがあるかどうか
func has_vision_points() -> bool:
	return _has_vision_points


## 現在の視線方向を取得（正規化済み、Vector3.ZEROなら視線指定なし）
func get_current_vision_direction() -> Vector3:
	return _current_vision_direction


## 視線ポイントをクリア
func clear_vision_points() -> void:
	_vision_points.clear()
	_has_vision_points = false
	_current_distance_traveled = 0.0
	_current_vision_direction = Vector3.ZERO


## パスの総距離を計算
func _calculate_path_length(points: Array[Vector3]) -> float:
	if points.size() < 2:
		return 0.0

	var total_length: float = 0.0
	for i in range(1, points.size()):
		var p1 = Vector3(points[i - 1].x, 0, points[i - 1].z)
		var p2 = Vector3(points[i].x, 0, points[i].z)
		total_length += p1.distance_to(p2)

	return total_length


## 視線方向を更新（移動進行率に基づく）
func _update_vision_direction() -> void:
	if not _has_vision_points or _vision_points.is_empty():
		_current_vision_direction = Vector3.ZERO
		return

	# 移動パスの進行率を計算
	var progress_ratio: float = 0.0
	if _total_path_length > 0.001:
		progress_ratio = _current_distance_traveled / _total_path_length
		progress_ratio = clampf(progress_ratio, 0.0, 1.0)

	# 現在の進行率に対応する視線方向を取得
	var new_direction = _get_vision_direction_at_ratio(progress_ratio)

	# 方向が変更された場合のみシグナルを発行
	if _current_vision_direction.distance_squared_to(new_direction) > 0.001:
		_current_vision_direction = new_direction
		vision_direction_changed.emit(_current_vision_direction)


## 指定した進行率での視線方向を取得
## 進行率がポイントを超えたら、そのポイントの方向を適用
func _get_vision_direction_at_ratio(ratio: float) -> Vector3:
	if _vision_points.is_empty():
		return Vector3.ZERO

	# 最初の視線ポイント前なら視線なし
	if ratio < _vision_points[0].path_ratio:
		return Vector3.ZERO

	# 現在の進行率に対応するポイントを探す
	var active_direction: Vector3 = Vector3.ZERO

	for point in _vision_points:
		if ratio >= point.path_ratio:
			active_direction = point.direction
		else:
			break

	return active_direction
