extends Camera3D
## オービットカメラ
## マウスドラッグでターゲットを中心に回転、ホイールでズーム

@export var target: Vector3 = Vector3.ZERO
@export var mouse_sensitivity: float = 0.005
@export var zoom_speed: float = 0.5
@export var min_distance: float = 2.0
@export var max_distance: float = 20.0

var _distance: float = 5.0
var _yaw: float = 0.0
var _pitch: float = 0.5
var _is_dragging: bool = false


func _ready() -> void:
	_distance = global_position.distance_to(target)
	_update_camera()


func _input(event: InputEvent) -> void:
	# 左クリックドラッグで回転
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed

	if event is InputEventMouseMotion and _is_dragging:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, 0.1, PI * 0.45)
		_update_camera()

	# ホイールでズーム
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = max(min_distance, _distance - zoom_speed)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = min(max_distance, _distance + zoom_speed)
			_update_camera()


func _update_camera() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * _distance

	global_position = target + offset
	look_at(target)
