class_name VisionComponent
extends Node3D

## Vision Component for Fog of War System (Light2D方式用の簡素化版)
## ポリゴン生成は廃止し、is_position_in_view()による可視判定のみを提供
## デバッグ表示用のレイキャスト計算は維持

signal vision_updated(visible_points: PackedVector3Array)

# ============================================
# Export Settings
# ============================================
@export_group("Vision Settings")
@export var fov_degrees: float = 90.0  ## Field of view in degrees
@export var view_distance: float = 15.0  ## Vision distance in meters
@export var peripheral_distance: float = 0.8  ## Peripheral vision distance (360 degrees)
@export var eye_height: float = 1.5  ## Eye height from ground

@export_group("Collision Settings")
@export_flags_3d_physics var wall_collision_mask: int = 2  ## Collision mask for walls

@export_group("Debug")
@export var debug_draw: bool = false  ## Enable debug visualization
@export var debug_color: Color = Color(0.2, 0.8, 0.2, 0.3)  ## Vision cone fill color
@export var debug_line_color: Color = Color(0.2, 1.0, 0.2, 0.8)  ## Vision boundary line color
@export var debug_hit_color: Color = Color(1.0, 0.3, 0.3, 1.0)  ## Raycast hit point color

# デバッグ表示用のレイ数
const DEBUG_RAY_COUNT: int = 36

# ============================================
# State
# ============================================
var _enabled: bool = true
var _visible_polygon: PackedVector3Array = PackedVector3Array()

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

# SmokeAreaManager cache (avoid repeated group lookups)
var _smoke_area_manager_cache: SmokeAreaManager = null
var _smoke_area_manager_checked: bool = false


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


func _physics_process(_delta: float) -> void:
	if not _enabled:
		return

	# デバッグ表示が有効な場合のみポリゴン計算
	if debug_draw:
		_calculate_debug_vision()


# ============================================
# Public API
# ============================================

## Get the visible polygon (デバッグ表示用)
func get_visible_polygon() -> PackedVector3Array:
	return _visible_polygon


## Force immediate vision update
func force_update() -> void:
	if debug_draw:
		_calculate_debug_vision()


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
	vision_updated.emit(_visible_polygon)
	_clear_debug_drawing()


## Enable vision
func enable() -> void:
	_enabled = true


## Check if vision is enabled
func is_enabled() -> bool:
	return _enabled


## Enable/disable debug drawing at runtime
func set_debug_draw(enabled: bool) -> void:
	debug_draw = enabled
	if enabled:
		_enabled = true
		_calculate_debug_vision()
		_setup_debug_drawing()
		_update_debug_drawing()
	else:
		_clear_debug_drawing()
		if _debug_mesh_instance and is_instance_valid(_debug_mesh_instance):
			_debug_mesh_instance.queue_free()
			_debug_mesh_instance = null
			_debug_immediate_mesh = null


## Check if a world position is within FOV (lightweight single raycast check)
## Used for enemy visibility detection
## Includes peripheral vision check (360 degrees within peripheral_distance)
func is_position_in_view(world_pos: Vector3) -> bool:
	if not _character:
		return false

	var origin := _get_eye_position_raw()
	var to_target := world_pos - origin
	var distance := to_target.length()

	# Peripheral vision check (360 degrees, short range)
	# If within peripheral distance, skip FOV angle check
	var is_in_peripheral := distance <= peripheral_distance

	# Distance check (only applies to main FOV, not peripheral)
	if not is_in_peripheral and distance > view_distance:
		return false

	# FOV check (XZ plane) - skip for peripheral vision
	if not is_in_peripheral:
		var look_dir := _get_look_direction()
		var to_target_xz := Vector3(to_target.x, 0, to_target.z).normalized()
		var look_dir_xz := Vector3(look_dir.x, 0, look_dir.z).normalized()

		if to_target_xz.length_squared() < 0.001 or look_dir_xz.length_squared() < 0.001:
			pass  # Target directly above/below or vertical look direction - allow
		else:
			var angle := rad_to_deg(look_dir_xz.angle_to(to_target_xz))
			if angle > fov_degrees / 2.0:
				return false

	# Smoke occlusion check
	var smoke_manager := _get_smoke_area_manager()
	if smoke_manager and smoke_manager.is_line_of_sight_blocked(origin, world_pos):
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


## SmokeAreaManagerを取得（キャッシュ版）
func _get_smoke_area_manager() -> SmokeAreaManager:
	# 既にチェック済みならキャッシュを返す
	if _smoke_area_manager_checked:
		return _smoke_area_manager_cache

	_smoke_area_manager_checked = true
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	if game_screen and game_screen.has_method("get_smoke_area_manager"):
		_smoke_area_manager_cache = game_screen.get_smoke_area_manager()
	return _smoke_area_manager_cache


# ============================================
# Debug Vision Calculation (デバッグ表示用)
# ============================================

func _calculate_debug_vision() -> void:
	if not _character:
		return

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return

	var origin := _get_eye_position_raw()
	var char_rotation := _get_look_angle()

	var half_fov := deg_to_rad(fov_degrees / 2.0)
	var fov_min := char_rotation - half_fov
	var fov_max := char_rotation + half_fov

	# Cast rays at equal intervals across FOV
	_visible_polygon.clear()
	_visible_polygon.append(origin)

	for i in range(DEBUG_RAY_COUNT + 1):
		var t := float(i) / float(DEBUG_RAY_COUNT)
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

	if debug_draw:
		_update_debug_drawing()


# ============================================
# Debug Drawing
# ============================================

func _setup_debug_drawing() -> void:
	if _debug_mesh_instance:
		return

	_debug_immediate_mesh = ImmediateMesh.new()

	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.mesh = _debug_immediate_mesh
	_debug_mesh_instance.name = "VisionDebugMesh"
	_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_debug_material = StandardMaterial3D.new()
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_material.albedo_color = debug_color

	_debug_line_material = StandardMaterial3D.new()
	_debug_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_line_material.albedo_color = debug_line_color

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
	var draw_height := origin.y + 0.05

	_debug_material.albedo_color = debug_color
	_debug_line_material.albedo_color = debug_line_color

	# Draw filled vision cone
	_debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _debug_material)
	for i in range(1, _visible_polygon.size() - 1):
		var p1 := _visible_polygon[i]
		var p2 := _visible_polygon[i + 1]
		_debug_immediate_mesh.surface_add_vertex(Vector3(origin.x, draw_height, origin.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(p1.x, draw_height, p1.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(p2.x, draw_height, p2.z))
	_debug_immediate_mesh.surface_end()

	# Draw vision boundary lines
	if _visible_polygon.size() >= 2:
		_debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_line_material)

		var first_point := _visible_polygon[1]
		var last_point := _visible_polygon[_visible_polygon.size() - 1]

		_debug_immediate_mesh.surface_add_vertex(Vector3(origin.x, draw_height, origin.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(first_point.x, draw_height, first_point.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(origin.x, draw_height, origin.z))
		_debug_immediate_mesh.surface_add_vertex(Vector3(last_point.x, draw_height, last_point.z))

		for i in range(1, _visible_polygon.size() - 1):
			var p1 := _visible_polygon[i]
			var p2 := _visible_polygon[i + 1]
			_debug_immediate_mesh.surface_add_vertex(Vector3(p1.x, draw_height, p1.z))
			_debug_immediate_mesh.surface_add_vertex(Vector3(p2.x, draw_height, p2.z))

		_debug_immediate_mesh.surface_end()

	# Draw hit points (only if there are any)
	var hit_points_exist := false
	for i in range(1, _visible_polygon.size()):
		var p := _visible_polygon[i]
		var dist := p.distance_to(origin)
		if dist < view_distance - 0.1:
			hit_points_exist = true
			break

	if hit_points_exist:
		var hit_material := StandardMaterial3D.new()
		hit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hit_material.albedo_color = debug_hit_color

		_debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, hit_material)
		var cross_size := 0.1
		for i in range(1, _visible_polygon.size()):
			var p := _visible_polygon[i]
			var dist := p.distance_to(origin)
			if dist < view_distance - 0.1:
				_debug_immediate_mesh.surface_add_vertex(Vector3(p.x - cross_size, draw_height, p.z))
				_debug_immediate_mesh.surface_add_vertex(Vector3(p.x + cross_size, draw_height, p.z))
				_debug_immediate_mesh.surface_add_vertex(Vector3(p.x, draw_height, p.z - cross_size))
				_debug_immediate_mesh.surface_add_vertex(Vector3(p.x, draw_height, p.z + cross_size))
		_debug_immediate_mesh.surface_end()


func _exit_tree() -> void:
	if _debug_mesh_instance and is_instance_valid(_debug_mesh_instance):
		_debug_mesh_instance.queue_free()
		_debug_mesh_instance = null


# ============================================
# Position and Direction Helpers
# ============================================

func _get_eye_position_raw() -> Vector3:
	if not _character:
		return global_position
	var pos := _character.global_position
	pos.y += eye_height
	return pos


func _get_look_angle() -> float:
	var direction := _get_look_direction()
	return atan2(direction.x, -direction.z)


func _get_look_direction() -> Vector3:
	if not _character:
		return Vector3.FORWARD

	if _character.has_method("get_facing_direction"):
		var dir: Vector3 = _character.get_facing_direction()
		if dir.length_squared() > 0.001:
			return dir.normalized()

	var forward := _character.global_transform.basis.z
	forward.y = 0

	if forward.length_squared() < 0.001:
		return Vector3.FORWARD

	return forward.normalized()
