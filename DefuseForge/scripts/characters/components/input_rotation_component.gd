class_name InputRotationComponent
extends Node

## Mouse-based character rotation component
## Click near a character and drag to rotate them to face the mouse position

signal rotation_started()
signal rotation_ended()

## Proximity check radius for click detection
@export var click_radius: float = 1.5
## Collision mask for character detection (Layer 1 = characters)
@export_flags_3d_physics var character_collision_mask: int = 1
## Ground plane height for mouse intersection calculation
@export var ground_plane_height: float = 0.0
## Hold duration before rotation starts (seconds)
@export var hold_duration: float = 0.2

var _character: CharacterBody3D
var _camera: Camera3D
var _is_rotating: bool = false
var _is_holding: bool = false
var _hold_timer: float = 0.0
var _hold_mouse_pos: Vector2
var _ground_plane: Plane


func _ready() -> void:
	_character = get_parent() as CharacterBody3D
	if _character == null:
		push_error("[InputRotationComponent] Parent must be CharacterBody3D")
	_ground_plane = Plane(Vector3.UP, ground_plane_height)


## Setup camera reference for mouse raycasting
func setup(camera: Camera3D) -> void:
	_camera = camera


func _process(delta: float) -> void:
	if _is_holding and not _is_rotating:
		_hold_timer += delta
		if _hold_timer >= hold_duration:
			_is_rotating = true
			rotation_started.emit()
			_rotate_character_to_mouse(_hold_mouse_pos)


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or _character == null:
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if _is_clicking_on_character(mouse_event.position):
					_is_holding = true
					_hold_timer = 0.0
					_hold_mouse_pos = mouse_event.position
			else:
				_is_holding = false
				_hold_timer = 0.0
				if _is_rotating:
					_is_rotating = false
					rotation_ended.emit()

	if event is InputEventMouseMotion:
		if _is_holding:
			_hold_mouse_pos = event.position
		if _is_rotating:
			_rotate_character_to_mouse(event.position)


func _is_clicking_on_character(mouse_pos: Vector2) -> bool:
	var ray_origin = _camera.project_ray_origin(mouse_pos)
	var ray_direction = _camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_direction * 100.0

	# Raycast to check direct character hit
	var space_state = _character.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = character_collision_mask
	var result = space_state.intersect_ray(query)

	if result and result.collider == _character:
		return true

	# Proximity fallback - allow clicks near character
	var intersection = _ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		var click_pos = intersection as Vector3
		var char_pos = _character.global_position
		if click_pos.distance_to(char_pos) < click_radius:
			return true

	return false


func _rotate_character_to_mouse(mouse_pos: Vector2) -> void:
	var ray_origin = _camera.project_ray_origin(mouse_pos)
	var ray_direction = _camera.project_ray_normal(mouse_pos)

	var intersection = _ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection == null:
		return

	var char_pos = _character.global_position
	var target_pos = intersection as Vector3
	var direction = target_pos - char_pos
	direction.y = 0  # Horizontal only

	if direction.length_squared() < 0.01:
		return

	var target_angle = atan2(direction.x, direction.z)
	_character.rotation.y = target_angle


## Check if currently in rotation mode
func is_rotating() -> bool:
	return _is_rotating
