extends Node
## Map Registry - Manages all map presets
## Use as Autoload singleton (MapRegistry)

const MapPresetScript = preload("res://scripts/resources/map_preset.gd")

## Wall collision layer bit (for VisionComponent)
const WALL_COLLISION_LAYER := 2

# ============================================
# Preset Storage
# ============================================

## All registered presets indexed by ID
var _presets: Dictionary = {}  # { id: MapPreset }

# ============================================
# Preset Directory
# ============================================

## Directory containing .tres preset files
const PRESET_DIR := "res://data/maps/"

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_load_presets_from_directory()

# ============================================
# Loading
# ============================================

## Load all preset .tres files from PRESET_DIR
func _load_presets_from_directory() -> void:
	if not DirAccess.dir_exists_absolute(PRESET_DIR):
		push_warning("MapRegistry: Preset directory not found: %s" % PRESET_DIR)
		return

	var dir := DirAccess.open(PRESET_DIR)
	if not dir:
		push_warning("MapRegistry: Could not open preset directory: %s" % PRESET_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := PRESET_DIR + file_name
			var preset := load(path) as MapPresetScript
			if preset:
				register(preset)
		file_name = dir.get_next()

	dir.list_dir_end()
	print("MapRegistry: Loaded %d presets" % _presets.size())

# ============================================
# Registration API
# ============================================

## Register a preset
func register(preset: MapPresetScript) -> void:
	if preset.id.is_empty():
		push_warning("MapRegistry: Cannot register preset with empty ID")
		return

	if _presets.has(preset.id):
		push_warning("MapRegistry: Preset already registered: %s" % preset.id)
		return

	_presets[preset.id] = preset

## Unregister a preset
func unregister(id: String) -> void:
	if not _presets.has(id):
		return
	_presets.erase(id)

# ============================================
# Query API
# ============================================

## Get preset by ID
func get_preset(id: String) -> MapPresetScript:
	return _presets.get(id)

## Check if preset exists
func has_preset(id: String) -> bool:
	return _presets.has(id)

## Get all presets
func get_all() -> Array:
	return _presets.values()

## Get all preset IDs
func get_all_ids() -> Array:
	return _presets.keys()

# ============================================
# Factory API
# ============================================

## Create a map instance from preset ID
## Returns null if preset not found or map_scene not set
func instantiate_map(preset_id: String) -> Node3D:
	var preset := get_preset(preset_id)
	if not preset:
		push_error("MapRegistry: Preset not found: %s" % preset_id)
		return null

	return instantiate_map_from_preset(preset)

## Create a map instance from preset object
func instantiate_map_from_preset(preset: MapPresetScript) -> Node3D:
	if not preset.map_scene:
		push_error("MapRegistry: Preset has no map_scene: %s" % preset.id)
		return null

	var map_instance := preset.map_scene.instantiate() as Node3D
	if not map_instance:
		push_error("MapRegistry: Failed to instantiate map scene: %s" % preset.id)
		return null

	# Setup wall groups for VisionComponent
	_setup_wall_groups(map_instance)

	return map_instance

# ============================================
# Wall Setup
# ============================================

## Recursively add nodes with collision_layer=WALL_COLLISION_LAYER to "walls" group
func _setup_wall_groups(node: Node) -> void:
	# Check if this node has collision_layer property and matches wall layer
	if node is CollisionObject3D:
		var collision_obj := node as CollisionObject3D
		if collision_obj.collision_layer & WALL_COLLISION_LAYER:
			node.add_to_group("walls")

	# Also check GridMap nodes
	if node is GridMap:
		var grid_map := node as GridMap
		if grid_map.collision_layer & WALL_COLLISION_LAYER:
			node.add_to_group("walls")

	# Recursively process children
	for child in node.get_children():
		_setup_wall_groups(child)
