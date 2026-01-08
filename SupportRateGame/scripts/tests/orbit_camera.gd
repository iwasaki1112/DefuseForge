extends Camera3D
## Orbit camera that looks at a target and can be rotated/zoomed

@export var target: Node3D
@export var distance: float = 5.0
@export var min_distance: float = 2.0
@export var max_distance: float = 15.0
@export var rotation_speed: float = 0.5
@export var zoom_speed: float = 0.5
@export var pan_speed: float = 0.01
@export var vertical_angle_min: float = -80.0
@export var vertical_angle_max: float = 80.0

var _horizontal_angle: float = 0.0
var _vertical_angle: float = 30.0
var _is_rotating: bool = false  # 左クリックドラッグ
var _is_panning: bool = false   # 中クリックドラッグ
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _target_offset: Vector3 = Vector3.ZERO  # パン操作によるオフセット

# Multi-touch for pinch zoom
var _touch_points: Dictionary = {}  # touch_index -> position
var _initial_pinch_distance: float = 0.0
var _initial_zoom_distance: float = 0.0


func _ready() -> void:
	_update_camera_position()


func _input(event: InputEvent) -> void:
	# UIコントロール上の操作を無視
	if _is_mouse_over_ui():
		_is_rotating = false
		_is_panning = false
		return

	# Mouse button events
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_rotating = mb.pressed
			_last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = mb.pressed
			_last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - zoom_speed, min_distance, max_distance)
			_update_camera_position()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + zoom_speed, min_distance, max_distance)
			_update_camera_position()

	# Mac trackpad pinch gesture
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		# factor > 1 = zoom in, factor < 1 = zoom out
		var zoom_amount := (1.0 - mg.factor) * 5.0
		distance = clampf(distance + zoom_amount, min_distance, max_distance)
		_update_camera_position()

	# Mouse motion events
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _last_mouse_pos
		_last_mouse_pos = mm.position

		if _is_rotating:
			# 左クリックドラッグ: 回転
			_horizontal_angle -= delta.x * rotation_speed
			_vertical_angle -= delta.y * rotation_speed
			_vertical_angle = clampf(_vertical_angle, vertical_angle_min, vertical_angle_max)
			_update_camera_position()
		elif _is_panning:
			# 中クリックドラッグ: パン（上下左右移動）
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			_target_offset -= right * delta.x * pan_speed * distance
			_target_offset += up * delta.y * pan_speed * distance
			_update_camera_position()

	# Touch events for mobile
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_points[st.index] = st.position
			if _touch_points.size() == 2:
				# Start pinch
				var points = _touch_points.values()
				var p0 := points[0] as Vector2
				var p1 := points[1] as Vector2
				_initial_pinch_distance = p0.distance_to(p1)
				_initial_zoom_distance = distance
		else:
			_touch_points.erase(st.index)
			if _touch_points.size() == 1:
				# Reset single touch position
				_last_mouse_pos = _touch_points.values()[0]

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_points[sd.index] = sd.position

		if _touch_points.size() == 1:
			# Single finger drag - rotate camera
			var delta := sd.relative
			_horizontal_angle -= delta.x * rotation_speed
			_vertical_angle -= delta.y * rotation_speed
			_vertical_angle = clampf(_vertical_angle, vertical_angle_min, vertical_angle_max)
			_update_camera_position()
		elif _touch_points.size() == 2:
			# Two finger pinch - zoom
			var points = _touch_points.values()
			var p0 := points[0] as Vector2
			var p1 := points[1] as Vector2
			var current_pinch_distance := p0.distance_to(p1)
			if _initial_pinch_distance > 0:
				var pinch_ratio := _initial_pinch_distance / current_pinch_distance
				distance = clampf(_initial_zoom_distance * pinch_ratio, min_distance, max_distance)
				_update_camera_position()


func _is_mouse_over_ui() -> bool:
	## マウスがUI要素の上にあるかチェック
	var viewport := get_viewport()
	if not viewport:
		return false

	# フォーカスを持つGUIコントロールがあればUI操作中
	var gui_control := viewport.gui_get_focus_owner()
	if gui_control:
		return true

	# マウス位置がCanvasLayer内のコントロール上にあるかチェック
	var mouse_pos := viewport.get_mouse_position()
	var root := get_tree().current_scene
	if root:
		for child in root.get_children():
			if child is CanvasLayer:
				for ui_child in child.get_children():
					if ui_child is Control and ui_child.visible:
						if ui_child.get_global_rect().has_point(mouse_pos):
							return true
	return false


func _update_camera_position() -> void:
	if not target:
		return

	var h_rad := deg_to_rad(_horizontal_angle)
	var v_rad := deg_to_rad(_vertical_angle)

	var offset := Vector3(
		distance * cos(v_rad) * sin(h_rad),
		distance * sin(v_rad),
		distance * cos(v_rad) * cos(h_rad)
	)

	var look_target := target.global_position + _target_offset
	global_position = look_target + offset
	look_at(look_target, Vector3.UP)


func set_target(new_target: Node3D) -> void:
	target = new_target
	_target_offset = Vector3.ZERO  # ターゲット変更時はオフセットをリセット
	_update_camera_position()


func reset_pan() -> void:
	## パンオフセットをリセット
	_target_offset = Vector3.ZERO
	_update_camera_position()
