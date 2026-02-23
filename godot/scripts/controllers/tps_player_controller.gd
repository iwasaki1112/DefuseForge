class_name TPSPlayerController
extends Node
## TPS操作コントローラー
##
## GameScreenで使用する再利用可能なTPSプレイヤー制御。
## ツインスティック（左: 移動、右: 向き/エイム）+ WASD + マウス操作。
## 左スティックで移動しつつ、右スティックで任意の方向を向ける。
## CombatAwareness連携（敵検知時は自動で敵を向く）。
##
## 使用方法:
##   var ctrl = TPSPlayerController.new()
##   add_child(ctrl)
##   ctrl.setup(character, camera, ui_layer)
##
## _physics_process内でctrl.process(delta)を呼び出し、
## _input内でctrl.handle_input(event)を呼び出す。

# ============================================
# Configurable Parameters
# ============================================
var camera_height := 14.0
var camera_pitch_deg := -90.0
var enable_aim_stick := true

# ============================================
# Constants
# ============================================
const CAMERA_FOV := 30.0
const CAMERA_SMOOTH := 8.0
const CAMERA_ZOOM_SMOOTH := 4.0
const GROUND_Y := 0.0
const DEFAULT_VISION_RANGE := 7.0

# Move stick (left)
const STICK_RADIUS := 80.0
const STICK_KNOB_RADIUS := 30.0
const STICK_DEADZONE := 0.15

# Aim stick (right)
const AIM_STICK_RADIUS := 80.0
const AIM_STICK_KNOB_RADIUS := 30.0
## 右スティックが敵方向からこの角度以上ずれた場合のみ手動エイムに切り替え
const AIM_OVERRIDE_ANGLE := deg_to_rad(60.0)

# ============================================
# References
# ============================================
var _character: GameCharacter = null
var _camera: Camera3D = null
var _ui_layer: CanvasLayer = null

# Move stick state (left side)
var _stick_base: Control = null
var _stick_knob: Control = null
var _stick_touch_idx: int = -1
var _stick_input: Vector2 = Vector2.ZERO
var _stick_center: Vector2 = Vector2.ZERO

# Aim stick state (right side)
var _aim_stick_base: Control = null
var _aim_stick_knob: Control = null
var _aim_stick_touch_idx: int = -1
var _aim_stick_input: Vector2 = Vector2.ZERO
var _aim_stick_center: Vector2 = Vector2.ZERO

# Movement direction cache
var _last_move_dir: Vector3 = Vector3.ZERO

# 右スティック操作中フラグ（自動エイム・自動射撃を一時停止するため）
var _is_aim_stick_active: bool = false

# スプリント状態（ボタン押下中）
var _is_sprinting: bool = false

# スプリント中の滑らかな方向転換（角速度キャップ方式）
var _sprint_dir: Vector3 = Vector3.ZERO
const SPRINT_MAX_TURN_RATE := 12.0  # rad/s（180°転換 ≈ 0.26秒）

# 向き固定（投擲アニメーション中など）
var _facing_locked: bool = false
var _locked_facing: Vector3 = Vector3.FORWARD

# カメラズーム（武器視界距離連動）
var _base_camera_height: float = 14.0
var _target_camera_height: float = 14.0


# Gun Down検出タイマー（毎フレームではなく100ms間隔）
var _gun_down_check_timer: float = 0.0
const GUN_DOWN_CHECK_INTERVAL := 0.1

# 近接攻撃（メレー）
var _melee_target: Node = null  ## 近接攻撃ターゲット
var _melee_cooldown: float = 0.0  ## メレー後クールダウン
var _melee_signals_connected: bool = false  ## シグナル接続済みフラグ
const MELEE_COOLDOWN_TIME := 0.5  ## メレー後のクールダウン（秒）



# ============================================
# Public API
# ============================================

## コントローラーを初期化する
## config: オプション設定 { "camera_height": float, "camera_pitch_deg": float, "enable_aim_stick": bool }
func setup(character: GameCharacter, cam: Camera3D, canvas: CanvasLayer, config: Dictionary = {}) -> void:
	camera_height = config.get("camera_height", camera_height)
	camera_pitch_deg = config.get("camera_pitch_deg", camera_pitch_deg)
	enable_aim_stick = config.get("enable_aim_stick", enable_aim_stick)

	_character = character
	_camera = cam
	_ui_layer = canvas
	_base_camera_height = camera_height
	_target_camera_height = camera_height

	# カメラをTPS用に設定
	if _camera:
		_camera.fov = CAMERA_FOV
		_camera.rotation_degrees.x = camera_pitch_deg
		# 初期位置をキャラクター上に設定
		if _character:
			var pitch_rad := deg_to_rad(camera_pitch_deg)
			var offset_z := camera_height / tan(-pitch_rad)
			_camera.global_position = _character.global_position + Vector3(0, camera_height, offset_z)

	# ジョイスティックUI作成（左: 移動、右: 向き）
	if _ui_layer:
		_create_move_stick(_ui_layer)
		if enable_aim_stick:
			_create_aim_stick(_ui_layer)


## 毎フレーム処理（_physics_processから呼ぶ）
func process(delta: float) -> void:
	if not _character or not _character.is_alive:
		return

	# 近接攻撃チェック（最優先 — 射撃より先に判定）
	if _process_melee(delta):
		_handle_movement(delta)
		_update_camera(delta)
		return

	# 3フェーズ実行: 検知 → エイム → 射撃
	# フェーズ1: 敵検知（ターゲット特定のみ、射撃しない）
	if _character.combat_awareness:
		_character.combat_awareness.process(delta)
	# スプリント中は右スティックエイムと自動射撃を無効化
	var is_sprint_active := _is_sprinting or Input.is_key_pressed(KEY_SHIFT)
	if not is_sprint_active:
		# フェーズ2: エイム更新（検知結果で向きを即座に設定）
		_handle_aim(delta)
		# フェーズ2.5: Gun Down検出（壁/味方接近時に武器を下げる）
		_update_gun_down(delta)
		# フェーズ3: 射撃判定（右スティック操作中も敵が射程内なら射撃する）
		if _character.combat_awareness:
			_character.combat_awareness.process_firing(delta)
	else:
		# スプリント中はgun_downを解除
		if _character.anim_ctrl:
			_character.anim_ctrl.set_gun_down(false)
	_handle_movement(delta)
	_update_camera(delta)


## 向きを固定する（投擲アニメーション中など）
func lock_facing(dir: Vector3) -> void:
	_facing_locked = true
	_locked_facing = dir
	if _character:
		_character.set_facing_direction_vec(dir)


## 向き固定を解除する
func unlock_facing() -> void:
	_facing_locked = false


## 入力処理（_inputから呼ぶ）
func handle_input(event: InputEvent) -> void:
	_handle_touch_input(event)


## 移動入力があるかどうかを返す（スティック or WASD）
func has_move_input() -> bool:
	if _stick_input.length() > STICK_DEADZONE:
		return true
	if Input.get_action_strength("move_forward") > 0.0:
		return true
	if Input.get_action_strength("move_backward") > 0.0:
		return true
	if Input.get_action_strength("move_left") > 0.0:
		return true
	if Input.get_action_strength("move_right") > 0.0:
		return true
	return false


## 武器の視界距離に合わせてカメラ高さを更新する（現在は固定）
func update_camera_for_weapon(_vision_range: float) -> void:
	_target_camera_height = _base_camera_height


## スプリント状態を設定（スプリントボタンから呼ばれる）
func set_sprinting(value: bool) -> void:
	_is_sprinting = value


## 操作対象のキャラクターを返す
func get_character() -> GameCharacter:
	return _character


# ============================================
# Movement
# ============================================

func _handle_movement(delta: float) -> void:
	# WASD input
	var input_dir := Vector2.ZERO
	input_dir.y -= Input.get_action_strength("move_forward")
	input_dir.y += Input.get_action_strength("move_backward")
	input_dir.x -= Input.get_action_strength("move_left")
	input_dir.x += Input.get_action_strength("move_right")

	# Combine with move joystick (left)
	input_dir.x += _stick_input.x
	input_dir.y += _stick_input.y

	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var move_dir := Vector3.ZERO
	var has_input := input_dir.length() > 0.01
	if has_input:
		input_dir = input_dir.normalized()
		move_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()
		_last_move_dir = move_dir
	else:
		_last_move_dir = Vector3.ZERO

	# PC: Shiftキーでもスプリント可能
	var is_sprint_input := _is_sprinting or Input.is_key_pressed(KEY_SHIFT)

	if _character.anim_ctrl:
		var aim_dir: Vector3
		if is_sprint_input and has_input:
			# スプリント中は角速度キャップで滑らかに方向転換
			if _sprint_dir.length_squared() < 0.001:
				_sprint_dir = move_dir
			else:
				var angle_diff := _sprint_dir.signed_angle_to(move_dir, Vector3.UP)
				var max_rotation := SPRINT_MAX_TURN_RATE * delta
				if absf(angle_diff) <= max_rotation:
					_sprint_dir = move_dir
				else:
					_sprint_dir = _sprint_dir.rotated(Vector3.UP, signf(angle_diff) * max_rotation).normalized()
			_character.set_facing_direction_vec(_sprint_dir)
			aim_dir = _sprint_dir
			move_dir = _sprint_dir
		elif is_sprint_input and not has_input:
			# スプリント中に入力なし: 方向を維持（キー切替の空きフレーム対策）
			if _sprint_dir.length_squared() > 0.001:
				_character.set_facing_direction_vec(_sprint_dir)
				aim_dir = _sprint_dir
				move_dir = Vector3.ZERO
			else:
				aim_dir = _character.get_facing_direction()
		else:
			_sprint_dir = Vector3.ZERO
			aim_dir = _character.get_facing_direction()
		_character.anim_ctrl.update_animation(move_dir, aim_dir, is_sprint_input, delta)

	var base_speed := _character.anim_ctrl.get_current_speed() if _character.anim_ctrl else 2.0
	_character.velocity = move_dir * base_speed
	_character.move_and_slide()


# ============================================
# Aim (Facing Direction)
# ============================================

func _handle_aim(_delta: float) -> void:
	# 0. 向き固定中はスキップ（投擲アニメーション等）
	if _facing_locked:
		_character.set_facing_direction_vec(_locked_facing)
		return

	# 敵方向を取得
	var combat_dir := Vector3.ZERO
	if _character.combat_awareness:
		combat_dir = _character.combat_awareness.get_override_look_direction()

	# 1. 右スティック — 敵検知中はスティックが敵方向から大きくずれた時のみ手動エイム
	_is_aim_stick_active = _aim_stick_input.length() > STICK_DEADZONE
	if _is_aim_stick_active:
		var aim_dir := Vector3(_aim_stick_input.x, 0, _aim_stick_input.y).normalized()
		if combat_dir != Vector3.ZERO:
			# 敵検知中: スティックが敵方向から閾値以上ずれている場合のみ手動エイム
			if aim_dir.angle_to(combat_dir) > AIM_OVERRIDE_ANGLE:
				_character.set_facing_direction_vec(aim_dir)
			else:
				_character.set_facing_direction_vec(combat_dir)
		else:
			# 敵なし: 通常の手動エイム
			_character.set_facing_direction_vec(aim_dir)
		return

	# 2. CombatAwareness override — 敵検知時は自動で敵方向を向く
	if combat_dir != Vector3.ZERO:
		_character.set_facing_direction_vec(combat_dir)
		return

	# 3. 移動方向 — フォールバック
	if _last_move_dir.length_squared() > 0.01:
		_character.set_facing_direction_vec(_last_move_dir)


# ============================================
# Gun Down Detection
# ============================================

func _update_gun_down(delta: float) -> void:
	_gun_down_check_timer += delta
	if _gun_down_check_timer < GUN_DOWN_CHECK_INTERVAL:
		return
	_gun_down_check_timer = 0.0
	if _character.anim_ctrl:
		_character.anim_ctrl.set_gun_down(_character.check_gun_down())


# ============================================
# Melee Attack (自動近接攻撃)
# ============================================

## 近接攻撃処理（メレー中ならtrue、通常フローをスキップさせる）
func _process_melee(delta: float) -> bool:
	# クールダウン減算
	if _melee_cooldown > 0.0:
		_melee_cooldown -= delta

	# メレーアニメーション再生中はブロック
	if _character.anim_ctrl and _character.anim_ctrl.is_meleeing():
		return true

	# クールダウン中は新規メレー不可（通常フローに戻す）
	if _melee_cooldown > 0.0:
		return false

	# 他のアクション中はスキップ
	if _character.anim_ctrl and (_character.anim_ctrl.is_throwing() or _character.anim_ctrl.is_opening_door() or _character.anim_ctrl.is_talking()):
		return false

	# スプリント中はメレー不可
	if _is_sprinting or Input.is_key_pressed(KEY_SHIFT):
		return false

	# 近接攻撃可能な敵を探す（円形360°）
	if not _character.combat_awareness:
		return false

	var target := _character.combat_awareness.get_melee_target()
	if not target:
		return false

	_melee_target = target

	# シグナル接続（初回のみ）
	_ensure_melee_signals()

	# 敵の方向を向く
	var dir: Vector3 = target.global_position - _character.global_position
	dir.y = 0
	if dir.length_squared() > 0.001:
		_character.set_facing_direction_vec(dir.normalized())

	# 近接攻撃アニメーション再生
	if _character.anim_ctrl:
		_character.anim_ctrl.play_melee()

	return true


## メレーシグナルを接続（一度だけ）
func _ensure_melee_signals() -> void:
	if _melee_signals_connected or not _character.anim_ctrl:
		return
	_character.anim_ctrl.melee_impact.connect(_on_melee_impact)
	_character.anim_ctrl.melee_finished.connect(_on_melee_finished_ctrl)
	_melee_signals_connected = true


## メレーインパクト：致死ダメージを与える（100%一撃キル）
## 攻撃者が死亡済みならキャンセル（先に殴った方が勝ち）
func _on_melee_impact() -> void:
	if not _character or not _character.is_alive:
		return
	if _melee_target and is_instance_valid(_melee_target):
		if _melee_target.has_method("take_damage") and "is_alive" in _melee_target and _melee_target.is_alive:
			var lethal_damage: float = _melee_target.max_health if "max_health" in _melee_target else 9999.0
			_melee_target.take_damage(lethal_damage, _character, false)


## メレー完了：ターゲットクリア＋クールダウン開始
func _on_melee_finished_ctrl() -> void:
	_melee_target = null
	_melee_cooldown = MELEE_COOLDOWN_TIME


# ============================================
# Camera (Fixed Follow)
# ============================================

func _update_camera(delta: float) -> void:
	if not _character or not _camera:
		return
	# カメラ高さを目標値に向けて滑らかに遷移
	camera_height = lerpf(camera_height, _target_camera_height, CAMERA_ZOOM_SMOOTH * delta)
	var pitch_rad := deg_to_rad(camera_pitch_deg)
	var offset_z := camera_height / tan(-pitch_rad)
	var target := _character.global_position + Vector3(0, camera_height, offset_z)
	_camera.global_position = _camera.global_position.lerp(target, CAMERA_SMOOTH * delta)


# ============================================
# Move Stick (Left Side)
# ============================================

func _create_move_stick(canvas: CanvasLayer) -> void:
	var base_size := STICK_RADIUS * 2

	_stick_base = Control.new()
	_stick_base.name = "MoveStickBase"
	_stick_base.custom_minimum_size = Vector2(base_size, base_size)
	_stick_base.size = Vector2(base_size, base_size)
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.visible = false
	canvas.add_child(_stick_base)

	var base_circle := _create_circle_control(STICK_RADIUS, Color(0.5, 0.5, 0.5, 0.3))
	base_circle.position = Vector2(STICK_RADIUS, STICK_RADIUS)
	base_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(base_circle)

	_stick_knob = _create_circle_control(STICK_KNOB_RADIUS, Color(0.8, 0.8, 0.8, 0.6))
	_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(_stick_knob)


# ============================================
# Aim Stick (Right Side)
# ============================================

func _create_aim_stick(canvas: CanvasLayer) -> void:
	var base_size := AIM_STICK_RADIUS * 2

	_aim_stick_base = Control.new()
	_aim_stick_base.name = "AimStickBase"
	_aim_stick_base.custom_minimum_size = Vector2(base_size, base_size)
	_aim_stick_base.size = Vector2(base_size, base_size)
	_aim_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_stick_base.visible = false
	canvas.add_child(_aim_stick_base)

	var base_circle := _create_circle_control(AIM_STICK_RADIUS, Color(0.5, 0.5, 0.5, 0.3))
	base_circle.position = Vector2(AIM_STICK_RADIUS, AIM_STICK_RADIUS)
	base_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_stick_base.add_child(base_circle)

	_aim_stick_knob = _create_circle_control(AIM_STICK_KNOB_RADIUS, Color(0.8, 0.8, 0.8, 0.6))
	_aim_stick_knob.position = Vector2(AIM_STICK_RADIUS, AIM_STICK_RADIUS)
	_aim_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_stick_base.add_child(_aim_stick_knob)


# ============================================
# Shared UI Helper
# ============================================

func _create_circle_control(radius: float, color: Color) -> Control:
	var ctrl := Control.new()
	ctrl.custom_minimum_size = Vector2(radius * 2, radius * 2)
	ctrl.size = Vector2(radius * 2, radius * 2)
	ctrl.pivot_offset = Vector2(radius, radius)
	ctrl.draw.connect(func():
		ctrl.draw_circle(Vector2.ZERO, radius, color)
	)
	return ctrl


# ============================================
# Touch Input (Mobile)
# ============================================

func _handle_touch_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var screen_half_x := _character.get_viewport().get_visible_rect().size.x * 0.5

		if touch.pressed:
			# 左半分 → 移動スティック（タッチ位置に出現）
			if _stick_touch_idx < 0 and touch.position.x < screen_half_x:
				_stick_touch_idx = touch.index
				_stick_center = touch.position
				_stick_base.position = touch.position - Vector2(STICK_RADIUS, STICK_RADIUS)
				_stick_base.visible = true
			# 右半分 → エイムスティック（タッチ位置に出現）
			elif _aim_stick_touch_idx < 0 and touch.position.x >= screen_half_x:
				_aim_stick_touch_idx = touch.index
				_aim_stick_center = touch.position
				_aim_stick_base.position = touch.position - Vector2(AIM_STICK_RADIUS, AIM_STICK_RADIUS)
				_aim_stick_base.visible = true
		else:
			if touch.index == _stick_touch_idx:
				_release_move_stick()
			if touch.index == _aim_stick_touch_idx:
				_release_aim_stick()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_touch_idx:
			_update_move_stick_position(drag.position)
		if drag.index == _aim_stick_touch_idx:
			_update_aim_stick_position(drag.position)

	# PC: 左クリック長押し → エイムスティック
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.device >= 0:
			if mb.pressed:
				if _aim_stick_touch_idx < 0 and _aim_stick_base:
					_aim_stick_touch_idx = 100
					_aim_stick_center = mb.position
					_aim_stick_base.position = mb.position - Vector2(AIM_STICK_RADIUS, AIM_STICK_RADIUS)
					_aim_stick_base.visible = true
			else:
				if _aim_stick_touch_idx == 100:
					_release_aim_stick()

	elif event is InputEventMouseMotion:
		if _aim_stick_touch_idx == 100:
			_update_aim_stick_position((event as InputEventMouseMotion).position)


# ============================================
# Move Stick Helpers
# ============================================

func _release_move_stick() -> void:
	_stick_touch_idx = -1
	_stick_input = Vector2.ZERO
	if _stick_knob:
		_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS)
	if _stick_base:
		_stick_base.visible = false


func _update_move_stick_position(touch_pos: Vector2) -> void:
	var offset := touch_pos - _stick_center
	if offset.length() > STICK_RADIUS:
		offset = offset.normalized() * STICK_RADIUS

	if _stick_knob:
		_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS) + offset

	var normalized := offset / STICK_RADIUS
	if normalized.length() < STICK_DEADZONE:
		_stick_input = Vector2.ZERO
	else:
		_stick_input = normalized


# ============================================
# Aim Stick Helpers
# ============================================

func _release_aim_stick() -> void:
	_aim_stick_touch_idx = -1
	_aim_stick_input = Vector2.ZERO
	if _aim_stick_knob:
		_aim_stick_knob.position = Vector2(AIM_STICK_RADIUS, AIM_STICK_RADIUS)
	if _aim_stick_base:
		_aim_stick_base.visible = false


func _update_aim_stick_position(touch_pos: Vector2) -> void:
	var offset := touch_pos - _aim_stick_center
	if offset.length() > AIM_STICK_RADIUS:
		offset = offset.normalized() * AIM_STICK_RADIUS

	if _aim_stick_knob:
		_aim_stick_knob.position = Vector2(AIM_STICK_RADIUS, AIM_STICK_RADIUS) + offset

	var normalized := offset / AIM_STICK_RADIUS
	if normalized.length() < STICK_DEADZONE:
		_aim_stick_input = Vector2.ZERO
	else:
		_aim_stick_input = normalized
