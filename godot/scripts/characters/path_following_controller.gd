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
signal grenade_marker_reached(index: int, marker_data: Dictionary)
signal smoke_grenade_marker_reached(index: int, marker_data: Dictionary)
signal door_marker_reached(index: int, door: Node3D)

## スタック検出設定
@export var stuck_threshold: float = 0.01  ## この距離以下の移動をスタックとみなす
@export var stuck_timeout: float = 0.5  ## この時間スタックしたら次のポイントへスキップ
@export var final_destination_radius: float = 0.1  ## 最終目的地への到達判定半径
@export var ally_collision_radius: float = 1.0  ## 味方との衝突検出半径

## 衝突回避設定
@export var collision_check_radius: float = 0.8  ## 前方衝突検出の半径
@export var collision_check_distance: float = 1.5  ## 前方衝突検出の距離
@export var avoidance_timeout: float = 3.0  ## 回避タイムアウト（この時間経過で強制解除）

## キャッシュ設定
const CHARACTERS_CACHE_INTERVAL: float = 0.15  ## キャラクターキャッシュ更新間隔（150ms）
const COLLISION_CHECK_INTERVAL: float = 0.1  ## 衝突検出間隔（100ms、モバイル最適化）

## 内部状態
var _character: CharacterBody3D = null
var _is_following: bool = false
var _is_running: bool = false
var _current_path: Array[Vector3] = []
var _path_index: int = 0
var _vision_points: Array[Dictionary] = []
var _vision_index: int = 0
var _run_segments: Array[Dictionary] = []  # { start_ratio, end_ratio }
var _clear_points: Array[Dictionary] = []  # { path_ratio }
var _clear_index: int = 0
var _grenade_markers: Array[Dictionary] = []  # { path_ratio, anchor, target_pos, bounce_point? }
var _grenade_index: int = 0
var _smoke_grenade_markers: Array[Dictionary] = []  # { path_ratio, anchor, target_pos, bounce_point? }
var _smoke_grenade_index: int = 0
var _door_markers: Array[Dictionary] = []  # { path_ratio, anchor, door_node }
var _door_index: int = 0
var _is_waiting_for_door: bool = false  # ドアキック完了を待っている状態
var _is_waiting_for_closed_door: bool = false  # 閉じたドアが開くのを待っている状態
var _waiting_door: Node3D = null  # 待機中のドアノード
var _wait_markers: Array[Dictionary] = []  # { path_ratio, anchor, wait_duration }
var _wait_index: int = 0
var _is_waiting_for_wait: bool = false  # Wait待機中状態
var _wait_timer: float = 0.0  # 現在の待機経過時間
var _current_wait_duration: float = 0.0  # 現在の待機時間目標
var _forced_look_direction: Vector3 = Vector3.ZERO
var _last_move_direction: Vector3 = Vector3.ZERO
var _combat_awareness: Node = null  # CombatAwarenessComponent
var _active_target_point: Vector3 = Vector3.ZERO  # ターゲットポイントモード用

## スタック検出用
var _last_position: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0

## 衝突回避状態
var _is_avoiding_collision: bool = false  ## 衝突回避中フラグ（待機状態）
var _is_sidestepping: bool = false  ## 側方回避中フラグ
var _sidestep_direction: Vector3 = Vector3.ZERO  ## 側方回避の方向
var _sidestep_timer: float = 0.0  ## 側方回避の経過時間
var _avoidance_blocker: Node = null  ## 回避対象の相手キャラクター
var _avoidance_timer: float = 0.0  ## 回避継続時間
var _movement_priority: int = 0  ## 移動優先度（低いほど高優先）
var _collision_check_timer: float = 0.0  ## 衝突検出タイマー

## 側方回避設定
const SIDESTEP_DURATION: float = 0.5  ## 側方回避の継続時間
const SIDESTEP_DISTANCE: float = 0.8  ## 側方回避の距離
const HEAD_ON_THRESHOLD: float = -0.3  ## Head-on判定の閾値（相手の移動方向とのdot）

## パス長キャッシュ（毎フレーム再計算を回避）
var _cached_total_length: float = 0.0
var _cached_segment_lengths: Array[float] = []  # 各セグメントの累積距離

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
## @param clear_points: Clearポイント配列（path_ratioを含むDictionary）
## @param grenade_markers: グレネードマーカー配列（path_ratio, target_pos等を含むDictionary）
## @param door_markers: ドアマーカー配列（path_ratio, door_nodeを含むDictionary）
## @param wait_markers: Waitマーカー配列（path_ratio, wait_durationを含むDictionary）
## @param smoke_grenade_markers: スモークグレネードマーカー配列（path_ratio, target_pos等を含むDictionary）
## @return: 開始成功したらtrue
func start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [],
		run_segments: Array[Dictionary] = [], run: bool = false,
		clear_points: Array[Dictionary] = [], grenade_markers: Array[Dictionary] = [],
		door_markers: Array[Dictionary] = [], wait_markers: Array[Dictionary] = [],
		smoke_grenade_markers: Array[Dictionary] = []) -> bool:
	if not _character:
		push_warning("[PathFollowingController] No character set")
		return false

	if path.size() < 2:
		push_warning("[PathFollowingController] Path too short (size=%d)" % path.size())
		return false

	_current_path = path.duplicate()
	_vision_points = vision_points.duplicate()
	_run_segments = run_segments.duplicate()
	_clear_points = clear_points.duplicate()
	_grenade_markers = grenade_markers.duplicate()
	_smoke_grenade_markers = smoke_grenade_markers.duplicate()
	_door_markers = door_markers.duplicate()
	_wait_markers = wait_markers.duplicate()
	_vision_index = 0
	_clear_index = 0
	_grenade_index = 0
	_smoke_grenade_index = 0
	_door_index = 0
	_wait_index = 0
	_is_running = run
	_is_following = true
	_is_waiting_for_door = false
	_is_waiting_for_closed_door = false
	_is_waiting_for_wait = false
	_wait_timer = 0.0
	_current_wait_duration = 0.0
	_waiting_door = null
	_forced_look_direction = Vector3.ZERO
	_active_target_point = Vector3.ZERO  # ターゲットポイントをリセット
	_last_move_direction = Vector3.ZERO
	_last_position = _character.global_position
	_stuck_time = 0.0

	# パス長キャッシュを構築
	_build_path_length_cache()

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

	path_started.emit()
	return true


## パス追従をキャンセル
func cancel() -> void:
	if not _is_following:
		return

	_is_following = false
	_is_waiting_for_door = false
	_is_waiting_for_closed_door = false
	_is_waiting_for_wait = false
	_is_avoiding_collision = false
	_is_sidestepping = false
	_wait_timer = 0.0
	_current_wait_duration = 0.0
	_waiting_door = null
	_avoidance_blocker = null
	_avoidance_timer = 0.0
	_sidestep_direction = Vector3.ZERO
	_sidestep_timer = 0.0
	_current_path.clear()
	_vision_points.clear()
	_run_segments.clear()
	_clear_points.clear()
	_grenade_markers.clear()
	_door_markers.clear()
	_wait_markers.clear()
	_forced_look_direction = Vector3.ZERO
	_active_target_point = Vector3.ZERO
	_last_move_direction = Vector3.ZERO

	path_cancelled.emit()


## パス追従中か確認
func is_following_path() -> bool:
	return _is_following


## 移動優先度を設定（PathExecutionManagerから呼ばれる）
func set_movement_priority(priority: int) -> void:
	_movement_priority = priority


## 移動優先度を取得
func get_movement_priority() -> int:
	return _movement_priority


## 毎フレームの処理（_physics_processから呼び出す）
func process(delta: float) -> void:
	if not _is_following:
		return

	# ドアキック完了待ち状態の場合は処理しない
	if _is_waiting_for_door:
		return

	# Wait待機中の場合
	if _is_waiting_for_wait:
		_wait_timer += delta
		if _wait_timer >= _current_wait_duration:
			# 待機完了、移動再開
			_is_waiting_for_wait = false
			_wait_timer = 0.0
			_current_wait_duration = 0.0
		else:
			# アイドルアニメーションを維持
			_update_idle_animation_while_waiting()
			return

	# 閉じたドアが開くのを待っている場合
	if _is_waiting_for_closed_door:
		if _check_waiting_door_opened():
			# ドアが開いたので移動再開
			_is_waiting_for_closed_door = false
			_waiting_door = null
		else:
			# アイドルアニメーションを維持
			_update_idle_animation_while_waiting()
			return  # まだ閉じているので待機継続

	# 側方回避中の場合
	if _is_sidestepping:
		_sidestep_timer += delta
		if _sidestep_timer >= SIDESTEP_DURATION or _check_avoidance_resolved():
			_end_sidestep()
		else:
			# 側方移動を実行
			_execute_sidestep(delta)
			return  # 側方回避継続

	# 衝突回避待機中の場合
	if _is_avoiding_collision:
		_avoidance_timer += delta
		# タイムアウトまたは衝突解消で待機終了
		if _avoidance_timer >= avoidance_timeout or _check_avoidance_resolved():
			_end_collision_halt()
		else:
			# 相手が非常に近い場合は即座に側方回避
			if _avoidance_blocker and is_instance_valid(_avoidance_blocker):
				var dist: float = _get_distance_to_ally(_avoidance_blocker)
				if dist < collision_check_radius * 1.2:
					_start_sidestep()
					return

			# Head-on検出時は側方回避に切り替え（0.15秒後）
			if _avoidance_timer > 0.15 and _is_head_on_collision():
				_start_sidestep()
				return
			# アイドルアニメーションを維持
			_update_idle_animation_while_waiting()
			return  # 待機継続

	# キャラクターキャッシュ更新（150ms間隔）
	_characters_cache_timer += delta
	if _characters_cache_timer >= CHARACTERS_CACHE_INTERVAL:
		_characters_cache_timer = 0.0
		_characters_cache = get_tree().get_nodes_in_group("characters")

	# 衝突検出タイマー更新（100ms間隔）
	_collision_check_timer += delta

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

	# ドアマーカーのチェック（最終目的地到達前に優先チェック）
	# ドアマーカーがある場合、パス完了より先に停止してドアキックを実行
	var early_progress = _calculate_path_progress()
	if _check_door_markers(early_progress):
		return  # ドアマーカーに到達、処理を中断

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

	# Clearポイントのチェック（視線・Runをリセット）
	_check_clear_points(progress)

	# グレネードマーカーのチェック（投擲実行、移動は継続）
	_check_grenade_markers(progress)

	# スモークグレネードマーカーのチェック（投擲実行、移動は継続）
	_check_smoke_grenade_markers(progress)

	# Waitマーカーのチェック（待機開始）
	if _check_wait_markers(progress):
		return  # Waitマーカーに到達、処理を中断

	# ドアマーカーは早期チェック済み（最終目的地到達前に処理）

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

		# VisionComponent用にGameCharacterの向きを同期
		if look_dir.length_squared() > 0.001:
			_character._facing_direction = look_dir.normalized()

	# 閉じたドアチェック（移動方向に閉じたドアがあれば停止）
	# ただし、Doorマーカーが設定されているドアは除外（Doorマーカーで処理される）
	var closed_door = _check_closed_door_ahead(move_dir)
	if closed_door and not _is_door_in_markers(closed_door):
		_is_waiting_for_closed_door = true
		_waiting_door = closed_door
		_character.velocity = Vector3.ZERO
		# アイドルアニメーションに切り替え
		_update_idle_animation_while_waiting()
		return

	# 衝突回避チェック（100ms間隔）
	if _collision_check_timer >= COLLISION_CHECK_INTERVAL:
		_collision_check_timer = 0.0
		var ally_ahead: Node = _detect_ally_ahead(move_dir)
		if ally_ahead:
			_avoidance_blocker = ally_ahead

			# 相手との距離が非常に近い場合は即座に側方回避（物理的にブロックされている）
			var distance_to_ally: float = _get_distance_to_ally(ally_ahead)
			if distance_to_ally < collision_check_radius * 1.2:
				# 近距離では優先度に関係なく両者が側方回避
				_start_sidestep()
				return

			# Head-on（対面移動）かどうかをチェック
			var is_head_on: bool = _is_head_on_collision()
			if is_head_on:
				# Head-onの場合は即座に側方回避
				_start_sidestep()
				return
			elif _should_yield_to(ally_ahead):
				# Head-onでなく、自分が低優先度なら待機
				_start_collision_halt(ally_ahead)
				_update_idle_animation_while_waiting()
				return
			else:
				_avoidance_blocker = null  # 高優先度なので進む

	# 物理移動
	_character.velocity.x = move_dir.x * speed
	_character.velocity.z = move_dir.z * speed

	if not _character.is_on_floor():
		_character.velocity.y -= 9.8 * delta

	_character.move_and_slide()


## 視線方向を更新（ターゲットポイントモード対応）
func _update_vision_direction() -> void:
	if _vision_points.size() == 0:
		# ターゲットポイントが設定されている場合、動的に方向を計算
		if _active_target_point.length_squared() > 0.001:
			_calculate_direction_to_target()
		else:
			_forced_look_direction = Vector3.ZERO
		return

	var progress = _calculate_path_progress()

	while _vision_index < _vision_points.size():
		var vp = _vision_points[_vision_index]
		if progress >= vp.path_ratio:
			# ターゲットポイントモードかどうかをチェック
			if vp.has("target_point"):
				# ターゲットポイントを保存（毎フレーム方向を再計算）
				_active_target_point = vp.target_point
				_calculate_direction_to_target()
				vision_point_reached.emit(_vision_index, _forced_look_direction)
			elif vp.has("direction"):
				# 後方互換: 固定方向モード
				_forced_look_direction = vp.direction
				_active_target_point = Vector3.ZERO
				vision_point_reached.emit(_vision_index, vp.direction)
			_vision_index += 1
		else:
			break

	# ターゲットポイントが設定されている場合、毎フレーム方向を再計算
	if _active_target_point.length_squared() > 0.001:
		_calculate_direction_to_target()


## キャラクター位置からターゲット地点への方向を計算
func _calculate_direction_to_target() -> void:
	if not _character:
		return
	var char_pos = _character.global_position
	char_pos.y = 0
	var target = _active_target_point
	target.y = 0

	var direction = (target - char_pos)
	if direction.length_squared() > 0.001:
		_forced_look_direction = direction.normalized()
	# ターゲットに非常に近い場合は現在の方向を維持


## パス完了時に残りの視線ポイントを全て処理
## 終点付近の視線ポイントを適用するため
func _process_remaining_vision_points() -> void:
	while _vision_index < _vision_points.size():
		var vp = _vision_points[_vision_index]
		if vp.has("target_point"):
			_active_target_point = vp.target_point
			_calculate_direction_to_target()
		elif vp.has("direction"):
			_forced_look_direction = vp.direction
			_active_target_point = Vector3.ZERO
		_vision_index += 1


## パス長キャッシュを構築
func _build_path_length_cache() -> void:
	_cached_segment_lengths.clear()
	_cached_total_length = 0.0

	if _current_path.size() < 2:
		return

	_cached_segment_lengths.append(0.0)  # 最初のポイントは累積距離0
	for i in range(1, _current_path.size()):
		_cached_total_length += _current_path[i - 1].distance_to(_current_path[i])
		_cached_segment_lengths.append(_cached_total_length)


## パスの進行率を計算
## キャラクターの実際の位置に基づいて、パス上の最も近い点を見つけて進行率を計算
func _calculate_path_progress() -> float:
	if _current_path.size() < 2 or not _character:
		return 0.0

	if _cached_total_length < 0.001:
		return 0.0

	var char_pos = _character.global_position
	char_pos.y = 0

	# 各セグメントを調べて、キャラクターに最も近い点を見つける
	var best_distance = INF
	var best_accumulated_length = 0.0

	for i in range(1, _current_path.size()):
		var p1 = _current_path[i - 1]
		var p2 = _current_path[i]
		p1.y = 0
		p2.y = 0

		var segment = p2 - p1
		var segment_length_sq = segment.length_squared()
		if segment_length_sq < 0.000001:
			continue

		# セグメント上の最近点を計算
		var t = clampf((char_pos - p1).dot(segment) / segment_length_sq, 0.0, 1.0)
		var point_on_segment = p1 + segment * t
		var distance = char_pos.distance_to(point_on_segment)

		# 現在のセグメント以降のみ考慮（戻らない）
		if i >= _path_index:
			if distance < best_distance:
				best_distance = distance
				var segment_length = sqrt(segment_length_sq)
				best_accumulated_length = _cached_segment_lengths[i - 1] + segment_length * t

	return best_accumulated_length / _cached_total_length


## Run区間内かどうかを判定
func _is_in_run_segment(progress: float) -> bool:
	for seg in _run_segments:
		if progress >= seg.start_ratio and progress < seg.end_ratio:
			return true
	return false


## Clearポイントのチェックと処理
## Clearポイント到達時に視線・Runをリセットして進行方向を向く
func _check_clear_points(progress: float) -> void:
	while _clear_index < _clear_points.size():
		var cp = _clear_points[_clear_index]
		if progress >= cp.path_ratio:
			# Clearポイントに到達: 視線とRun状態をリセット
			_forced_look_direction = Vector3.ZERO
			_active_target_point = Vector3.ZERO
			_clear_index += 1
		else:
			break


## グレネードマーカーのチェックと処理
## マーカー到達時に即座に投擲シグナルを発火（移動は継続）
func _check_grenade_markers(progress: float) -> void:
	while _grenade_index < _grenade_markers.size():
		var gm = _grenade_markers[_grenade_index]
		if progress >= gm.path_ratio:
			# グレネードマーカーに到達: 投擲シグナルを発火
			grenade_marker_reached.emit(_grenade_index, gm)
			_grenade_index += 1
		else:
			break


## スモークグレネードマーカーのチェックと処理
## マーカー到達時に即座に投擲シグナルを発火（移動は継続）
func _check_smoke_grenade_markers(progress: float) -> void:
	while _smoke_grenade_index < _smoke_grenade_markers.size():
		var sgm = _smoke_grenade_markers[_smoke_grenade_index]
		if progress >= sgm.path_ratio:
			# スモークグレネードマーカーに到達: 投擲シグナルを発火
			smoke_grenade_marker_reached.emit(_smoke_grenade_index, sgm)
			_smoke_grenade_index += 1
		else:
			break


## ドアマーカーのチェックと処理
## マーカー到達時にパスを一時停止してドアキックシグナルを発火
## @return: ドアマーカーに到達してパスを停止した場合はtrue
func _check_door_markers(progress: float) -> bool:
	# パス終端付近のマーカーに対する許容範囲（進行率が完全に1.0に到達しないため）
	const END_TOLERANCE: float = 0.03
	# マーカー位置への到達判定距離
	const MARKER_REACH_DISTANCE: float = 0.8

	while _door_index < _door_markers.size():
		var dm = _door_markers[_door_index]
		var target_ratio = dm.path_ratio

		# 終端付近（ratio > 0.97）のマーカーは許容範囲を持たせる
		var ratio_reached = false
		if target_ratio > 0.97:
			# 終端マーカー: progress が target_ratio - END_TOLERANCE 以上で到達とみなす
			ratio_reached = progress >= (target_ratio - END_TOLERANCE)
		else:
			ratio_reached = progress >= target_ratio

		if ratio_reached:
			# 進行率だけでなく、実際の距離もチェック
			# キャラクターがマーカーのanchor位置に十分近いか確認
			var actually_reached = true
			if dm.has("anchor") and _character:
				var char_pos = _character.global_position
				char_pos.y = 0
				var anchor = dm.anchor
				anchor.y = 0
				var distance = char_pos.distance_to(anchor)
				actually_reached = distance < MARKER_REACH_DISTANCE

			if actually_reached:
				# ドアマーカーに到達: パスを一時停止
				_is_waiting_for_door = true
				_door_index += 1

				# ドアノードを取得してシグナル発火
				var door = dm.door_node if dm.has("door_node") else null
				door_marker_reached.emit(_door_index - 1, door)
				return true
			else:
				# 進行率は超えているが、実際の位置はまだ遠い
				# 次のフレームで再チェックするために break しない
				break
		else:
			break
	return false


## ドアキック完了後にパス追従を再開
func resume_after_door() -> void:
	_is_waiting_for_door = false


## Waitマーカーのチェックと処理
## マーカー到達時にパスを一時停止して待機開始
## @return: Waitマーカーに到達してパスを停止した場合はtrue
func _check_wait_markers(progress: float) -> bool:
	while _wait_index < _wait_markers.size():
		var wm = _wait_markers[_wait_index]
		if progress >= wm.path_ratio:
			# Waitマーカーに到達: 待機開始
			_is_waiting_for_wait = true
			_wait_timer = 0.0
			_current_wait_duration = wm.wait_duration if wm.has("wait_duration") else 1.0
			_wait_index += 1

			# キャラクターを停止
			if _character:
				_character.velocity = Vector3.ZERO

			# アイドルアニメーションに切り替え
			_update_idle_animation_while_waiting()
			return true
		else:
			break
	return false


## 移動方向に閉じたドアがあるかチェック
## @return: 閉じたドアがあればそのノード、なければnull
func _check_closed_door_ahead(move_dir: Vector3) -> Node3D:
	if not _character:
		return null

	# レイキャストで前方の閉じたドアを検出
	var space_state = _character.get_world_3d().direct_space_state
	if not space_state:
		return null

	var from = _character.global_position + Vector3(0, 0.5, 0)
	var to = from + move_dir.normalized() * 0.8  # 0.8m先をチェック

	# 壁レイヤー（2）をチェック
	var query = PhysicsRayQueryParameters3D.create(from, to, 2)
	query.exclude = [_character.get_rid()]
	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return null

	var collider = result.collider
	if not collider:
		return null

	# doorsグループに属していて、open_doorsグループに属していないドアを検出
	var door = _find_closed_door_in_hierarchy(collider)
	return door


## ノード階層を遡って閉じたドアを探す
func _find_closed_door_in_hierarchy(node: Node) -> Node3D:
	while node:
		if node.is_in_group("doors"):
			# open_doorsグループに属していなければ閉じている
			if not node.is_in_group("open_doors"):
				return node as Node3D
			else:
				return null  # 開いているドア
		node = node.get_parent()
	return null


## 待機中のドアが開いたかチェック
func _check_waiting_door_opened() -> bool:
	if not is_instance_valid(_waiting_door):
		return true  # ドアが無効になった場合は通過可能

	# open_doorsグループに属していれば開いている
	return _waiting_door.is_in_group("open_doors")


## 指定されたドアがDoorマーカーに設定されているかチェック
func _is_door_in_markers(door: Node3D) -> bool:
	if not door:
		return false

	for dm in _door_markers:
		if dm.has("door_node") and dm.door_node == door:
			return true
	return false


## 閉じたドア待機中のアイドルアニメーション更新
func _update_idle_animation_while_waiting() -> void:
	if not _character:
		return

	var anim_ctrl = _character.get_anim_controller()
	if not anim_ctrl:
		return

	# 現在の視線方向または最後の移動方向を維持
	var look_dir = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else _last_move_direction
	if look_dir.length_squared() < 0.1:
		look_dir = Vector3.FORWARD

	# アイドル状態（移動方向ゼロ）でアニメーション更新
	anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, 0.016)


## パス追従完了
func _finish() -> void:
	# キャラクターの速度を停止
	if _character:
		_character.velocity = Vector3.ZERO

	# 残りの視線ポイントを全て処理（終点付近の視線ポイントを適用するため）
	_process_remaining_vision_points()

	# 完了時に最後の向きを維持してアイドル状態に
	# 優先順位: 敵視認 > 視線ポイント > 移動方向
	if _character:
		var anim_ctrl = _character.get_anim_controller()
		if anim_ctrl:
			var final_dir: Vector3 = Vector3.ZERO

			# 1. 敵を追跡中なら敵方向を維持（最優先）
			if _combat_awareness and _combat_awareness.has_method("is_tracking_enemy"):
				if _combat_awareness.is_tracking_enemy():
					final_dir = _combat_awareness.get_override_look_direction()

			# 2. 視線ポイント or 3. 最後の移動方向
			if final_dir.length_squared() < 0.1:
				final_dir = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else _last_move_direction

			if final_dir.length_squared() < 0.1:
				final_dir = Vector3.FORWARD
			# アイドル状態に遷移（移動方向をゼロに）
			anim_ctrl.update_animation(Vector3.ZERO, final_dir, false, 0.016)

	_is_following = false
	_is_waiting_for_door = false
	_is_waiting_for_closed_door = false
	_is_waiting_for_wait = false
	_is_avoiding_collision = false
	_is_sidestepping = false
	_wait_timer = 0.0
	_current_wait_duration = 0.0
	_waiting_door = null
	_avoidance_blocker = null
	_avoidance_timer = 0.0
	_sidestep_direction = Vector3.ZERO
	_sidestep_timer = 0.0
	_current_path.clear()
	_vision_points.clear()
	_run_segments.clear()
	_clear_points.clear()
	_grenade_markers.clear()
	_door_markers.clear()
	_wait_markers.clear()
	_forced_look_direction = Vector3.ZERO
	_active_target_point = Vector3.ZERO
	_last_move_direction = Vector3.ZERO

	path_completed.emit()


## ========================================
## 衝突回避ロジック（Door Kickers 2スタイル）
## ========================================

## 味方との距離を取得
func _get_distance_to_ally(ally: Node) -> float:
	if not _character or not ally:
		return INF
	var char_pos: Vector3 = _character.global_position
	char_pos.y = 0
	var ally_pos: Vector3 = ally.global_position
	ally_pos.y = 0
	return char_pos.distance_to(ally_pos)


## 前方の味方キャラクターを検出
## @param move_dir: 移動方向
## @return: 前方に味方がいればそのNode、いなければnull
func _detect_ally_ahead(move_dir: Vector3) -> Node:
	if not _character or move_dir.length_squared() < 0.001:
		return null

	var char_pos: Vector3 = _character.global_position
	char_pos.y = 0

	# キャッシュを使用して味方をチェック
	for other in _characters_cache:
		if other == _character:
			continue
		if not is_instance_valid(other):
			continue
		if "is_alive" in other and not other.is_alive:
			continue
		if not _is_ally(other):
			continue

		var other_pos: Vector3 = other.global_position
		other_pos.y = 0

		# 距離チェック
		var distance: float = char_pos.distance_to(other_pos)
		if distance > collision_check_distance:
			continue

		# 方向チェック（前方にいるか）
		var to_other: Vector3 = (other_pos - char_pos).normalized()
		var dot: float = move_dir.normalized().dot(to_other)
		if dot < 0.5:  # 前方60度以外は無視
			continue

		# 横方向の距離チェック（パス上の衝突判定）
		var perpendicular: Vector3 = to_other - move_dir.normalized() * dot
		if perpendicular.length() > collision_check_radius:
			continue

		return other

	return null


## 相手に道を譲るべきかを判定
## @param other: 比較対象のキャラクター
## @return: 自分が待機すべきならtrue
func _should_yield_to(other: Node) -> bool:
	if not other:
		return false

	# 相手のPathFollowingControllerを取得
	var other_controller: Node = null
	var other_id: int = other.get_instance_id()

	# PathExecutionManagerからコントローラーを探す
	var path_exec_manager = get_node_or_null("/root/GameScreen/PathExecutionManager")
	if not path_exec_manager:
		# fallback: 親ノードから探す
		for sibling in get_parent().get_children():
			if sibling.name.begins_with("PathFollowingController_") and sibling != self:
				if sibling.name.ends_with(str(other_id)):
					other_controller = sibling
					break
	else:
		if path_exec_manager.has_method("_get_or_create_path_controller"):
			# 直接アクセスできないので、_path_controllersを参照
			if "_path_controllers" in path_exec_manager:
				var controllers: Dictionary = path_exec_manager._path_controllers
				if controllers.has(other_id):
					other_controller = controllers[other_id]

	if not other_controller:
		# 相手がパス追従中でなければ、こちらが進む
		return false

	if not other_controller.is_following_path():
		# 相手がパス追従中でなければ、こちらが進む
		return false

	var other_priority: int = other_controller.get_movement_priority()
	var my_priority: int = _movement_priority

	# 優先度ルール:
	# 1. 優先度が低い数値 = 先に実行開始 = 高優先
	# 2. 優先度が同じ場合はパス進行率で比較
	# 3. それでも同じならキャラクターIDで決定
	if my_priority != other_priority:
		return my_priority > other_priority  # 自分の数値が大きい = 後から開始 = 譲る

	# パス進行率で比較（進んでいる方が優先）
	var my_progress: float = _calculate_path_progress()
	var other_progress: float = 0.0
	if other_controller.has_method("get_current_progress"):
		other_progress = other_controller.get_current_progress()

	if absf(my_progress - other_progress) > 0.05:
		return my_progress < other_progress  # 相手の方が進んでいれば譲る

	# 最終手段: キャラクターIDで決定（小さい方が優先）
	return _character.get_instance_id() > other.get_instance_id()


## 衝突回避の待機を開始
func _start_collision_halt(blocker: Node) -> void:
	_is_avoiding_collision = true
	_avoidance_blocker = blocker
	_avoidance_timer = 0.0

	# キャラクターを停止
	if _character:
		_character.velocity = Vector3.ZERO


## 衝突回避の待機を終了
func _end_collision_halt() -> void:
	_is_avoiding_collision = false
	_avoidance_blocker = null
	_avoidance_timer = 0.0


## 衝突が解消されたかチェック
## @return: 解消されていればtrue
func _check_avoidance_resolved() -> bool:
	if not _avoidance_blocker:
		return true

	if not is_instance_valid(_avoidance_blocker):
		return true

	# 相手が死亡した場合
	if "is_alive" in _avoidance_blocker and not _avoidance_blocker.is_alive:
		return true

	# 相手がパス追従を完了した場合
	var other_id: int = _avoidance_blocker.get_instance_id()
	var path_exec_manager = get_node_or_null("/root/GameScreen/PathExecutionManager")
	if path_exec_manager and "_path_controllers" in path_exec_manager:
		var controllers: Dictionary = path_exec_manager._path_controllers
		if controllers.has(other_id):
			var other_controller = controllers[other_id]
			if not other_controller.is_following_path():
				return true

	# 相手との距離が離れた場合
	if _character:
		var char_pos: Vector3 = _character.global_position
		char_pos.y = 0
		var blocker_pos: Vector3 = _avoidance_blocker.global_position
		blocker_pos.y = 0
		if char_pos.distance_to(blocker_pos) > collision_check_distance * 1.5:
			return true

	return false


## Head-on（対面）衝突かどうかを判定
## 両者が互いに向かって移動している場合にtrue
func _is_head_on_collision() -> bool:
	if not _avoidance_blocker or not _character:
		return false

	if not is_instance_valid(_avoidance_blocker):
		return false

	# 相手のコントローラーを取得
	var other_id: int = _avoidance_blocker.get_instance_id()
	var path_exec_manager = get_node_or_null("/root/GameScreen/PathExecutionManager")
	if not path_exec_manager or not "_path_controllers" in path_exec_manager:
		return false

	var controllers: Dictionary = path_exec_manager._path_controllers
	if not controllers.has(other_id):
		return false

	var other_controller = controllers[other_id]
	if not other_controller.is_following_path():
		return false

	# 相手も衝突回避中（待機中）ならhead-on
	if other_controller._is_avoiding_collision:
		return true

	# 相手が自分に向かって移動しているかチェック
	if _check_moving_toward_each_other(other_controller):
		return true

	return false


## 相手が自分に向かって移動しているかチェック
func _check_moving_toward_each_other(other_controller: Node) -> bool:
	if not _character or not _avoidance_blocker:
		return false

	var my_pos: Vector3 = _character.global_position
	my_pos.y = 0
	var other_pos: Vector3 = _avoidance_blocker.global_position
	other_pos.y = 0

	# 自分から相手への方向
	var to_other: Vector3 = (other_pos - my_pos).normalized()

	# 相手のパス上の次の目標点を取得
	if other_controller._current_path.size() == 0:
		return false

	var other_path_index: int = other_controller._path_index
	if other_path_index >= other_controller._current_path.size():
		return false

	var other_target: Vector3 = other_controller._current_path[other_path_index]
	other_target.y = 0

	# 相手の移動方向
	var other_move_dir: Vector3 = (other_target - other_pos).normalized()

	# 相手が自分の方に向かっているか（移動方向が自分への方向と逆）
	var dot: float = other_move_dir.dot(to_other)
	return dot < HEAD_ON_THRESHOLD  # -0.3以下なら対面移動


## 側方回避を開始
func _start_sidestep() -> void:
	if not _character or not _avoidance_blocker:
		return

	# 側方回避方向を計算
	_sidestep_direction = _calculate_sidestep_direction()
	if _sidestep_direction.length_squared() < 0.001:
		return  # 有効な回避方向がない

	_is_sidestepping = true
	_is_avoiding_collision = false  # 待機状態を解除
	_sidestep_timer = 0.0


## 側方回避方向を計算
## 壁を避けて安全な方向を選択
## キャラクターIDに基づいて一貫した方向を決定（両者が反対方向に避ける）
func _calculate_sidestep_direction() -> Vector3:
	if not _character or not _avoidance_blocker:
		return Vector3.ZERO

	var char_pos: Vector3 = _character.global_position
	char_pos.y = 0
	var blocker_pos: Vector3 = _avoidance_blocker.global_position
	blocker_pos.y = 0

	# 両者を結ぶ線に垂直な方向（グローバル座標系で一貫）
	var between: Vector3 = (blocker_pos - char_pos).normalized()
	var perpendicular: Vector3 = Vector3(between.z, 0, -between.x)

	# キャラクターIDで方向を決定（小さいIDが+perpendicular、大きいIDが-perpendicular）
	# これにより両者が必ず反対方向に移動する
	var my_id: int = _character.get_instance_id()
	var other_id: int = _avoidance_blocker.get_instance_id()

	var primary: Vector3
	var secondary: Vector3
	if my_id < other_id:
		primary = perpendicular
		secondary = -perpendicular
	else:
		primary = -perpendicular
		secondary = perpendicular

	# 壁チェック
	if _is_direction_clear(primary):
		return primary
	elif _is_direction_clear(secondary):
		return secondary

	return Vector3.ZERO  # どちらも壁がある場合


## 指定方向が壁に遮られていないかチェック
func _is_direction_clear(direction: Vector3) -> bool:
	if not _character:
		return false

	var space_state = _character.get_world_3d().direct_space_state
	if not space_state:
		return true  # チェックできない場合は通過可能と仮定

	var from: Vector3 = _character.global_position + Vector3(0, 0.5, 0)
	var to: Vector3 = from + direction.normalized() * SIDESTEP_DISTANCE

	# 壁レイヤー（2）をチェック
	var query = PhysicsRayQueryParameters3D.create(from, to, 2)
	query.exclude = [_character.get_rid()]
	var result = space_state.intersect_ray(query)

	return result.is_empty()


## 側方回避を実行（毎フレーム呼ばれる）
func _execute_sidestep(delta: float) -> void:
	if not _character:
		return

	var anim_ctrl = _character.get_anim_controller()
	if not anim_ctrl:
		return

	var speed: float = anim_ctrl.get_current_speed() * 0.7  # 通常速度の70%

	# 側方移動
	_character.velocity.x = _sidestep_direction.x * speed
	_character.velocity.z = _sidestep_direction.z * speed

	if not _character.is_on_floor():
		_character.velocity.y -= 9.8 * delta

	_character.move_and_slide()

	# 視線は相手またはパス方向を維持
	var look_dir: Vector3 = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else _sidestep_direction
	anim_ctrl.update_animation(_sidestep_direction, look_dir, false, delta)


## 側方回避を終了
func _end_sidestep() -> void:
	_is_sidestepping = false
	_sidestep_direction = Vector3.ZERO
	_sidestep_timer = 0.0
	_avoidance_blocker = null
	_avoidance_timer = 0.0


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


## ========================================
## 進行状況取得API（タイムライン用）
## ========================================

## 現在の進行率を取得 (0.0 ~ 1.0)
func get_current_progress() -> float:
	if not _is_following:
		return 0.0
	return _calculate_path_progress()


## 待機状態を取得
## @return: { is_waiting: bool, type: String, remaining: float }
func get_waiting_state() -> Dictionary:
	if _is_waiting_for_wait:
		return {
			"is_waiting": true,
			"type": "wait",
			"remaining": maxf(0.0, _current_wait_duration - _wait_timer)
		}
	elif _is_waiting_for_door:
		return {
			"is_waiting": true,
			"type": "door",
			"remaining": 0.0  # ドアキック時間は外部で管理
		}
	elif _is_waiting_for_closed_door:
		return {
			"is_waiting": true,
			"type": "closed_door",
			"remaining": 0.0  # 不定
		}
	else:
		return {
			"is_waiting": false,
			"type": "",
			"remaining": 0.0
		}


## パス追従中かどうか（_is_followingの公開版）
func is_active() -> bool:
	return _is_following


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
