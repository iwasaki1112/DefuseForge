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

## Static list of map preset files (required for exported builds)
## DirAccess does not work with res:// in exported .pck files
const PRESET_FILES := [
	"res://data/maps/bank.tres",
	        "res://data/maps/convenience_store.tres",	"res://data/maps/iwasaki_test.tres",
	"res://data/maps/park.tres",
]

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_load_presets_from_list()

# ============================================
# Loading
# ============================================

## Load all preset files from static list
func _load_presets_from_list() -> void:
	for path in PRESET_FILES:
		if ResourceLoader.exists(path):
			var preset := load(path) as MapPresetScript
			if preset:
				register(preset)
		else:
			push_warning("MapRegistry: Preset file not found: %s" % path)

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

	# Extract spawn points from scene markers if available
	_extract_spawn_points(map_instance, preset)

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

	# Recursively process children
	for child in node.get_children():
		_setup_wall_groups(child)

# ============================================
# Spawn Point Extraction
# ============================================

## Spawn marker naming patterns
const SPAWN_CT_PATTERNS := ["spawn_ct_", "SpawnCT"]
const SPAWN_T_PATTERNS := ["spawn_t_", "SpawnT"]

## Extract spawn points and rotations from scene markers and update preset
## Markers should be named: spawn_ct_1, spawn_ct_2, ... or SpawnCT1, SpawnCT2, ...
## For T side: spawn_t_1, spawn_t_2, ... or SpawnT1, SpawnT2, ...
func _extract_spawn_points(map_instance: Node3D, preset: MapPresetScript) -> void:
	var ct_spawns: Array[Vector3] = []
	var ct_rotations: Array[float] = []
	var t_spawns: Array[Vector3] = []
	var t_rotations: Array[float] = []

	# Recursively find spawn markers
	_find_spawn_markers(map_instance, ct_spawns, ct_rotations, t_spawns, t_rotations)

	# Update preset if markers were found
	if ct_spawns.size() > 0:
		preset.spawn_points_ct = ct_spawns
		preset.spawn_rotations_ct = ct_rotations
	if t_spawns.size() > 0:
		preset.spawn_points_t = t_spawns
		preset.spawn_rotations_t = t_rotations

## Recursively find spawn marker nodes
func _find_spawn_markers(
	node: Node,
	ct_spawns: Array[Vector3],
	ct_rotations: Array[float],
	t_spawns: Array[Vector3],
	t_rotations: Array[float]
) -> void:
	var node_name := node.name.to_lower()

	# Check for CT spawn markers
	for pattern in SPAWN_CT_PATTERNS:
		if node_name.begins_with(pattern.to_lower()):
			if node is Node3D:
				var node3d := node as Node3D
				ct_spawns.append(node3d.position)
				ct_rotations.append(node3d.rotation.y)
			break

	# Check for T spawn markers
	for pattern in SPAWN_T_PATTERNS:
		if node_name.begins_with(pattern.to_lower()):
			if node is Node3D:
				var node3d := node as Node3D
				t_spawns.append(node3d.position)
				t_rotations.append(node3d.rotation.y)
			break

	# Recursively process children
	for child in node.get_children():
		_find_spawn_markers(child, ct_spawns, ct_rotations, t_spawns, t_rotations)
