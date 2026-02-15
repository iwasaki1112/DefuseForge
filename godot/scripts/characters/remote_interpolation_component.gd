class_name RemoteInterpolationComponent
extends RefCounted

## リモートキャラクター用補間コンポーネント
## スナップショットバッファベースの補間と外挿を管理
## GameCharacterから抽出されたコンポーネント
##
## 送信時刻ベースの補間を使用:
## - スナップショットの時間軸は送信側のクロック（等間隔で安定）
## - WiFiジッターによるパケット到着のバラつきは時間軸に影響しない
## - ローカルクロックとのオフセットをEMAで推定し、レンダリング時刻を算出

# ============================================
# References
# ============================================

var _character: GameCharacter = null
var _anim_ctrl: CharacterAnimationController = null

# ============================================
# Snapshot Buffer
# ============================================

## スナップショットバッファ（送信時刻の時系列順に格納）
var _snapshot_buffer: Array[Dictionary] = []
## 補間処理がアクティブかどうか
var _active: bool = false
## レンダリング用タイムベース（送信側クロック基準）
var _render_time_base: float = 0.0
## 最後に受信したスナップショットの時刻（送信側クロック基準）
var _last_snapshot_time: float = 0.0
## 外挿中フラグ
var _is_extrapolating: bool = false
## 直近の速度（外挿用）
var _last_velocity: Vector3 = Vector3.ZERO
## 初回スナップショット受信フラグ
var _first_snapshot_received: bool = false
## 補間位置のスムージング用（ジャーク防止）
var _smoothed_position: Vector3 = Vector3.ZERO
## スムージング初期化フラグ
var _smoothing_initialized: bool = false

# ============================================
# Sender Time Offset Estimation
# ============================================

## ローカル時刻と送信側時刻のオフセット推定値（local_time - remote_time）
var _remote_time_offset: float = 0.0
## オフセット初期化済みフラグ
var _offset_initialized: bool = false

# ============================================
# Fallback (Legacy Compatibility)
# ============================================

## 旧実装との互換用（段階的移行）
var _target_position: Vector3 = Vector3.ZERO
var _target_rotation: float = 0.0
var _target_velocity: Vector3 = Vector3.ZERO
var _target_animation_state: String = ""

# ============================================
# Setup
# ============================================

## セットアップ
func setup(character: GameCharacter) -> void:
	_character = character
	_anim_ctrl = character.anim_ctrl if character else null


## アニメーションコントローラを設定
func set_anim_controller(ctrl: CharacterAnimationController) -> void:
	_anim_ctrl = ctrl

# ============================================
# Snapshot Management
# ============================================

## スナップショットを追加
## 送信時刻が利用可能な場合はそれを使用（ジッター耐性向上）
func add_snapshot(state: NetworkMessages.CharacterStateMessage, local_receive_time: float) -> void:
	# 送信時刻ベース or 受信時刻フォールバック
	var snapshot_time: float
	if state.timestamp > 0:
		var remote_time := state.timestamp / 1000.0
		var sample_offset := local_receive_time - remote_time
		if not _offset_initialized:
			_remote_time_offset = sample_offset
			_offset_initialized = true
		else:
			# EMA(α=0.1)でオフセットを平滑化（ネットワークジッター除去）
			_remote_time_offset += 0.1 * (sample_offset - _remote_time_offset)
		snapshot_time = remote_time
	else:
		# 旧バージョン互換: 送信時刻なし → 受信時刻を使用
		snapshot_time = local_receive_time

	# 初回スナップショット時に時刻基準を初期化
	if not _first_snapshot_received:
		_first_snapshot_received = true
		_render_time_base = snapshot_time - NetworkConstants.INTERPOLATION_DELAY

	var snapshot := {
		"time": snapshot_time,
		"position": state.position,
		"rotation": state.rotation,
		"velocity": state.velocity,
		"animation_state": state.animation_state
	}
	_snapshot_buffer.append(snapshot)
	_last_snapshot_time = snapshot_time
	_is_extrapolating = false

	# バッファサイズ制限
	while _snapshot_buffer.size() > NetworkConstants.SNAPSHOT_BUFFER_SIZE:
		_snapshot_buffer.pop_front()

	# 旧実装との互換
	_target_position = state.position
	_target_rotation = state.rotation
	_target_velocity = state.velocity
	_target_animation_state = state.animation_state
	_last_velocity = state.velocity


## スナップショットバッファをクリア
func clear() -> void:
	_snapshot_buffer.clear()
	_is_extrapolating = false
	_active = false
	_first_snapshot_received = false
	_render_time_base = 0.0
	_smoothing_initialized = false
	_remote_time_offset = 0.0
	_offset_initialized = false


## 初回スナップショットが受信済みか
func has_received_first_snapshot() -> bool:
	return _first_snapshot_received


## 補間を有効化
func activate() -> void:
	_active = true


## 補間を無効化
func deactivate() -> void:
	_active = false
	clear()

# ============================================
# Interpolation Update
# ============================================

## リモートキャラクターの補間更新（毎フレーム呼び出し）
func update(delta: float) -> void:
	if not _active or not _character or not _character.is_alive:
		return

	# レンダリング時刻の更新
	_render_time_base += delta

	# 送信時刻オフセットが確立されたら、送信側クロック基準でドリフト補正
	if _offset_initialized:
		var local_now := Time.get_ticks_msec() / 1000.0
		# 送信側クロックでの「現在時刻」を推定し、補間遅延分を引く
		var ideal_render_time := (local_now - _remote_time_offset) - NetworkConstants.INTERPOLATION_DELAY
		var drift := _render_time_base - ideal_render_time
		# 大きなドリフトは即座にリセット（接続復帰時など）
		if absf(drift) > 0.5:
			_render_time_base = ideal_render_time
		elif absf(drift) > 0.01:
			# 緩やかに補正（比例制御 — オフセットが安定しているため追従可能）
			_render_time_base -= drift * minf(3.0 * delta, 1.0)

	# バッファベースの補間を試行
	var interpolated := _get_interpolated_state()

	if interpolated.is_empty():
		# バッファが不十分な場合はフォールバック（旧実装）
		_apply_fallback_interpolation(delta)
	else:
		# スムージング初期化
		if not _smoothing_initialized:
			_smoothed_position = _character.global_position
			_smoothing_initialized = true

		# 補間位置をスムージング（ジャーク防止）
		var target_pos: Vector3 = interpolated.position
		var smooth_factor := minf(12.0 * delta, 1.0)
		_smoothed_position = _smoothed_position.lerp(target_pos, smooth_factor)
		_character.global_position = _smoothed_position
		_character.set_facing_direction(interpolated.rotation)

		# 回転は四元数SLERPで滑らかに補間
		if _anim_ctrl and _anim_ctrl.has_method("update_model_rotation_smooth"):
			_anim_ctrl.update_model_rotation_smooth(_character.get_facing_direction(), delta)

		# アニメーション更新
		_update_animation(interpolated, delta)


## 初回スナップショット受信時またはテレポート時の初期化
func initialize_position(state: NetworkMessages.CharacterStateMessage) -> void:
	if not _character:
		return
	_character.global_position = state.position
	_character.set_facing_direction(state.rotation)
	# 送信時刻が利用可能ならそれを基準にrender_timeを初期化
	if state.timestamp > 0 and _offset_initialized:
		_render_time_base = (state.timestamp / 1000.0) - NetworkConstants.INTERPOLATION_DELAY
	else:
		_render_time_base = Time.get_ticks_msec() / 1000.0 - NetworkConstants.INTERPOLATION_DELAY
	# スムージング位置も初期化
	_smoothed_position = state.position
	_smoothing_initialized = true
	# スナップショットバッファをクリア（テレポート時の引き戻し防止）
	_snapshot_buffer.clear()
	# ターゲット値も更新
	_target_position = state.position
	_target_rotation = state.rotation
	_target_velocity = state.velocity

# ============================================
# State Getters
# ============================================

## 補間がアクティブか
func is_active() -> bool:
	return _active


## 外挿中か
func is_extrapolating() -> bool:
	return _is_extrapolating


## ターゲットアニメーション状態を取得（旧実装互換）
func get_target_animation_state() -> String:
	return _target_animation_state

# ============================================
# Internal: Interpolation Logic
# ============================================

## バッファから補間された状態を取得
func _get_interpolated_state() -> Dictionary:
	if _snapshot_buffer.size() < 2:
		return {}

	var target_time := _render_time_base

	# 補間可能な2点を探す
	for i in range(_snapshot_buffer.size() - 1):
		var before: Dictionary = _snapshot_buffer[i]
		var after: Dictionary = _snapshot_buffer[i + 1]

		var before_time: float = before.time
		var after_time: float = after.time
		if before_time <= target_time and target_time <= after_time:
			# ゼロ割を防止
			var time_diff := after_time - before_time
			var t: float = (target_time - before_time) / time_diff if time_diff > 0.0001 else 0.5
			t = clampf(t, 0.0, 1.0)
			_is_extrapolating = false
			# アニメーション状態は補間せず、近い方を使用
			var anim_state: String = after.get("animation_state", "") if t > 0.5 else before.get("animation_state", "")
			return {
				"position": (before.position as Vector3).lerp(after.position, t),
				"rotation": lerp_angle(before.rotation as float, after.rotation as float, t),
				"velocity": (before.velocity as Vector3).lerp(after.velocity, t),
				"animation_state": anim_state
			}

	# 最新のスナップショットより未来の場合は外挿
	var latest: Dictionary = _snapshot_buffer.back()
	var latest_time: float = latest.time
	var time_since_latest: float = target_time - latest_time

	if time_since_latest > 0.0 and time_since_latest < NetworkConstants.MAX_EXTRAPOLATION_TIME:
		_is_extrapolating = true
		# 外挿速度を減衰（オーバーシュート → スナップバック振動の防止）
		var damped_velocity: Vector3 = latest.velocity * 0.7
		var extrapolated_pos: Vector3 = latest.position + damped_velocity * time_since_latest
		return {
			"position": extrapolated_pos,
			"rotation": latest.rotation,
			"velocity": latest.velocity,
			"animation_state": latest.get("animation_state", "")
		}

	# 外挿限界を超えた場合は最新値を返す
	if not _snapshot_buffer.is_empty():
		_is_extrapolating = true
		return {
			"position": latest.position,
			"rotation": latest.rotation,
			"velocity": Vector3.ZERO,
			"animation_state": latest.get("animation_state", "")
		}

	return {}


## フォールバック補間（旧実装との互換）
func _apply_fallback_interpolation(delta: float) -> void:
	if not _character:
		return

	const FALLBACK_SPEED := 12.0

	# 位置の補間（低FPS時のオーバーシュート防止）
	var lerp_factor := minf(FALLBACK_SPEED * delta, 1.0)
	var new_pos := _character.global_position.lerp(_target_position, lerp_factor)
	_character.global_position = new_pos
	# スムージング位置も同期（モード切替時のジャーク防止）
	_smoothed_position = new_pos
	_smoothing_initialized = true

	# 回転の補間（低FPS時のオーバーシュート防止）
	var facing := _character.get_facing_direction()
	var current_rot := atan2(facing.x, facing.z)
	var rot_diff := fmod(_target_rotation - current_rot + PI, TAU) - PI
	var new_rot := current_rot + rot_diff * minf(FALLBACK_SPEED * delta, 1.0)
	_character.set_facing_direction(new_rot)

	# 回転は四元数SLERPで滑らかに補間
	if _anim_ctrl and _anim_ctrl.has_method("update_model_rotation_smooth"):
		_anim_ctrl.update_model_rotation_smooth(_character.get_facing_direction(), delta)

	# アニメーション更新
	_update_fallback_animation(delta)


## アニメーション更新（補間状態から）
func _update_animation(interpolated: Dictionary, delta: float) -> void:
	if not _anim_ctrl:
		return

	var anim_state: String = interpolated.get("animation_state", "")
	if not anim_state.is_empty() and _anim_ctrl.has_method("apply_animation_state"):
		_anim_ctrl.apply_animation_state(anim_state, delta)
	else:
		# フォールバック: velocity から推論
		var vel: Vector3 = interpolated.get("velocity", Vector3.ZERO)
		var move_dir := vel.normalized() if vel.length_squared() > 0.01 else Vector3.ZERO
		var is_running := vel.length() > 3.0
		_anim_ctrl.update_animation(move_dir, _character.get_facing_direction(), is_running, delta)


## アニメーション更新（フォールバック）
func _update_fallback_animation(delta: float) -> void:
	if not _anim_ctrl or not _character:
		return

	if not _target_animation_state.is_empty() and _anim_ctrl.has_method("apply_animation_state"):
		_anim_ctrl.apply_animation_state(_target_animation_state, delta)
	else:
		# フォールバック: velocity から推論
		var move_dir := _target_velocity.normalized() if _target_velocity.length_squared() > 0.01 else Vector3.ZERO
		var is_running := _target_velocity.length() > 3.0
		_anim_ctrl.update_animation(move_dir, _character.get_facing_direction(), is_running, delta)
