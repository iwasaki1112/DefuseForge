extends Node
## PathFollowingController
## パス追従を管理するコントローラークラス
## キャラクターが描画されたパスに沿って移動し、視線ポイントで向きを変える
## 注意: CharacterAnimationControllerが必須

## シグナル
signal path_started()
signal path_completed()
signal path_cancelled()
signal vision_point_reached(index: int, point_data: Dictionary)
@warning_ignore("unused_signal")
signal grenade_point_reached(index: int, point_data: Dictionary)
@warning_ignore("unused_signal")
signal smoke_grenade_point_reached(index: int, point_data: Dictionary)
@warning_ignore("unused_signal")
signal door_point_reached(index: int, door: Node3D)
@warning_ignore("unused_signal")
signal wait_point_reached(index: int, point_data: Dictionary)
@warning_ignore("unused_signal")
signal extension_path_activated()  ## 延長パスに切り替わった時
signal path_progress_updated(path_index: int)  ## パスの進行状況が更新された時
@warning_ignore("unused_signal")
signal extension_points_scaled(scale: float)  ## 延長ポイントの比率がスケールされた時
@warning_ignore("unused_signal")
signal sync_wait_started()  ## 同期待機開始時
@warning_ignore("unused_signal")
signal sync_wait_released()  ## 同期待機解放時

## スタック検出設定
@export var stuck_threshold: float = 0.01  ## この距離以下の移動をスタックとみなす
@export var stuck_timeout: float = 0.5  ## この時間スタックしたら次のポイントへスキップ
@export var final_destination_radius: float = 0.1  ## 最終目的地への到達判定半径
@export var ally_collision_radius: float = 1.0  ## 味方との衝突検出半径

## 移動スムージング設定
@export var direction_smoothing: float = 8.0  ## 移動方向のスムージング係数（大きいほど追従が速い）

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
var _run_segments: Array[Dictionary] = []  # { start_ratio, end_ratio }
var _clear_points: Array[Dictionary] = []  # { path_ratio }
var _grenade_points: Array[Dictionary] = []  # { path_ratio, anchor, target_pos, bounce_point? }
var _smoke_grenade_points: Array[Dictionary] = []  # { path_ratio, anchor, target_pos, bounce_point? }
var _door_points: Array[Dictionary] = []  # { path_ratio, anchor, door_node }
var _door_index: int = 0
var _forced_look_direction: Vector3 = Vector3.ZERO
var _last_move_direction: Vector3 = Vector3.ZERO
var _smoothed_move_direction: Vector3 = Vector3.ZERO  ## スムージングされた移動方向
var _combat_awareness: Node = null  # CombatAwarenessComponent
var _active_target_point: Vector3 = Vector3.ZERO  # ターゲットポイントモード用

## ポイントチェッカー（PathPointCheckerを使用）
var _vision_checker: PathPointChecker = null
var _wait_checker: PathPointChecker = null
var _extension_vision_checker: PathPointChecker = null
var _extension_wait_checker: PathPointChecker = null

## スタック検出用
var _last_position: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0

## 距離計算の単調増加保証用（自己交差パス対策）
var _last_distance_traveled: float = 0.0

## パス長キャッシュ（毎フレーム再計算を回避）
var _cached_total_length: float = 0.0
var _cached_segment_lengths: Array[float] = []  # 各セグメントの累積距離

## 距離ベースのポイント検出用（_calculate_distance_traveled()で動的に計算）

## 衝突検出・キャラクターキャッシュ（process内で使用）
var _movement_priority: int = 0  ## 移動優先度（低いほど高優先）
var _collision_check_timer: float = 0.0  ## 衝突検出タイマー

## キャラクターキャッシュ（GC負荷削減）
var _characters_cache: Array = []
var _characters_cache_timer: float = CHARACTERS_CACHE_INTERVAL  # 初回即時更新

## ハンドラーインスタンス
var _collision_avoidance: CollisionAvoidanceController = null
var _door_handler: DoorInteractionHandler = null
var _point_handler: PathPointActionHandler = null
var _extension_handler: ExtensionPathHandler = null


## セットアップ
func setup(character: CharacterBody3D) -> void:
	_character = character
	_init_point_checkers()

	# ハンドラーの初期化
	_collision_avoidance = CollisionAvoidanceController.new()
	_collision_avoidance.setup(self, character)
	_door_handler = DoorInteractionHandler.new()
	_door_handler.setup(self, character)
	_point_handler = PathPointActionHandler.new()
	_point_handler.setup(self, character)
	_extension_handler = ExtensionPathHandler.new()
	_extension_handler.setup(self)


## 対象キャラクターを取得（内部状態を隠蔽するAPI）
func get_character() -> CharacterBody3D:
	return _character


## ポイントチェッカーを初期化
func _init_point_checkers() -> void:
	_vision_checker = PathPointChecker.new()
	_vision_checker.setup(
		PathPointChecker.CheckMode.DISTANCE,
		_calculate_distance_traveled,
		_calculate_anchor_distance
	)

	_wait_checker = PathPointChecker.new()
	_wait_checker.setup(
		PathPointChecker.CheckMode.DISTANCE,
		_calculate_distance_traveled,
		_calculate_anchor_distance
	)

	_extension_vision_checker = PathPointChecker.new()
	_extension_vision_checker.setup(
		PathPointChecker.CheckMode.DISTANCE,
		Callable(),  # 延長パス用は後で設定
		Callable()
	)

	_extension_wait_checker = PathPointChecker.new()
	_extension_wait_checker.setup(
		PathPointChecker.CheckMode.DISTANCE,
		Callable(),
		Callable()
	)


## Set combat awareness component for automatic enemy aiming
func set_combat_awareness(component: Node) -> void:
	_combat_awareness = component


## パス追従を開始
## @param path: 追従するパス（Vector3の配列）
## @param vision_points: 視線ポイント配列（path_ratio, directionを含むDictionary）
## @param run_segments: Run区間配列（start_ratio, end_ratioを含むDictionary）
## @param run: 走行モードか（全体を走る場合）
## @param clear_points: Clearポイント配列（path_ratioを含むDictionary）
## @param grenade_points: グレネードポイント配列（path_ratio, target_pos等を含むDictionary）
## @param door_points: ドアポイント配列（path_ratio, door_nodeを含むDictionary）
## @param wait_points: Waitポイント配列（path_ratio, wait_durationを含むDictionary）
## @param smoke_grenade_points: スモークグレネードポイント配列（path_ratio, target_pos等を含むDictionary）
## @return: 開始成功したらtrue
func start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [],
		run_segments: Array[Dictionary] = [], run: bool = false,
		clear_points: Array[Dictionary] = [], grenade_points: Array[Dictionary] = [],
		door_points: Array[Dictionary] = [], wait_points: Array[Dictionary] = [],
		smoke_grenade_points: Array[Dictionary] = []) -> bool:
	if not _character:
		push_warning("[PathFollowingController] No character set")
		return false

	if path.size() < 2:
		push_warning("[PathFollowingController] Path too short (size=%d)" % path.size())
		return false

	_current_path = path.duplicate()
	_run_segments = run_segments.duplicate()
	_clear_points = clear_points.duplicate()
	_grenade_points = grenade_points.duplicate()
	_smoke_grenade_points = smoke_grenade_points.duplicate()
	_door_points = door_points.duplicate()
	_door_index = 0
	_is_running = run
	_is_following = true
	_forced_look_direction = Vector3.ZERO
	_active_target_point = Vector3.ZERO  # ターゲットポイントをリセット
	_last_move_direction = Vector3.ZERO
	_smoothed_move_direction = Vector3.ZERO  # スムージング状態をリセット
	_last_position = _character.global_position
	_stuck_time = 0.0
	_last_distance_traveled = 0.0  # 距離計算をリセット

	# ハンドラーの状態をリセット
	_point_handler.reset()
	_door_handler.reset()
	_collision_avoidance.reset()

	# パス長キャッシュを構築
	_build_path_length_cache()

	# ポイントチェッカーにポイントを設定（自動でpath_distance計算とソート）
	# パス開始時は char_dist=0 なのでインデックス再計算は不要
	_vision_checker.set_points(vision_points, false)
	_wait_checker.set_points(wait_points, false)

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
	_smoothed_move_direction = Vector3.ZERO
	_current_path.clear()
	_vision_checker.clear()
	_run_segments.clear()
	_clear_points.clear()
	_grenade_points.clear()
	_door_points.clear()
	_wait_checker.clear()
	_forced_look_direction = Vector3.ZERO
	_active_target_point = Vector3.ZERO
	_last_move_direction = Vector3.ZERO

	# ハンドラーの状態をリセット
	_point_handler.reset()
	_door_handler.reset()
	_collision_avoidance.reset()

	path_cancelled.emit()


## パス追従中か確認
func is_following_path() -> bool:
	return _is_following


## 現在のパスを取得
func get_current_path() -> Array[Vector3]:
	return _current_path


## 現在のパスインデックスを取得
func get_current_path_index() -> int:
	return _path_index


## 現在のビジョンポイント配列を取得
func get_vision_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in _vision_checker.get_all_points():
		result.append(p)
	return result


## 移動優先度を設定（PathExecutionManagerから呼ばれる）
func set_movement_priority(priority: int) -> void:
	_movement_priority = priority
	# 優先度に基づいて衝突検出タイミングをずらす
	# 高優先度（小さい数値）は早く検出し、先に行動を開始
	# 低優先度は遅く検出し、相手が既に行動中ならスキップ
	_collision_check_timer = COLLISION_CHECK_INTERVAL - float(priority) * 0.03


## 移動優先度を取得
func get_movement_priority() -> int:
	return _movement_priority


## 毎フレームの処理（_physics_processから呼び出す）
func process(delta: float) -> void:
	if not _is_following:
		return

	# ドアキック完了待ち状態の場合は処理しない
	if _door_handler.is_waiting_for_door:
		return

	# 同期待機中の場合（Wボタンで解放されるまで待機）
	if _point_handler.is_sync_waiting:
		_point_handler._update_idle_animation_while_waiting()
		return

	# Wait待機中の場合（時間ベース）
	if _point_handler.is_waiting_for_wait:
		if _point_handler.process_wait(delta):
			return  # まだ待機中

	# 閉じたドアが開くのを待っている場合
	if _door_handler.is_waiting_for_closed_door:
		if _door_handler.check_waiting_door_opened():
			# ドアが開いたので移動再開
			_door_handler.is_waiting_for_closed_door = false
			_door_handler.waiting_door = null
		else:
			# アイドルアニメーションを維持
			_point_handler._update_idle_animation_while_waiting()
			return  # まだ閉じているので待機継続

	# 側方回避中の場合
	if _collision_avoidance.is_sidestepping:
		_collision_avoidance.sidestep_timer += delta
		# 終了条件: 時間経過、すれ違い完了、または衝突解消
		if _collision_avoidance.sidestep_timer >= CollisionAvoidanceController.SIDESTEP_DURATION or _collision_avoidance.has_passed_blocker() or _collision_avoidance.check_avoidance_resolved():
			_collision_avoidance.end_sidestep()
		else:
			# 側方移動を実行
			_collision_avoidance.execute_sidestep(delta)
			return  # 側方回避継続

	# 衝突回避待機中の場合（低優先度キャラは停止して待つだけ）
	if _collision_avoidance.is_avoiding_collision:
		_collision_avoidance.avoidance_timer += delta
		# タイムアウトまたは衝突解消で待機終了
		if _collision_avoidance.avoidance_timer >= avoidance_timeout or _collision_avoidance.check_avoidance_resolved():
			_collision_avoidance.end_collision_halt()
		else:
			# アイドルアニメーションを維持（sidestepはしない）
			_point_handler._update_idle_animation_while_waiting()
			return  # 待機継続

	# キャラクターキャッシュ更新（150ms間隔）
	_characters_cache_timer += delta
	if _characters_cache_timer >= CHARACTERS_CACHE_INTERVAL:
		_characters_cache_timer = 0.0
		_characters_cache = get_tree().get_nodes_in_group("characters")

	# 衝突検出タイマー更新（100ms間隔）
	_collision_check_timer += delta

	# 回避クールダウンタイマー更新
	if _collision_avoidance.avoidance_cooldown_timer > 0:
		_collision_avoidance.avoidance_cooldown_timer -= delta

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

	# ドアポイントのチェック（最終目的地到達前に優先チェック）
	# ドアポイントがある場合、パス完了より先に停止してドアキックを実行
	var early_progress = _calculate_path_progress()
	var door_idx_arr: Array[int] = [_door_index]
	if _door_handler.check_door_points(early_progress, _door_points, door_idx_arr):
		_door_index = door_idx_arr[0]
		return  # ドアポイントに到達、処理を中断
	_door_index = door_idx_arr[0]

	# 最終目的地に十分近ければ完了
	if distance_to_final < final_destination_radius:
		_finish()
		return

	# 味方衝突検出: 最終目的地付近に味方がいれば現在位置で停止
	if distance_to_final < final_destination_radius + ally_collision_radius:
		if _point_handler.is_ally_at_destination(_current_path, _characters_cache, ally_collision_radius):
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
			path_progress_updated.emit(_path_index)
			if _path_index >= _current_path.size():
				_finish()
				return
	else:
		_stuck_time = 0.0
	_last_position = char_pos

	# 目標点に到達したら次へ
	if distance < 0.25:
		_path_index += 1
		path_progress_updated.emit(_path_index)
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

	# 速度選択: 常に歩行速度を使用
	var speed: float = anim_ctrl.get_current_speed()
	var is_running_now: bool = false

	# 最後の移動方向を保存（完了時の向き保持用）
	if move_dir.length_squared() > 0.1:
		_last_move_direction = move_dir

	# Clearポイントのチェック（視線・Runをリセット）
	_point_handler.check_clear_points(progress, _clear_points)

	# グレネードポイントのチェック（投擲実行、移動は継続）
	_point_handler.check_grenade_points(progress, _grenade_points)

	# スモークグレネードポイントのチェック（投擲実行、移動は継続）
	_point_handler.check_smoke_grenade_points(progress, _smoke_grenade_points)

	# Waitポイントのチェック（待機開始）
	if _point_handler.check_wait_points(progress):
		return  # Waitポイントに到達、処理を中断

	# ドアポイントは早期チェック済み（最終目的地到達前に処理）

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
			# 1. 敵視認チェック（最優先、ただし手動回転中はスキップ）
			var is_manual_rotating: bool = _character.is_manual_rotating() if _character.has_method("is_manual_rotating") else false
			if not is_manual_rotating and _combat_awareness and _combat_awareness.has_method("is_tracking_enemy"):
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
	# ただし、Doorポイントが設定されているドアは除外（Doorポイントで処理される）
	var closed_door = _door_handler.check_closed_door_ahead(move_dir)
	if closed_door and not _door_handler.is_door_in_points(closed_door, _door_points):
		_door_handler.is_waiting_for_closed_door = true
		_door_handler.waiting_door = closed_door
		_character.velocity = Vector3.ZERO
		# アイドルアニメーションに切り替え
		_point_handler._update_idle_animation_while_waiting()
		return

	# 衝突回避チェック（100ms間隔、クールダウン中はスキップ）
	if _collision_check_timer >= COLLISION_CHECK_INTERVAL and _collision_avoidance.avoidance_cooldown_timer <= 0:
		_collision_check_timer = 0.0
		var ally_ahead: Node = _collision_avoidance.detect_ally_ahead(move_dir, _characters_cache, collision_check_radius, collision_check_distance)
		if ally_ahead:
			_collision_avoidance.avoidance_blocker = ally_ahead
			var dist: float = _collision_avoidance.get_distance_to_ally(ally_ahead)
			var head_on: bool = _collision_avoidance.is_head_on_collision()
			var should_yield: bool = _collision_avoidance.should_yield_to(ally_ahead)

			# 相手が sidestep 中なら、こちらは通常通り進む
			if _collision_avoidance.is_other_sidestepping(ally_ahead):
				_collision_avoidance.avoidance_blocker = null
			# 相手との距離が非常に近い場合 or Head-on
			elif dist < collision_check_radius * 1.2 or head_on:
				# 低優先度が sidestep して避ける、高優先度はそのまま進む
				if should_yield:
					_collision_avoidance.start_sidestep()
					return
				else:
					_collision_avoidance.avoidance_blocker = null
			elif should_yield:
				# 追いつきなど: 低優先度が sidestep
				_collision_avoidance.start_sidestep()
				return
			else:
				_collision_avoidance.avoidance_blocker = null  # 高優先度なので進む

	# 物理移動（スムージング適用）
	# 移動方向をスムーズに補間してカーブ時のカクつきを軽減
	if _smoothed_move_direction.length_squared() < 0.001:
		_smoothed_move_direction = move_dir
	else:
		# 急カーブ検出: 現在方向と目標方向の角度が大きいほど追従を強化
		var angle_dot = _smoothed_move_direction.dot(move_dir)
		# angle_dot: 1.0=同方向, 0.0=直角, -1.0=逆方向
		# 急カーブ（90度以上）では追従を3倍に強化
		var sharp_turn_factor = 1.0
		if angle_dot < 0.5:  # 約60度以上の曲がり
			sharp_turn_factor = lerpf(1.0, 3.0, clampf((0.5 - angle_dot) / 1.5, 0.0, 1.0))
		_smoothed_move_direction = _smoothed_move_direction.lerp(move_dir, direction_smoothing * sharp_turn_factor * delta)
		if _smoothed_move_direction.length_squared() > 0.001:
			_smoothed_move_direction = _smoothed_move_direction.normalized()

	_character.velocity.x = _smoothed_move_direction.x * speed
	_character.velocity.z = _smoothed_move_direction.z * speed

	if not _character.is_on_floor():
		_character.velocity.y -= 9.8 * delta

	_character.move_and_slide()


## 視線方向を更新（距離ベースの検出 + 物理的近接チェック）
func _update_vision_direction() -> void:
	var char_distance := _calculate_distance_traveled()
	if not _vision_checker.has_points():
		# ターゲットポイントが設定されている場合、動的に方向を計算
		if _active_target_point.length_squared() > 0.001:
			_calculate_direction_to_target()
		else:
			_forced_look_direction = Vector3.ZERO
		return

	# キャラクター位置を取得
	var char_pos := Vector3.ZERO
	if _character:
		char_pos = _character.global_position
		char_pos.y = 0.0

	# 物理的近接チェック付きの到達判定
	# Q字型パスでは、パス距離を超えても物理的に離れている場合がある
	const PHYSICAL_PROXIMITY_THRESHOLD := 0.3  # 物理的な近接判定しきい値（小さいほど正確）

	while _vision_checker.get_current_index() < _vision_checker.get_count():
		var idx := _vision_checker.get_current_index()
		var vp: Dictionary = _vision_checker.get_point_at(idx)
		var point_distance: float = vp.get("path_distance", 0.0)

		# パス距離チェック
		if char_distance < point_distance:
			break  # まだこのポイントに到達していない

		# 物理的近接チェック（Q字型パス対策）
		var anchor: Vector3 = vp.get("anchor", Vector3.ZERO)
		anchor.y = 0.0
		var physical_dist := char_pos.distance_to(anchor)

		if physical_dist > PHYSICAL_PROXIMITY_THRESHOLD:
			# パス距離は超えたが物理的に離れている - 待機
			break

		# 両方の条件を満たした - ポイント到達
		_vision_checker.set_current_index(idx + 1)

		# ターゲットポイントモードかどうかをチェック
		if vp.has("target_point"):
			_active_target_point = vp.target_point
			_calculate_direction_to_target()
		elif vp.has("direction"):
			_forced_look_direction = vp.direction
			_active_target_point = Vector3.ZERO
		# シグナル発火（point_dataを直接渡す - WaitPointと統一）
		vision_point_reached.emit(idx, vp)

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
	# 残りの全ポイントを処理（パス完了時）
	var remaining := _vision_checker.get_remaining_count()
	for i in range(remaining):
		var idx := _vision_checker.get_current_index()
		var vp := _vision_checker.get_point_at(idx)
		if vp.has("target_point"):
			_active_target_point = vp.target_point
			_calculate_direction_to_target()
		elif vp.has("direction"):
			_forced_look_direction = vp.direction
			_active_target_point = Vector3.ZERO
		_vision_checker.set_current_index(idx + 1)


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


## パスの先頭から最初の有効セグメント方向を取得
## 重複点やゼロ長セグメントをスキップして最初の有効な方向を返す
func _get_first_segment_direction(path: Array[Vector3], start_index: int = 0) -> Vector3:
	if path.size() < 2:
		return Vector3.ZERO

	var start := clampi(start_index, 0, path.size() - 2)
	for i in range(start + 1, path.size()):
		var segment = path[i] - path[i - 1]
		segment.y = 0
		if segment.length_squared() > 0.001:
			return segment.normalized()

	return Vector3.ZERO


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


## キャラクターの移動距離を計算（パス開始点からの累積距離）
## 自己交差するパス（Q字型など）での距離ジャンプを防ぐため、単調増加を保証
func _calculate_distance_traveled() -> float:
	if _current_path.size() < 2 or not _character:
		return 0.0

	var char_pos = _character.global_position
	char_pos.y = 0

	var best_distance = INF
	var best_accumulated_length = 0.0
	var start_segment := maxi(1, _path_index)

	for i in range(start_segment, _current_path.size()):
		var p1 = _current_path[i - 1]
		var p2 = _current_path[i]
		p1.y = 0
		p2.y = 0

		var segment = p2 - p1
		var segment_length_sq = segment.length_squared()
		if segment_length_sq < 0.000001:
			continue

		var t = clampf((char_pos - p1).dot(segment) / segment_length_sq, 0.0, 1.0)
		var point_on_segment = p1 + segment * t
		var distance = char_pos.distance_to(point_on_segment)

		if distance < best_distance:
			best_distance = distance
			var segment_length = sqrt(segment_length_sq)
			best_accumulated_length = _cached_segment_lengths[i - 1] + segment_length * t

	# 自己交差パス対策: 距離が急激に増加した場合は制限
	# キャラクターの最大移動速度を考慮（走行速度 ~8 units/sec → 60fpsで ~0.13/frame）
	# 余裕を持って 0.5 units/frame を最大増加量とする
	const MAX_DISTANCE_INCREASE := 0.5
	if best_accumulated_length > _last_distance_traveled + MAX_DISTANCE_INCREASE:
		# 急激なジャンプを検出 - 前回の位置から少しだけ進める
		best_accumulated_length = _last_distance_traveled + MAX_DISTANCE_INCREASE

	# 距離は減少しない（後退しない）
	if best_accumulated_length < _last_distance_traveled:
		best_accumulated_length = _last_distance_traveled

	_last_distance_traveled = best_accumulated_length
	return best_accumulated_length


## anchor位置のパス上での距離を計算（パス開始点からの累積距離）
func _calculate_anchor_distance(anchor: Vector3) -> float:
	if _current_path.size() < 2:
		return 0.0

	var pos = anchor
	pos.y = 0

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

		var t = clampf((pos - p1).dot(segment) / segment_length_sq, 0.0, 1.0)
		var point_on_segment = p1 + segment * t
		var distance = pos.distance_to(point_on_segment)

		if distance < best_distance:
			best_distance = distance
			var segment_length = sqrt(segment_length_sq)
			best_accumulated_length = _cached_segment_lengths[i - 1] + segment_length * t

	return best_accumulated_length


## 指定したパス上でのanchor位置の距離を計算
func _calculate_anchor_distance_on_path(path: Array, anchor: Vector3) -> float:
	if path.size() < 2:
		return 0.0

	var pos = anchor
	pos.y = 0

	var best_distance = INF
	var best_accumulated_length = 0.0
	var accumulated_length = 0.0

	for i in range(1, path.size()):
		var p1 = path[i - 1]
		var p2 = path[i]
		p1.y = 0
		p2.y = 0

		var segment = p2 - p1
		var segment_length_sq = segment.length_squared()
		if segment_length_sq < 0.000001:
			continue

		var segment_length = sqrt(segment_length_sq)
		var t = clampf((pos - p1).dot(segment) / segment_length_sq, 0.0, 1.0)
		var point_on_segment = p1 + segment * t
		var distance = pos.distance_to(point_on_segment)

		if distance < best_distance:
			best_distance = distance
			best_accumulated_length = accumulated_length + segment_length * t

		accumulated_length += segment_length

	return best_accumulated_length


## Run区間内かどうかを判定
func _is_in_run_segment(progress: float) -> bool:
	for seg in _run_segments:
		if seg.has("start_ratio") and seg.has("end_ratio"):
			if progress >= seg.start_ratio and progress < seg.end_ratio:
				return true
	return false


## パス追従完了
func _finish() -> void:
	# 延長パスがある場合は切り替えて移動継続
	if _extension_handler.has_extension_path():
		if _extension_handler.switch_to_extension_path():
			# ハンドラーの状態をリセット（延長パスでは新しい状態で開始）
			_point_handler.reset()
			_door_handler.reset()
			_collision_avoidance.reset()
			return

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

			# 1. 敵を追跡中なら敵方向を維持（最優先、ただし手動回転中はスキップ）
			var is_manual_rotating: bool = _character.is_manual_rotating() if _character.has_method("is_manual_rotating") else false
			if not is_manual_rotating and _combat_awareness and _combat_awareness.has_method("is_tracking_enemy"):
				if _combat_awareness.is_tracking_enemy():
					final_dir = _combat_awareness.get_override_look_direction()

			# 2. 視線ポイント or 3. 最後の移動方向
			if final_dir.length_squared() < 0.1:
				final_dir = _forced_look_direction if _forced_look_direction.length_squared() > 0.1 else _last_move_direction

			if final_dir.length_squared() < 0.1:
				final_dir = Vector3.FORWARD
			# アイドル状態に遷移（移動方向をゼロに）
			anim_ctrl.update_animation(Vector3.ZERO, final_dir, false, 0.016)

			# _facing_direction を更新してネットワーク同期に反映
			# これにより、パス完了時の向きがリモート側で正しく表示される
			_character._facing_direction = final_dir.normalized()

	_is_following = false
	_smoothed_move_direction = Vector3.ZERO
	_current_path.clear()
	_vision_checker.clear()
	_run_segments.clear()
	_clear_points.clear()
	_grenade_points.clear()
	_door_points.clear()
	_wait_checker.clear()
	_forced_look_direction = Vector3.ZERO
	_active_target_point = Vector3.ZERO
	_last_move_direction = Vector3.ZERO

	# ハンドラーの状態をリセット
	_point_handler.reset()
	_door_handler.reset()
	_collision_avoidance.reset()

	path_completed.emit()


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
	if _point_handler.is_sync_waiting:
		return {
			"is_waiting": true,
			"type": "sync",
			"remaining": -1.0  # 無期限
		}
	elif _point_handler.is_waiting_for_wait:
		return {
			"is_waiting": true,
			"type": "wait",
			"remaining": maxf(0.0, _point_handler.current_wait_duration - _point_handler.wait_timer)
		}
	elif _door_handler.is_waiting_for_door:
		return {
			"is_waiting": true,
			"type": "door",
			"remaining": 0.0  # ドアキック時間は外部で管理
		}
	elif _door_handler.is_waiting_for_closed_door:
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


## 同期待機中かどうか
func is_sync_waiting() -> bool:
	return _point_handler.is_sync_waiting


## 同期待機を解除して移動を再開
func release_sync_wait() -> void:
	_point_handler.release_sync_wait()


## パス追従中かどうか（_is_followingの公開版）
func is_active() -> bool:
	return _is_following


## ドアキック完了後にパス追従を再開
func resume_after_door() -> void:
	_door_handler.resume_after_door()


## ========================================
## パス延長機能（移動中のパス延長）- ハンドラーへのデリゲーション
## ========================================

## 現在のパス終点を取得
func get_path_endpoint() -> Vector3:
	if _current_path.size() == 0:
		return Vector3.ZERO
	return _current_path[_current_path.size() - 1]


## パスにポイントを追加（移動中の延長用）
func append_path_point(point: Vector3) -> void:
	_current_path.append(point)
	# 新しいセグメントの長さをキャッシュに追加（全体再計算を避ける）
	if _current_path.size() >= 2:
		var new_segment_length = _current_path[_current_path.size() - 2].distance_to(point)
		_cached_total_length += new_segment_length
		_cached_segment_lengths.append(_cached_total_length)


## 現在の全パスをPackedVector3Arrayとして取得（メッシュ更新用）
func get_current_path_packed() -> PackedVector3Array:
	var result := PackedVector3Array()
	for p in _current_path:
		result.append(p)
	return result


## 残りパスと延長パスを結合して取得（Visionポイント配置用）
## @return: PackedVector3Array（現在位置から先のパス全体）
func get_full_remaining_path() -> PackedVector3Array:
	var result := PackedVector3Array()

	# 残りの元のパス（現在のインデックスから終点まで）
	for i in range(_path_index, _current_path.size()):
		result.append(_current_path[i])

	# 延長パスがある場合は追加（最初の点は元のパス終点と重複するのでスキップ）
	if _extension_handler.has_extension_path() and _extension_handler._extension_path.size() > 0:
		var ext_path = _extension_handler._extension_path
		var start_idx = 1 if ext_path[0].distance_to(_current_path[_current_path.size() - 1]) < 0.1 else 0
		for i in range(start_idx, ext_path.size()):
			result.append(ext_path[i])

	return result


## 残りのパスデータを取得（延長用）
## @return: { path: Array[Vector3], vision_points: Array, run_segments: Array, ... }
func get_remaining_path_data() -> Dictionary:
	if not _is_following or _current_path.size() == 0:
		return {}

	# 現在のパス終点を返す（延長はパス終点から開始）
	var endpoint := get_path_endpoint()

	return {
		"path": [endpoint],  # 延長開始点のみ
		"endpoint": endpoint,
		"vision_points": [],  # 延長パスでは新規ポイントのみ
		"run_segments": [],
		"clear_points": [],
		"grenade_points_data": [],
		"smoke_grenade_points_data": [],
		"door_points_data": [],
		"wait_points_data": []
	}


## 延長パスがあるか
func has_extension_path() -> bool:
	return _extension_handler.has_extension_path()


## 延長パスの終点を取得
func get_extension_path_endpoint() -> Vector3:
	return _extension_handler.get_extension_path_endpoint()


## 延長パスを設定
func set_extension_path(extension_path: Array[Vector3], markers: Dictionary, append_to_existing: bool = false) -> void:
	_extension_handler.set_extension_path(extension_path, markers, append_to_existing)


## 延長パスをキャンセル
func cancel_extension() -> void:
	_extension_handler.cancel_extension()


## 延長パスのデータを取得（さらなる延長用）
func get_extension_path_data() -> Dictionary:
	return _extension_handler.get_extension_path_data()


## 移動中パスにVisionポイントを追加
func add_vision_point_to_extension(path_ratio: float, anchor: Vector3, target_point: Vector3) -> void:
	_extension_handler.add_vision_point_to_extension(path_ratio, anchor, target_point)


## Waitポイントを追加（実行中のパスに）
func add_wait_point(point_data: Dictionary) -> void:
	_extension_handler.add_wait_point(point_data)
