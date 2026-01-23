class_name VisionComponent
extends Node3D

## Vision Component for Fog of War System (Simplified Raycast Method)
## Uses equal-interval raycasting without wall corner caching
## Ensures immediate response to dynamic obstacles (doors, etc.)

signal vision_updated(visible_points: PackedVector3Array)

# ============================================
# Quality Presets (synced with FogOfWarSystem.Quality)
# ============================================
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_PRESETS := {
	Quality.LOW: { "ray_count": 36, "update_hz": 15 },     # Mobile
	Quality.MEDIUM: { "ray_count": 54, "update_hz": 20 }, # Balanced
	Quality.HIGH: { "ray_count": 72, "update_hz": 30 },   # PC
}

# ============================================
# Export Settings
# ============================================
@export_group("Vision Settings")
@export var fov_degrees: float = 90.0  ## Field of view in degrees
@export var view_distance: float = 15.0  ## Vision distance in meters
@export var ray_count: int = 36  ## Number of rays across FOV (equal interval)
@export var eye_height: float = 1.5  ## Eye height from ground

@export_group("Collision Settings")
@export_flags_3d_physics var wall_collision_mask: int = 2  ## Collision mask for walls

# ============================================
# State
# ============================================
var _enabled: bool = true
var _visible_polygon: PackedVector3Array = PackedVector3Array()
var _update_interval: float = 0.067  # ~15Hz default
var _time_since_update: float = 0.0

# Temporal smoothing (prevents jitter)
var _smoothed_eye_position: Vector3 = Vector3.ZERO
var _smoothed_angle: float = 0.0
var _smoothed_initialized: bool = false

const EYE_POSITION_SMOOTHING: float = 0.3  # Position smoothing factor
const ANGLE_SMOOTHING: float = 0.3  # Angle smoothing factor

# Stationary optimization
var _last_position: Vector3 = Vector3.ZERO
var _last_angle: float = 0.0
var _stationary_frames: int = 0
const STATIONARY_THRESHOLD: int = 3
const STATIONARY_UPDATE_MULTIPLIER: float = 3.0  # Update slower when stationary

# ============================================
# References
# ============================================
var _character: Node3D = null
var _character_rid: RID  # Cached RID for raycast exclusion


# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_character = get_parent()
	# Cache RID for raycast exclusion
	if _character is CollisionObject3D:
		_character_rid = _character.get_rid()


func _physics_process(delta: float) -> void:
	if not _enabled:
		return

	# Use longer interval when stationary
	var current_interval := _update_interval
	if _stationary_frames >= STATIONARY_THRESHOLD:
		current_interval *= STATIONARY_UPDATE_MULTIPLIER

	_time_since_update += delta
	if _time_since_update >= current_interval:
		_time_since_update = 0.0
		_calculate_vision()


# ============================================
# Public API
# ============================================

## Get the visible polygon (used by FogOfWarSystem)
func get_visible_polygon() -> PackedVector3Array:
	return _visible_polygon


## Force immediate vision update
func force_update() -> void:
	_calculate_vision()


## Set quality preset
func set_quality(q: Quality) -> void:
	var preset: Dictionary = QUALITY_PRESETS[q]
	ray_count = preset["ray_count"]
	_update_interval = 1.0 / float(preset["update_hz"])


## Apply quality settings from dictionary (for FogOfWarSystem sync)
func apply_quality_settings(settings: Dictionary) -> void:
	if settings.has("ray_count"):
		ray_count = settings["ray_count"]
	if settings.has("update_hz"):
		_update_interval = 1.0 / float(settings["update_hz"])


## Set field of view
func set_fov(degrees: float) -> void:
	fov_degrees = clamp(degrees, 1.0, 360.0)


## Set view distance
func set_view_distance(distance: float) -> void:
	view_distance = max(1.0, distance)


## Disable vision (for death, etc.)
func disable() -> void:
	_enabled = false
	_visible_polygon = PackedVector3Array()
	_smoothed_initialized = false
	vision_updated.emit(_visible_polygon)


## Enable vision
func enable() -> void:
	_enabled = true
	_calculate_vision()


## Check if vision is enabled
func is_enabled() -> bool:
	return _enabled


## Check if a world position is within FOV (lightweight single raycast check)
## Used for enemy visibility detection without full polygon calculation
func is_position_in_view(world_pos: Vector3) -> bool:
	if not _character:
		return false

	var origin := _get_eye_position_raw()  # Use raw position for accuracy
	var to_target := world_pos - origin
	var distance := to_target.length()

	# Distance check
	if distance > view_distance:
		return false

	# FOV check (XZ plane)
	var look_dir := _get_look_direction()
	var to_target_xz := Vector3(to_target.x, 0, to_target.z).normalized()
	var look_dir_xz := Vector3(look_dir.x, 0, look_dir.z).normalized()

	if to_target_xz.length_squared() < 0.001 or look_dir_xz.length_squared() < 0.001:
		return true  # Target directly above/below or vertical look direction

	var angle := rad_to_deg(look_dir_xz.angle_to(to_target_xz))
	if angle > fov_degrees / 2.0:
		return false

	# Wall occlusion check (single raycast)
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return false

	var query := PhysicsRayQueryParameters3D.create(origin, world_pos, wall_collision_mask)
	if _character_rid.is_valid():
		query.exclude = [_character_rid]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


# ============================================
# Vision Calculation (Equal Interval Raycast)
# ============================================

func _calculate_vision() -> void:
	if not _character:
		return

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return

	# Get smoothed position and angle
	var origin := _get_eye_position()
	var char_rotation := _get_look_angle()

	# Check if position/angle changed significantly
	var pos_changed := origin.distance_to(_last_position) >= 0.05
	var angle_changed := absf(char_rotation - _last_angle) > 0.01

	if not pos_changed and not angle_changed:
		_stationary_frames += 1
		return
	else:
		_stationary_frames = 0

	_last_position = origin
	_last_angle = char_rotation

	var half_fov := deg_to_rad(fov_degrees / 2.0)
	var fov_min := char_rotation - half_fov
	var fov_max := char_rotation + half_fov

	# Cast rays at equal intervals across FOV
	_visible_polygon.clear()
	_visible_polygon.append(origin)  # First point is origin

	for i in range(ray_count + 1):
		var t := float(i) / float(ray_count)
		var angle := fov_min + t * (fov_max - fov_min)

		var direction := Vector3(sin(angle), 0, -cos(angle))
		var end_point := origin + direction * view_distance

		var query := PhysicsRayQueryParameters3D.create(origin, end_point, wall_collision_mask)
		if _character_rid.is_valid():
			query.exclude = [_character_rid]

		var result := space_state.intersect_ray(query)

		if result:
			_visible_polygon.append(result.position)
		else:
			_visible_polygon.append(end_point)

	vision_updated.emit(_visible_polygon)


# ============================================
# Position and Direction Helpers
# ============================================

## Get raw eye position (no smoothing, for is_position_in_view)
func _get_eye_position_raw() -> Vector3:
	if not _character:
		return global_position
	var pos := _character.global_position
	pos.y += eye_height
	return pos


## Get smoothed eye position (for vision calculation)
func _get_eye_position() -> Vector3:
	if not _character:
		return global_position

	var target_pos := _character.global_position
	target_pos.y += eye_height

	# Temporal smoothing to prevent jitter
	if not _smoothed_initialized:
		_smoothed_eye_position = target_pos
	else:
		_smoothed_eye_position = _smoothed_eye_position.lerp(target_pos, EYE_POSITION_SMOOTHING)

	return _smoothed_eye_position


## Get smoothed look angle
func _get_look_angle() -> float:
	var direction := _get_look_direction()
	var target_angle := atan2(direction.x, -direction.z)

	# Temporal smoothing for angle
	if not _smoothed_initialized:
		_smoothed_angle = target_angle
		_smoothed_initialized = true
	else:
		# Normalize angle difference to -PI ~ PI before interpolation
		var angle_diff := _wrap_angle(target_angle - _smoothed_angle)
		_smoothed_angle = _wrap_angle(_smoothed_angle + angle_diff * ANGLE_SMOOTHING)

	return _smoothed_angle


## Get look direction from character
func _get_look_direction() -> Vector3:
	if not _character:
		return Vector3.FORWARD

	# Use GameCharacter's facing direction (single source of truth)
	if _character.has_method("get_facing_direction"):
		var dir: Vector3 = _character.get_facing_direction()
		if dir.length_squared() > 0.001:
			return dir.normalized()

	# Fallback: character's forward direction
	var forward := _character.global_transform.basis.z
	forward.y = 0

	if forward.length_squared() < 0.001:
		return Vector3.FORWARD

	return forward.normalized()


## Wrap angle to -PI to PI range
func _wrap_angle(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle
