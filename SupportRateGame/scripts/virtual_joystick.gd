extends Control

## バーチャルジョイスティック
## 画面左側に表示され、タッチ/マウス操作でプレイヤーを移動させる

signal joystick_input(input_vector: Vector2)

@export var joystick_radius: float = 60.0
@export var handle_radius: float = 25.0
@export var dead_zone: float = 0.2

@onready var base: Control = $Base
@onready var handle: Control = $Base/Handle

var is_pressed: bool = false
var touch_index: int = -1
var input_vector: Vector2 = Vector2.ZERO
var is_mouse_pressed: bool = false


func _ready() -> void:
	# ジョイスティックのサイズを設定
	base.custom_minimum_size = Vector2(joystick_radius * 2, joystick_radius * 2)
	base.size = Vector2(joystick_radius * 2, joystick_radius * 2)
	handle.custom_minimum_size = Vector2(handle_radius * 2, handle_radius * 2)
	handle.size = Vector2(handle_radius * 2, handle_radius * 2)
	_reset_handle()


func _input(event: InputEvent) -> void:
	# タッチ入力（モバイル）
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	# マウス入力（PC テスト用）
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	# 画面左半分のみ反応
	if event.position.x > get_viewport().get_visible_rect().size.x * 0.5:
		return

	if event.pressed:
		if not is_pressed and _is_point_inside_base(event.position):
			is_pressed = true
			touch_index = event.index
			_update_handle(event.position)
	else:
		if event.index == touch_index:
			is_pressed = false
			touch_index = -1
			_reset_handle()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if is_pressed and event.index == touch_index:
		_update_handle(event.position)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	# 画面左半分のみ反応
	if event.position.x > get_viewport().get_visible_rect().size.x * 0.5:
		return

	if event.pressed:
		if not is_mouse_pressed and _is_point_inside_base(event.position):
			is_mouse_pressed = true
			is_pressed = true
			_update_handle(event.position)
	else:
		if is_mouse_pressed:
			is_mouse_pressed = false
			is_pressed = false
			_reset_handle()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_mouse_pressed:
		_update_handle(event.position)


func _is_point_inside_base(point: Vector2) -> bool:
	var base_center := base.global_position + base.size / 2
	var distance := point.distance_to(base_center)
	# ジョイスティックの範囲を少し広めに取る
	return distance <= joystick_radius * 1.5


func _update_handle(touch_position: Vector2) -> void:
	var base_center := base.global_position + base.size / 2
	var direction := touch_position - base_center
	var distance := direction.length()

	# ジョイスティックの範囲内に制限
	if distance > joystick_radius:
		direction = direction.normalized() * joystick_radius

	# ハンドルの位置を更新
	handle.position = base.size / 2 + direction - handle.size / 2

	# 入力ベクトルを計算（-1 〜 1）
	input_vector = direction / joystick_radius

	# デッドゾーンを適用
	if input_vector.length() < dead_zone:
		input_vector = Vector2.ZERO

	joystick_input.emit(input_vector)


func _reset_handle() -> void:
	# ハンドルを中央に戻す
	handle.position = base.size / 2 - handle.size / 2
	input_vector = Vector2.ZERO
	joystick_input.emit(input_vector)


func get_input() -> Vector2:
	return input_vector
