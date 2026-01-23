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

@export_group("Debug")
@export var debug_draw: bool = false  ## Enable debug visualization
@export var debug_color: Color = Color(0.2, 0.8, 0.2, 0.3)  ## Vision cone fill color
@export var debug_line_color: Color = Color(0.2, 1.0, 0.2, 0.8)  ## Vision boundary line color
@export var debug_hit_color: Color = Color(1.0, 0.3, 0.3, 1.0)  ## Raycast hit point color

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

# Force update flag (bypass change check)
var _force_next_update: bool = true  # true for first calculation

# ============================================
# References
# ============================================
var _character: Node3D = null
var _character_rid: RID  # Cached RID for raycast exclusion

# ============================================
# Debug Drawing
# ============================================
var _debug_mesh_instance: MeshInstance3D = null
var _debug_immediate_mesh: ImmediateMesh = null
var _debug_material: StandardMaterial3D = null
var _debug_line_material: StandardMaterial3D = null


# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_character = get_parent()
	# Cache RID for raycast exclusion
	if _character is CollisionObject3D:
		_character_rid = _character.get_rid()

	# Setup debug drawing if enabled
	if debug_draw:
		_setup_debug_drawing()


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
	_clear_debug_drawing()


## Enable vision
func enable() -> void:
	_enabled = true
	_calculate_vision()


## Check if vision is enabled
func is_enabled() -> bool:
	return _enabled


## Enable/disable debug drawing at runtime
func set_debug_draw(enabled: bool) -> void:
	debug_draw = enabled
	if enabled:
		# デバッグ表示時はVisionComponentを強制有効化（視界計算が必要）
		_enabled = true
		_force_next_update = true  # 強制的に初回計算を実行
		_calculate_vision()
		_setup_debug_drawing()
		_update_debug_drawing()
	else:
		_clear_debug_drawing()
		# デバッグ表示OFFで、デバッグメッシュも削除
		if _debug_mesh_instance and is_instance_valid(_debug_mesh_instance):
			_debug_mesh_instance.queue_free()
			_debug_mesh_instance = null
			_debug_immediate_mesh = null


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

	# Check if position/angle changed significantly (skip if forced)
	if not _force_next_update:
		var pos_changed := origin.distance_to(_last_position) >= 0.05
		var angle_changed := absf(char_rotation - _last_angle) > 0.01

		if not pos_changed and not angle_changed:
			_stationary_frames += 1
			return
		else:
			_stationary_frames = 0
	else:
		_force_next_update = false
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

	# Update debug visualization
	if debug_draw:
		_update_debug_drawing()


# ============================================
# Debug Drawing
# ============================================

func _setup_debug_drawing() -> void:
	if _debug_mesh_instance:
		return  # Already setup

	# Create ImmediateMesh for drawing
	_debug_immediate_mesh = ImmediateMesh.new()

	# Create MeshInstance3D
	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.mesh = _debug_immediate_mesh
	_debug_mesh_instance.name = "VisionDebugMesh"
	_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Create fill material (semi-transparent)
	_debug_material = StandardMaterial3D.new()
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_material.albedo_color = debug_color

	# Create line material
	_debug_line_material = StandardMaterial3D.new()
	_debug_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_line_material.albedo_color = debug_line_color

	# Add to scene (at root level for world-space drawing)
	get_tree().root.add_child.call_deferred(_debug_mesh_instance)


func _clear_debug_drawing() -> void:
	if _debug_immediate_mesh:
		_debug_immediate_mesh.clear_surfaces()


func _update_debug_drawing() -> void:
	if not _debug_immediate_mesh or not _debug_mesh_instance:
		_setup_debug_drawing()
		return

	if _visible_polygon.size() < 3:
		_debug_immediate_mesh.clear_surfaces()
		return

	_debug_immediate_mesh.clear_surfaces()

	var origin := _visible_polygon[0]
	var draw_height := origin.y + 0.05  # Slightly above ground to avoid z-fighting

	# Update material colors in case they changed
	_debug_material.albedo_color = debug_color
	_debug_line_material.albedo_color = debug_line_color

	# Draw filled vision cone (triangles from origin to each edge)
	_debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _debug_material)
	for i in range(1, _visible_polygon.size() - 1):
		var p1 := _visible_polygon[i]
		var p2 := _visible_polygon[i + 1]

		# Triangle: origin -> p1 -> p2
		_debug_immediate_mesh.surface_add_vertex(Vector3(origin.x, draw_height, origin.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(p1.x, draw_height, p1.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(p2.x, draw_height, p2.z))
	_debug_immediate_mesh.surface_end()

	# Draw vision boundary lines
	_debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_line_material)

	# FOV boundary edges (first and last rays)
	if _visible_polygon.size() >= 2:
		var first_point := _visible_polygon[1]
		var last_point := _visible_polygon[_visible_polygon.size() - 1]

		# Left edge
		_debug_immediate_mesh.surface_add_vertex(Vector3(origin.x, draw_height, origin.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(first_point.x, draw_height, first_point.z))

		# Right edge
		_debug_immediate_mesh.surface_add_vertex(Vector3(origin.x, draw_height, origin.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(last_point.x, draw_height, last_point.z))

	# Outer arc (connecting all hit points)
	for i in range(1, _visible_polygon.size() - 1):
		var p1 := _visible_polygon[i]
		var p2 := _visible_polygon[i + 1]
		_debug_immediate_mesh.surface_add_vertex(Vector3(p1.x, draw_height, p1.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(p2.x, draw_height, p2.z))

	_debug_immediate_mesh.surface_end()

	# Draw hit points (small crosses at wall intersections)
	var hit_material := StandardMaterial3D.new()
	hit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_material.albedo_color = debug_hit_color

	_debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, hit_material)
	var cross_size := 0.1
	for i in range(1, _visible_polygon.size()):
		var p := _visible_polygon[i]
		var dist := p.distance_to(origin)
		# Only draw hit markers for points that hit walls (not at max distance)
		if dist < view_distance - 0.1:
			# Small cross at hit point
			_debug_immediate_mesh.surface_add_vertex(Vector3(p.x - cross_size, draw_height, p.z))
			_debug_immediate_mesh.surface_add_vertex(Vector3(p.x + cross_size, draw_height, p.z))
			_debug_immediate_mesh.surface_add_vertex(Vector3(p.x, draw_height, p.z - cross_size))
			_debug_immediate_mesh.surface_add_vertex(Vector3(p.x, draw_height, p.z + cross_size))
	_debug_immediate_mesh.surface_end()


func _exit_tree() -> void:
	# Clean up debug mesh when removed from scene
	if _debug_mesh_instance and is_instance_valid(_debug_mesh_instance):
		_debug_mesh_instance.queue_free()
		_debug_mesh_instance = null


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
