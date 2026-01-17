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
@export var stuck_threshold: float = 0.01  ## この距離以下の移動をスタックとみなす
@export var stuck_timeout: float = 0.5  ## この時間スタックしたら次のポイントへスキップ
@export var final_destination_radius: float = 0.5  ## 最終目的地への到達判定半径
@export var ally_collision_radius: float = 1.0  ## 味方との衝突検出半径

## キャッシュ設定
const CHARACTERS_CACHE_INTERVAL: float = 0.15  ## キャラクターキャッシュ更新間隔（150ms）

## 内部状態
var _character: CharacterBody3D = null
var _is_following: bool = false
var _is_running: bool = false
var _current_path: Array[Vector3] = []
var _path_index: int = 0
var _vision_points: Array[Dictionary] = []
var _vision_index: int = 0
var _run_segments: Array[Dictionary] = []  # { start_ratio, end_ratio }
var _forced_look_direction: Vector3 = Vector3.ZERO
var _last_move_direction: Vector3 = Vector3.ZERO
var _combat_awareness: Node = null  # CombatAwarenessComponent

## スタック検出用
var _last_position: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0

## キャラクターキャッシュ（GC負荷削減）
var _characters_cache: Array = []
var _characters_cache_timer: float = CHARACTERS_CACHE_INTERVAL  # 初回即時更新


## セットアップ
func setup(character: CharacterBody3D) -> void:
	_character = character


## Set combat awareness component for automatic enemy aiming
func set_combat_awareness(component: Node) -> void:
	_combat_awareness = component


## パス追従を開始
## @param path: 追従するパス（Vector3の配列）
## @param vision_points: 視線ポイント配列（path_ratio, directionを含むDictionary）
## @param run_segments: Run区間配列（start_ratio, end_ratioを含むDictionary）
## @param run: 走行モードか（全体を走る場合）
## @return: 開始成功したらtrue
func start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [],
		run_segments: Array[Dictionary] = [], run: bool = false) -> bool:
	if not _character:
		push_warning("[PathFollowingController] No character set")
		return false

	if path.size() < 2:
		push_warning("[PathFollowingController] Path too short (size=%d)" % path.size())
		return false

	_current_path = path.duplicate()
	_vision_points = vision_points.duplicate()
	_run_segments = run_segments.duplicate()
	_vision_index = 0
	_is_running = run
	_is_following = true
	_forced_look_direction = Vector3.ZERO
	_last_move_direction = Vector3.ZERO
	_last_position = _character.global_position
	_stuck_time = 0.0

	# キャラクターの現在位置に最も近いパスポイントから開始
	# （接続線の最初のポイントはキャラクター位置なのでスキップ）
	_path_index = 0
	var char_pos = _character.global_position
	char_pos.y = 0
	if _current_path.size() > 0:
		var first_point = _current_path[0]
		first_point.y = 0
		if char_pos.distance_to(first_point) < 0.2:
			# キャラクターがパスの最初のポイントにいる場合、次のポイントを目指す
			_path_index = 1

	print("[PathFollowingController] %s: Started with %d points, starting from index %d, first target: %s" % [
		_character.name, _current_path.size(), _path_index,
		str(_current_path[_path_index]) if _path_index < _current_path.size() else "none"
	])

	path_started.emit()
	return true


## パス追従をキャンセル
func cancel() -> void:
	if not _is_following:
		return

	_is_following = false
	_current_path.clear()
	_vision_points.clear()
	_run_segments.clear()
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

	# キャラクターキャッシュ更新（150ms間隔）
	_characters_cache_timer += delta
	if _characters_cache_timer >= CHARACTERS_CACHE_INTERVAL:
		_characters_cache_timer = 0.0
		_characters_cache = get_tree().get_nodes_in_group("characters")

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

	# 味方衝突検出: 最終目的地付近に味方がいれば現在位置で停止
	if distance_to_final < final_destination_radius + ally_collision_radius:
		if _is_ally_at_destination():
			_finish()
			return

	# スタック検出：移動距離が閾値以下なら時間を加算
	var moved_distance = char_pos.distance_to(_last_position)
	if moved_distance < stuck_threshold * delta * 60:  # deltaを考慮
		_stuck_time += delta
		if _stuck_time >= stuck_timeout:
			# 中間地点でスタック → 次のポイントにスキップ
			print("[PathFollowingController] %s: STUCK at point %d, skipping to %d" % [_character.name, _path_index, _path_index + 1])
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
		print("[PathFollowingController] %s: Reached point %d, moving to %d" % [_character.name, _path_index, _path_index + 1])
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

	# Run区間チェック
	var progress = _calculate_path_progress()
	var in_run_segment = _is_in_run_segment(progress)

	# 速度選択: Run区間内なら走る、そうでなければ既存ロジック
	var speed: float
	var is_running_now: bool
	if in_run_segment:
		speed = anim_ctrl.run_speed
		is_running_now = true
	elif _is_running:
		speed = anim_ctrl.run_speed
		is_running_now = true
	else:
		speed = anim_ctrl.get_current_speed()
		is_running_now = false

	# 最後の移動方向を保存（完了時の向き保持用）
	if move_dir.length_squared() > 0.1:
		_last_move_direction = move_dir

	# 視線方向を更新（Run区間外のみ）
	if not in_run_segment:
		_update_vision_direction()

	# Combat awarenessを処理（Run区間外のみ - Run中は敵をスルー）
	if not in_run_segment:
		if _combat_awareness and _combat_awareness.has_method("process"):
			_combat_awareness.process(delta)

	# アニメーション更新
	if anim_ctrl:
		var look_dir: Vector3 = Vector3.ZERO

		# Run区間中は移動方向のみ（敵認識・視線ポイント無視）
		if in_run_segment:
			look_dir = move_dir
		else:
			# 優先順位: 敵視認 > 視線ポイント > 移動方向
			# 1. 敵視認チェック（最優先）
			if _combat_awareness and _combat_awareness.has_method("is_tracking_enemy"):
				if _combat_awareness.is_tracking_enemy():
					look_dir = _combat_awareness.get_override_look_direction()

			# 2. 視線ポイント or 移動方向
			if look_dir.length_squared() < 0.1:
				look_dir = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else move_dir

		anim_ctrl.update_animation(move_dir, look_dir, is_running_now, delta)

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
## キャラクターの実際の位置に基づいて、パス上の最も近い点を見つけて進行率を計算
func _calculate_path_progress() -> float:
	if _current_path.size() < 2 or not _character:
		return 0.0

	var char_pos = _character.global_position
	char_pos.y = 0

	# パスの総距離を計算
	var total_length = 0.0
	for i in range(1, _current_path.size()):
		total_length += _current_path[i - 1].distance_to(_current_path[i])

	if total_length < 0.001:
		return 0.0

	# 各セグメントを調べて、キャラクターに最も近い点を見つける
	var best_distance = INF
	var best_accumulated_length = 0.0
	var accumulated_length = 0.0

	for i in range(1, _current_path.size()):
		var p1 = _current_path[i - 1]
		var p2 = _current_path[i]
		p1.y = 0
		p2.y = 0

		var segment = p2 - p1
		var segment_length = segment.length()
		if segment_length < 0.001:
			accumulated_length += segment_length
			continue

		# セグメント上の最近点を計算
		var t = clampf((char_pos - p1).dot(segment) / (segment_length * segment_length), 0.0, 1.0)
		var point_on_segment = p1 + segment * t
		var distance = char_pos.distance_to(point_on_segment)

		# 現在のセグメント以降のみ考慮（戻らない）
		if i >= _path_index or i == _path_index:
			if distance < best_distance:
				best_distance = distance
				best_accumulated_length = accumulated_length + segment_length * t

		accumulated_length += segment_length

	return best_accumulated_length / total_length


## Run区間内かどうかを判定
func _is_in_run_segment(progress: float) -> bool:
	for seg in _run_segments:
		if progress >= seg.start_ratio and progress < seg.end_ratio:
			return true
	return false


## パス追従完了
func _finish() -> void:
	# キャラクターの速度を停止
	if _character:
		_character.velocity = Vector3.ZERO

	# 完了時に最後の向きを維持してアイドル状態に
	# 優先順位: 敵視認 > 視線ポイント > 移動方向
	if _character:
		var anim_ctrl = _character.get_anim_controller()
		if anim_ctrl:
			var final_dir: Vector3 = Vector3.ZERO

			# 敵を追跡中なら敵方向を維持
			if _combat_awareness and _combat_awareness.has_method("is_tracking_enemy"):
				if _combat_awareness.is_tracking_enemy():
					final_dir = _combat_awareness.get_override_look_direction()

			# 視線ポイント or 移動方向
			if final_dir.length_squared() < 0.1:
				final_dir = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else _last_move_direction

			if final_dir.length_squared() < 0.1:
				final_dir = Vector3.FORWARD
			# アイドル状態に遷移（移動方向をゼロに）
			anim_ctrl.update_animation(Vector3.ZERO, final_dir, false, 0.016)

	_is_following = false
	_current_path.clear()
	_vision_points.clear()
	_run_segments.clear()
	_forced_look_direction = Vector3.ZERO
	_last_move_direction = Vector3.ZERO

	path_completed.emit()


## 味方判定
func _is_ally(other: Node) -> bool:
	if not _character or not other:
		return false
	if _character is GameCharacter and other is GameCharacter:
		return _character.team == other.team
	var player_state = get_node_or_null("/root/PlayerState")
	if player_state and player_state.has_method("is_friendly"):
		return player_state.is_friendly(_character) == player_state.is_friendly(other)
	return false


## 最終目的地付近に味方キャラクターがいるかチェック
func _is_ally_at_destination() -> bool:
	if _current_path.size() == 0:
		return false

	var final_destination = _current_path[_current_path.size() - 1]
	final_destination.y = 0

	# キャッシュを使用（GC負荷削減）
	for character in _characters_cache:
		if character == _character:
			continue
		if "is_alive" in character and not character.is_alive:
			continue
		if not _is_ally(character):
			continue

		var char_pos = character.global_position
		char_pos.y = 0
		if char_pos.distance_to(final_destination) < ally_collision_radius:
			return true

	return false
