extends Node
class_name IKActionPlayer

## IK-based action trajectory manager
##
## Tweenベースのキーフレーム補間でアクション（投擲・ドア開け・近接）の
## IKターゲット軌跡を管理する。AnimationTree停止不要で、下半身歩行を維持。

# ============================================
# Data Structures
# ============================================

## アクションキーフレーム
class ActionKeyframe:
	var time: float  ## 開始からの秒数
	var right_hand_pos: Vector3  ## 右手IKターゲット位置（キャラ原点基準）
	var right_hand_pole: Vector3  ## 右手IKポール位置（キャラ原点基準）
	var left_ik_enabled: bool = true  ## 左手IK有効
	var spine_pitch: float = 0.0  ## 背骨ピッチ（ラジアン）
	var easing: Tween.EaseType = Tween.EASE_IN_OUT

	func _init(
		p_time: float = 0.0,
		p_hand: Vector3 = Vector3.ZERO,
		p_pole: Vector3 = Vector3.ZERO,
		p_left_ik: bool = true,
		p_pitch: float = 0.0,
		p_easing: Tween.EaseType = Tween.EASE_IN_OUT
	) -> void:
		time = p_time
		right_hand_pos = p_hand
		right_hand_pole = p_pole
		left_ik_enabled = p_left_ik
		spine_pitch = p_pitch
		easing = p_easing


## アクション定義
class ActionDefinition:
	var keyframes: Array[ActionKeyframe] = []
	var signals: Dictionary = {}  ## { time(float): signal_name(String) }
	var total_duration: float = 0.0

	func add_keyframe(kf: ActionKeyframe) -> void:
		keyframes.append(kf)
		if kf.time > total_duration:
			total_duration = kf.time


# ============================================
# Signals
# ============================================
signal action_signal(signal_name: String)
signal action_finished()

# ============================================
# State
# ============================================
var _ubik: UpperBodyIKController  ## 上半身IKコントローラー参照
var _current_tween: Tween
var _is_playing := false
var _signal_timers: Array[SceneTreeTimer] = []

# ============================================
# Setup
# ============================================

func setup(ubik: UpperBodyIKController) -> void:
	_ubik = ubik
	if _ubik:
		_ubik.set_action_player(self)


# ============================================
# Public API
# ============================================

## アクション再生
func play(definition: ActionDefinition) -> void:
	if _is_playing:
		cancel()

	if not _ubik or definition.keyframes.is_empty():
		return

	_is_playing = true
	_ubik.set_state(UpperBodyIKController.IKState.ACTION)

	# シグナルタイマー設定
	for time_key in definition.signals:
		var sig_time: float = time_key
		var sig_name: String = definition.signals[time_key]
		var timer := get_tree().create_timer(sig_time)
		timer.timeout.connect(func(): _emit_action_signal(sig_name), CONNECT_ONE_SHOT)
		_signal_timers.append(timer)

	# Tweenでキーフレーム間を補間
	_current_tween = create_tween()
	_current_tween.set_ease(Tween.EASE_IN_OUT)
	_current_tween.set_trans(Tween.TRANS_CUBIC)

	var prev_time := 0.0
	for kf in definition.keyframes:
		var duration := kf.time - prev_time
		if duration > 0.001:
			var target_hand := kf.right_hand_pos
			var target_pole := kf.right_hand_pole
			var target_pitch := kf.spine_pitch
			var left_ik := kf.left_ik_enabled

			_current_tween.tween_method(
				func(t: float) -> void:
					_update_action_frame(t, target_hand, target_pole, target_pitch, left_ik),
				0.0, 1.0, duration
			).set_ease(kf.easing).set_trans(Tween.TRANS_CUBIC)
		prev_time = kf.time

	_current_tween.tween_callback(_on_action_finished)


## アクション中断
func cancel() -> void:
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = null
	_is_playing = false
	_signal_timers.clear()
	if _ubik:
		_ubik.set_state(UpperBodyIKController.IKState.READY)


## 再生中かどうか
func is_playing() -> bool:
	return _is_playing


# ============================================
# Internal
# ============================================

func _update_action_frame(
	_t: float,
	hand_pos: Vector3,
	pole_pos: Vector3,
	spine_pitch: float,
	left_ik_enabled: bool
) -> void:
	if not _ubik:
		return
	_ubik.set_right_hand_target_position(hand_pos)
	_ubik.set_right_hand_pole_position(pole_pos)
	_ubik.set_posture_pitch(spine_pitch)
	_ubik.set_left_hand_ik_enabled(left_ik_enabled)


func _emit_action_signal(sig_name: String) -> void:
	if _is_playing:
		action_signal.emit(sig_name)


func _on_action_finished() -> void:
	_is_playing = false
	_signal_timers.clear()
	_current_tween = null
	if _ubik:
		_ubik.set_state(UpperBodyIKController.IKState.READY)
	action_finished.emit()


func _exit_tree() -> void:
	cancel()
