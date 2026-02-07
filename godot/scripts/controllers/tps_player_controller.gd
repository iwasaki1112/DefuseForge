class_name TPSPlayerController
extends Node
## TPS操作コントローラー
##
## GameScreenで使用する再利用可能なTPSプレイヤー制御。
## WASD + バーチャルジョイスティック移動、マウスエイム、カメラフォロー、
## CombatAwareness連携を提供する。
##
## 使用方法:
##   var ctrl = TPSPlayerController.new()
##   add_child(ctrl)
##   ctrl.setup(character, camera, ui_layer)
##
## _physics_process内でctrl.process(delta)を呼び出し、
## _input内でctrl.handle_input(event)を呼び出す。

# ============================================
# Constants
# ============================================
const CAMERA_HEIGHT := 14.0
const CAMERA_PITCH_DEG := -50.0
const CAMERA_FOV := 30.0
const CAMERA_SMOOTH := 8.0
const GROUND_Y := 0.0

# Joystick
const STICK_RADIUS := 80.0
const STICK_KNOB_RADIUS := 30.0
const STICK_DEADZONE := 0.15

# ============================================
# References
# ============================================
var _character: GameCharacter = null
var _camera: Camera3D = null
var _ui_layer: CanvasLayer = null

# Joystick state
var _stick_base: Control = null
var _stick_knob: Control = null
var _stick_touch_idx: int = -1
var _stick_mouse_active: bool = false
var _stick_input: Vector2 = Vector2.ZERO
var _stick_center: Vector2 = Vector2.ZERO

# Movement direction cache (for mobile facing)
var _last_move_dir: Vector3 = Vector3.ZERO


# ============================================
# Public API
# ============================================

## コントローラーを初期化する
func setup(character: GameCharacter, cam: Camera3D, canvas: CanvasLayer) -> void:
	_character = character
	_camera = cam
	_ui_layer = canvas

	# カメラをTPS用に設定
	if _camera:
		_camera.fov = CAMERA_FOV
		_camera.rotation_degrees.x = CAMERA_PITCH_DEG
		# 初期位置をキャラクター上に設定
		if _character:
			var pitch_rad := deg_to_rad(CAMERA_PITCH_DEG)
			var offset_z := CAMERA_HEIGHT / tan(-pitch_rad)
			_camera.global_position = _character.global_position + Vector3(0, CAMERA_HEIGHT, offset_z)

	# ジョイスティックUI作成
	if _ui_layer:
		_create_joystick(_ui_layer)


## 毎フレーム処理（_physics_processから呼ぶ）
func process(delta: float) -> void:
	if not _character or not _character.is_alive:
		return

	_handle_movement(delta)
	_handle_aim(delta)
	if _character.combat_awareness:
		_character.combat_awareness.process(delta)
	_update_camera(delta)


## 入力処理（_inputから呼ぶ）
func handle_input(event: InputEvent) -> void:
	_handle_stick_input(event)


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

	# Combine with joystick
	input_dir.x += _stick_input.x
	input_dir.y += _stick_input.y

	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var move_dir := Vector3.ZERO
	if input_dir.length() > 0.01:
		input_dir = input_dir.normalized()
		move_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()

	_last_move_dir = move_dir

	var speed := _character.anim_ctrl.get_current_speed() if _character.anim_ctrl else 2.0
	_character.velocity = move_dir * speed
	_character.move_and_slide()

	if _character.anim_ctrl:
		var aim_dir := _character.get_facing_direction()
		_character.anim_ctrl.update_animation(move_dir, aim_dir, false, delta)


# ============================================
# Aim
# ============================================

func _handle_aim(_delta: float) -> void:
	# 1. CombatAwareness override — 敵検知時は自動で敵方向を向く
	if _character.combat_awareness:
		var override_dir := _character.combat_awareness.get_override_look_direction()
		if override_dir != Vector3.ZERO:
			_character.set_facing_direction_vec(override_dir)
			return

	# 2. PC: マウスエイム（ジョイスティック非アクティブ時のみ）
	if _camera and _stick_input.length() <= 0.01:
		var viewport := _character.get_viewport()
		if viewport:
			var mouse_pos := viewport.get_mouse_position()
			var ray_origin := _camera.project_ray_origin(mouse_pos)
			var ray_normal := _camera.project_ray_normal(mouse_pos)

			if absf(ray_normal.y) > 0.001:
				var t := (GROUND_Y - ray_origin.y) / ray_normal.y
				if t > 0:
					var ground_point := ray_origin + ray_normal * t
					var aim_dir := ground_point - _character.global_position
					aim_dir.y = 0
					if aim_dir.length_squared() > 0.01:
						_character.set_facing_direction_vec(aim_dir.normalized())
					return

	# 3. モバイル: 移動方向 = 向き
	if _last_move_dir.length_squared() > 0.01:
		_character.set_facing_direction_vec(_last_move_dir)


# ============================================
# Camera
# ============================================

func _update_camera(delta: float) -> void:
	if not _character or not _camera:
		return
	var pitch_rad := deg_to_rad(CAMERA_PITCH_DEG)
	var offset_z := CAMERA_HEIGHT / tan(-pitch_rad)
	var target := _character.global_position + Vector3(0, CAMERA_HEIGHT, offset_z)
	_camera.global_position = _camera.global_position.lerp(target, CAMERA_SMOOTH * delta)


# ============================================
# Joystick
# ============================================

func _create_joystick(canvas: CanvasLayer) -> void:
	var margin := 40.0
	var base_size := STICK_RADIUS * 2

	_stick_base = Control.new()
	_stick_base.name = "StickBase"
	_stick_base.custom_minimum_size = Vector2(base_size, base_size)
	_stick_base.size = Vector2(base_size, base_size)
	_stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.position = Vector2(margin, -margin - base_size)
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_stick_base)

	var base_draw := ColorRect.new()
	base_draw.name = "BaseBG"
	base_draw.size = Vector2(base_size, base_size)
	base_draw.color = Color(1, 1, 1, 0.0)
	base_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(base_draw)

	var base_circle := _create_circle_control(STICK_RADIUS, Color(0.5, 0.5, 0.5, 0.3))
	base_circle.position = Vector2(STICK_RADIUS, STICK_RADIUS)
	base_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(base_circle)

	_stick_knob = _create_circle_control(STICK_KNOB_RADIUS, Color(0.8, 0.8, 0.8, 0.6))
	_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(_stick_knob)

	_stick_center = _stick_base.global_position + Vector2(STICK_RADIUS, STICK_RADIUS)


func _create_circle_control(radius: float, color: Color) -> Control:
	var ctrl := Control.new()
	ctrl.custom_minimum_size = Vector2(radius * 2, radius * 2)
	ctrl.size = Vector2(radius * 2, radius * 2)
	ctrl.pivot_offset = Vector2(radius, radius)
	ctrl.draw.connect(func():
		ctrl.draw_circle(Vector2.ZERO, radius, color)
	)
	return ctrl


func _is_in_stick_area(pos: Vector2) -> bool:
	_stick_center = _stick_base.global_position + Vector2(STICK_RADIUS, STICK_RADIUS)
	return pos.distance_to(_stick_center) <= STICK_RADIUS * 1.5


func _handle_stick_input(event: InputEvent) -> void:
	if not _stick_base:
		return

	# Touch input (mobile)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _stick_touch_idx < 0 and touch.position.x < _character.get_viewport().get_visible_rect().size.x * 0.5:
				_stick_touch_idx = touch.index
				_stick_center = _stick_base.global_position + Vector2(STICK_RADIUS, STICK_RADIUS)
				_update_stick_position(touch.position)
		else:
			if touch.index == _stick_touch_idx:
				_release_stick()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_touch_idx:
			_update_stick_position(drag.position)

	# Mouse input (PC)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _is_in_stick_area(mb.position):
				_stick_mouse_active = true
				_update_stick_position(mb.position)
			elif not mb.pressed and _stick_mouse_active:
				_stick_mouse_active = false
				_release_stick()

	elif event is InputEventMouseMotion:
		if _stick_mouse_active:
			_update_stick_position(event.position)


func _release_stick() -> void:
	_stick_touch_idx = -1
	_stick_input = Vector2.ZERO
	if _stick_knob:
		_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS)


func _update_stick_position(touch_pos: Vector2) -> void:
	var offset := touch_pos - _stick_center
	var dist := offset.length()

	if dist > STICK_RADIUS:
		offset = offset.normalized() * STICK_RADIUS

	if _stick_knob:
		_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS) + offset

	var normalized := offset / STICK_RADIUS
	if normalized.length() < STICK_DEADZONE:
		_stick_input = Vector2.ZERO
	else:
		_stick_input = normalized
