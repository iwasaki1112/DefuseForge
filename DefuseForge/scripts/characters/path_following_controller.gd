extends Node
## PathFollowingController
## パス追従を管理するコントローラークラス
## キャラクターが描画されたパスに沿って移動し、視線ポイントで向きを変える
## 注意: CharacterAnimationControllerが必須

## シグナル
signal path_started()
signal path_completed()
signal path_cancelled()
signal vision_point_reached(index: int, direction: Vector3)

## スタック検出設定
@export var stuck_threshold: float = 0.05  ## この距離以下の移動をスタックとみなす
@export var stuck_timeout: float = 0.3  ## この時間スタックしたら次のポイントへスキップ
@export var final_destination_radius: float = 0.5  ## 最終目的地への到達判定半径

## 内部状態
var _character: CharacterBody3D = null
var _is_following: bool = false
var _is_running: bool = false
var _current_path: Array[Vector3] = []
var _path_index: int = 0
var _vision_points: Array[Dictionary] = []
var _vision_index: int = 0
var _forced_look_direction: Vector3 = Vector3.ZERO
var _last_move_direction: Vector3 = Vector3.ZERO

## スタック検出用
var _last_position: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0


## セットアップ
func setup(character: CharacterBody3D) -> void:
	_character = character


## パス追従を開始
## @param path: 追従するパス（Vector3の配列）
## @param vision_points: 視線ポイント配列（path_ratio, directionを含むDictionary）
## @param run: 走行モードか
## @return: 開始成功したらtrue
func start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [], run: bool = false) -> bool:
	if not _character:
		push_warning("[PathFollowingController] No character set")
		return false

	if path.size() < 2:
		push_warning("[PathFollowingController] Path too short")
		return false

	_current_path = path.duplicate()
	_vision_points = vision_points.duplicate()
	_vision_index = 0
	_path_index = 0
	_is_running = run
	_is_following = true
	_forced_look_direction = Vector3.ZERO
	_last_move_direction = Vector3.ZERO
	_last_position = _character.global_position
	_stuck_time = 0.0

	path_started.emit()
	return true


## パス追従をキャンセル
func cancel() -> void:
	if not _is_following:
		return

	_is_following = false
	_current_path.clear()
	_vision_points.clear()
	_forced_look_direction = Vector3.ZERO
	_last_move_direction = Vector3.ZERO

	path_cancelled.emit()


## パス追従中か確認
func is_following_path() -> bool:
	return _is_following


## 毎フレームの処理（_physics_processから呼び出す）
func process(delta: float) -> void:
	if not _is_following:
		return

	if not _character or _current_path.size() == 0:
		_finish()
		return

	if _path_index >= _current_path.size():
		_finish()
		return

	var target = _current_path[_path_index]
	var char_pos = _character.global_position
	var to_target = target - char_pos
	to_target.y = 0
	var distance = to_target.length()

	# 最終目的地への距離を計算
	var final_target = _current_path[_current_path.size() - 1]
	var to_final = final_target - char_pos
	to_final.y = 0
	var distance_to_final = to_final.length()

	# 最終目的地に十分近ければ完了
	if distance_to_final < final_destination_radius:
		_finish()
		return

	# スタック検出：移動距離が閾値以下なら時間を加算
	var moved_distance = char_pos.distance_to(_last_position)
	if moved_distance < stuck_threshold * delta * 60:  # deltaを考慮
		_stuck_time += delta
		if _stuck_time >= stuck_timeout:
			# 中間地点でスタック → 次のポイントにスキップ
			_path_index += 1
			_stuck_time = 0.0
			if _path_index >= _current_path.size():
				_finish()
				return
	else:
		_stuck_time = 0.0
	_last_position = char_pos

	# 目標点に到達したら次へ
	if distance < 0.15:
		_path_index += 1
		if _path_index >= _current_path.size():
			_finish()
			return
		target = _current_path[_path_index]
		to_target = target - char_pos
		to_target.y = 0

	# 移動方向を計算
	var move_dir = to_target.normalized()

	# CharacterAnimationControllerから速度を取得（必須）
	var anim_ctrl = _character.get_anim_controller()
	if not anim_ctrl:
		push_warning("[PathFollowingController] CharacterAnimationController is required")
		return

	var speed: float
	if _is_running:
		speed = anim_ctrl.run_speed
	else:
		speed = anim_ctrl.get_current_speed()

	# 最後の移動方向を保存（完了時の向き保持用）
	if move_dir.length_squared() > 0.1:
		_last_move_direction = move_dir

	# 視線方向を更新
	_update_vision_direction()

	# アニメーション更新
	if anim_ctrl:
		var look_dir = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else move_dir
		anim_ctrl.update_animation(move_dir, look_dir, _is_running, delta)

	# 物理移動
	_character.velocity.x = move_dir.x * speed
	_character.velocity.z = move_dir.z * speed

	if not _character.is_on_floor():
		_character.velocity.y -= 9.8 * delta

	_character.move_and_slide()


## 視線方向を更新
func _update_vision_direction() -> void:
	if _vision_points.size() == 0:
		_forced_look_direction = Vector3.ZERO
		return

	var progress = _calculate_path_progress()

	while _vision_index < _vision_points.size():
		var vp = _vision_points[_vision_index]
		if progress >= vp.path_ratio:
			_forced_look_direction = vp.direction
			vision_point_reached.emit(_vision_index, vp.direction)
			_vision_index += 1
		else:
			break


## パスの進行率を計算
func _calculate_path_progress() -> float:
	if _current_path.size() < 2:
		return 0.0

	# パスの総距離を計算
	var total_length = 0.0
	for i in range(1, _current_path.size()):
		total_length += _current_path[i - 1].distance_to(_current_path[i])

	# 現在位置までの距離を計算
	var current_length = 0.0
	for i in range(1, _path_index + 1):
		if i < _current_path.size():
			current_length += _current_path[i - 1].distance_to(_current_path[i])

	# 現在のセグメント内の進行を追加
	if _path_index < _current_path.size() and _character:
		var prev_index = max(0, _path_index - 1)
		var segment_start = _current_path[prev_index]
		var char_pos = _character.global_position
		char_pos.y = segment_start.y
		if _path_index > 0:
			current_length += segment_start.distance_to(char_pos)

	return current_length / total_length if total_length > 0 else 0.0


## パス追従完了
func _finish() -> void:
	# キャラクターの速度を停止
	if _character:
		_character.velocity = Vector3.ZERO

	# 完了時に最後の向きを維持してアイドル状態に
	if _character:
		var anim_ctrl = _character.get_anim_controller()
		if anim_ctrl:
			var final_dir = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else _last_move_direction
			if final_dir.length_squared() < 0.1:
				final_dir = Vector3.FORWARD
			# アイドル状態に遷移（移動方向をゼロに）
			anim_ctrl.update_animation(Vector3.ZERO, final_dir, false, 0.016)

	_is_following = false
	_current_path.clear()
	_vision_points.clear()
	_forced_look_direction = Vector3.ZERO
	_last_move_direction = Vector3.ZERO

	path_completed.emit()
