class_name FogOfWarSystem
extends Node3D

## Fog of War System (Redesigned)
## Uses SubViewport + Polygon2D for visibility rendering with external shader
## Simplified architecture for better door/wall dynamic updates

## Quality presets
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_SETTINGS := {
	Quality.LOW: {
		"resolution": 128,
		"msaa": SubViewport.MSAA_DISABLED,
		"ray_count": 36,
		"update_hz": 15
	},
	Quality.MEDIUM: {
		"resolution": 256,
		"msaa": SubViewport.MSAA_2X,
		"ray_count": 54,
		"update_hz": 20
	},
	Quality.HIGH: {
		"resolution": 512,
		"msaa": SubViewport.MSAA_4X,
		"ray_count": 72,
		"update_hz": 30
	},
}

## Export settings
@export_group("Map Settings")
@export var map_size: Vector2 = Vector2(40, 40)
@export var fog_height: float = 0.02

@export_group("Visual Settings")
@export var fog_color: Color = Color(0.1, 0.15, 0.25, 0.85)
@export var quality: Quality = Quality.LOW

## Internal settings (auto-configured from quality)
var texture_resolution: int = 128
var _update_interval: float = 0.067  # 15Hz default

## Internal nodes
var _fog_mesh: MeshInstance3D
var _fog_material: ShaderMaterial
var _visibility_viewport: SubViewport
var _visibility_polygons: Array[Polygon2D] = []

## Vision data
var _vision_components: Array = []
var _needs_update: bool = false
var _time_since_update: float = 0.0

## Shader reference
const FOW_SHADER_PATH := "res://shaders/fow.gdshader"


func _ready() -> void:
	_apply_quality_settings()
	_setup_visibility_viewport()
	_setup_fog_mesh()


## Apply quality preset settings
func _apply_quality_settings() -> void:
	var settings: Dictionary = QUALITY_SETTINGS[quality]
	texture_resolution = settings["resolution"]
	_update_interval = 1.0 / float(settings["update_hz"])


func _setup_visibility_viewport() -> void:
	var settings: Dictionary = QUALITY_SETTINGS[quality]

	# Create SubViewport for visibility texture
	_visibility_viewport = SubViewport.new()
	_visibility_viewport.name = "VisibilityViewport"
	_visibility_viewport.size = Vector2i(texture_resolution, texture_resolution)
	_visibility_viewport.transparent_bg = true
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_visibility_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_visibility_viewport.msaa_2d = settings["msaa"]
	add_child(_visibility_viewport)

	# Background (black = not visible)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.size = Vector2(texture_resolution, texture_resolution)
	_visibility_viewport.add_child(bg)


func _setup_fog_mesh() -> void:
	_fog_mesh = MeshInstance3D.new()
	_fog_mesh.name = "FogMesh"

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = map_size
	_fog_mesh.mesh = plane_mesh
	_fog_mesh.position.y = fog_height

	# Load external shader
	var shader: Shader = load(FOW_SHADER_PATH)
	if not shader:
		push_error("FogOfWarSystem: Failed to load shader from " + FOW_SHADER_PATH)
		return

	_fog_material = ShaderMaterial.new()
	_fog_material.shader = shader
	_fog_material.set_shader_parameter("fog_color", fog_color)
	_fog_material.set_shader_parameter("map_min", Vector2(-map_size.x / 2, -map_size.y / 2))
	_fog_material.set_shader_parameter("map_max", Vector2(map_size.x / 2, map_size.y / 2))
	_fog_material.set_shader_parameter("texture_size", float(texture_resolution))
	# モバイル最適化: blurを無効化
	_fog_material.set_shader_parameter("blur_radius", 0.0)
	_fog_material.set_shader_parameter("edge_softness", 0.1)

	_fog_mesh.material_override = _fog_material
	add_child(_fog_mesh)


func _process(delta: float) -> void:
	_time_since_update += delta

	# Update at configured interval or when dirty
	if _needs_update and _time_since_update >= _update_interval:
		_time_since_update = 0.0
		_update_visibility_texture()
		_needs_update = false

		# Request viewport render
		if _visibility_viewport:
			_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_fog_material.set_shader_parameter("visibility_texture", _visibility_viewport.get_texture())


func _update_visibility_texture() -> void:
	_sync_polygon_count()

	if _vision_components.is_empty():
		return

	# Update each VisionComponent's polygon
	for i in range(_vision_components.size()):
		var vision = _vision_components[i]
		if not is_instance_valid(vision):
			_visibility_polygons[i].polygon = PackedVector2Array()
			continue

		var polygon_3d: PackedVector3Array = vision.get_visible_polygon()
		_visibility_polygons[i].polygon = _convert_polygon_to_2d(polygon_3d)


## Sync polygon count with VisionComponent count
func _sync_polygon_count() -> void:
	# Add missing polygons
	while _visibility_polygons.size() < _vision_components.size():
		var polygon := Polygon2D.new()
		polygon.color = Color(1, 1, 1, 1)
		polygon.antialiased = true
		_visibility_viewport.add_child(polygon)
		_visibility_polygons.append(polygon)

	# Clear excess polygons (don't delete, just hide)
	for i in range(_vision_components.size(), _visibility_polygons.size()):
		_visibility_polygons[i].polygon = PackedVector2Array()


## Convert 3D polygon to 2D texture coordinates
func _convert_polygon_to_2d(polygon_3d: PackedVector3Array) -> PackedVector2Array:
	if polygon_3d.size() < 3:
		return PackedVector2Array()

	var polygon_2d := PackedVector2Array()
	var half_map := map_size / 2

	for point in polygon_3d:
		# World XZ -> Texture UV -> Pixel coordinates
		var uv_x := (point.x + half_map.x) / map_size.x
		var uv_y := (point.z + half_map.y) / map_size.y
		polygon_2d.append(Vector2(uv_x * texture_resolution, uv_y * texture_resolution))

	return polygon_2d


## Register a VisionComponent
func register_vision(vision) -> void:
	if vision and vision not in _vision_components:
		_vision_components.append(vision)
		# Connect vision update signal
		if vision.has_signal("vision_updated"):
			if not vision.vision_updated.is_connected(_on_vision_updated):
				vision.vision_updated.connect(_on_vision_updated)
		_needs_update = true


## Unregister a VisionComponent
func unregister_vision(vision) -> void:
	if vision in _vision_components:
		# Disconnect signal
		if vision.has_signal("vision_updated") and vision.vision_updated.is_connected(_on_vision_updated):
			vision.vision_updated.disconnect(_on_vision_updated)
		_vision_components.erase(vision)
		_needs_update = true


## Handler for vision update signal
func _on_vision_updated(_visible_points: PackedVector3Array) -> void:
	_needs_update = true


## Set fog visibility
func set_fog_visible(fog_visible: bool) -> void:
	if _fog_mesh:
		_fog_mesh.visible = fog_visible


## Force visibility texture update
func force_update() -> void:
	_needs_update = true
	_time_since_update = _update_interval  # Force immediate update


## Set fog color
func set_fog_color(color: Color) -> void:
	fog_color = color
	if _fog_material:
		_fog_material.set_shader_parameter("fog_color", fog_color)


## Get visibility texture (for wall lighting, etc.)
func get_visibility_texture() -> ViewportTexture:
	if _visibility_viewport:
		return _visibility_viewport.get_texture()
	return null


## Dynamically change map size
func set_map_size(new_size: Vector2) -> void:
	map_size = new_size

	# Update fog mesh size
	if _fog_mesh and _fog_mesh.mesh is PlaneMesh:
		(_fog_mesh.mesh as PlaneMesh).size = map_size

	# Update shader parameters
	if _fog_material:
		_fog_material.set_shader_parameter("map_min", Vector2(-map_size.x / 2, -map_size.y / 2))
		_fog_material.set_shader_parameter("map_max", Vector2(map_size.x / 2, map_size.y / 2))

	_needs_update = true


## Set quality preset at runtime
func set_quality(q: Quality) -> void:
	quality = q
	_apply_quality_settings()

	# Resize viewport
	if _visibility_viewport:
		_visibility_viewport.size = Vector2i(texture_resolution, texture_resolution)
		# Resize background
		for child in _visibility_viewport.get_children():
			if child is ColorRect:
				child.size = Vector2(texture_resolution, texture_resolution)
				break

	if _fog_material:
		_fog_material.set_shader_parameter("texture_size", float(texture_resolution))

	_needs_update = true


## Get quality settings for VisionComponent synchronization
func get_quality_settings() -> Dictionary:
	return QUALITY_SETTINGS[quality]
