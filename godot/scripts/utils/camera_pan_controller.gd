class_name CameraPanController
extends RefCounted
## 右ドラッグでカメラを平行移動する簡易コントローラー

var camera: Camera3D = null
var pan_speed: float = 0.05
var _drag_active: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_start_pos: Vector3 = Vector3.ZERO


func setup(target_camera: Camera3D, speed: float = 0.05) -> void:
	camera = target_camera
	pan_speed = speed


## 入力処理。処理した場合はtrueを返す
func handle_input(event: InputEvent) -> bool:
	if not camera:
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_drag_active = true
			_drag_start = event.position
			_camera_start_pos = camera.global_position
		else:
			_drag_active = false
		return true

	if event is InputEventMouseMotion and _drag_active:
		var delta = event.position - _drag_start
		var move_x = -delta.x * pan_speed
		var move_z = -delta.y * pan_speed
		camera.global_position = _camera_start_pos + Vector3(move_x, 0, move_z)
		return true

	return false
