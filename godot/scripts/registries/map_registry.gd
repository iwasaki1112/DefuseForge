extends Node
## Map Registry - Manages all map presets
## Use as Autoload singleton (MapRegistry)
##
## マップの検出方式:
## 1. scenes/maps/ の .tscn をスキャン（map_id @exportが設定されたMapBase直接方式）
## 2. エクスポート時: PRESET_FILES静的リストにフォールバック


## Wall collision layer bit (for VisionComponent)
const WALL_COLLISION_LAYER := 2

# ============================================
# Preset Storage
# ============================================

## All registered presets indexed by ID
var _presets: Dictionary[String, MapPreset] = {}  # { id: MapPreset }

# ============================================
# Directories
# ============================================

## マップシーンディレクトリ（.tscn直接方式）
const SCENE_DIR := "res://scenes/maps/"

## 静的リスト（exported builds用フォールバック）
## scripts/editor/sync_map_presets.gd で自動更新可能
const PRESET_FILES := [
	"res://scenes/maps/office.tscn",
]

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	# エディタ: ディレクトリスキャンで自動検出
	var found := _load_presets_from_scenes()
	# エクスポート: DirAccessが使えない場合は静的リストにフォールバック
	if not found:
		_load_presets_from_list()

# ============================================
# Loading - Scene Direct (.tscn)
# ============================================

## scenes/maps/の.tscnをスキャンしてmap_id付きマップを検出
func _load_presets_from_scenes() -> bool:
	var dir := DirAccess.open(SCENE_DIR)
	if not dir:
		return false

	var found := false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn"):
			var path := SCENE_DIR + file_name
			var scene := load(path) as PackedScene
			if scene:
				var preset := _create_preset_from_scene(scene)
				if preset:
					register(preset)
					found = true
		file_name = dir.get_next()
	dir.list_dir_end()
	return found


## PackedSceneのSceneStateからMapPresetを生成（インスタンス化不要）
func _create_preset_from_scene(scene: PackedScene) -> MapPreset:
	var state := scene.get_state()
	if state.get_node_count() == 0:
		return null

	var mid := ""
	var dname := ""
	var desc := ""

	for i in state.get_node_property_count(0):
		var prop_name := state.get_node_property_name(0, i)
		var prop_value = state.get_node_property_value(0, i)
		match prop_name:
			&"map_id":
				mid = str(prop_value)
			&"display_name":
				dname = str(prop_value)
			&"map_description":
				desc = str(prop_value)

	# map_idが未設定 → このシーンは自己記述型マップではない
	if mid.is_empty():
		return null

	var preset := MapPreset.new()
	preset.id = mid
	preset.display_name = dname if not dname.is_empty() else mid.to_pascal_case()
	preset.description = desc
	preset.map_scene = scene
	return preset

# ============================================
# Loading - Static Fallback
# ============================================

## 静的リストからロード（exported builds用）
func _load_presets_from_list() -> void:
	for path in PRESET_FILES:
		if not ResourceLoader.exists(path):
			push_warning("MapRegistry: File not found: %s" % path)
			continue

		var scene := load(path) as PackedScene
		if scene:
			var preset := _create_preset_from_scene(scene)
			if preset:
				register(preset)

# ============================================
# Registration API
# ============================================

## Register a preset
func register(preset: MapPreset) -> void:
	if preset.id.is_empty():
		push_warning("MapRegistry: Cannot register preset with empty ID")
		return

	if _presets.has(preset.id):
		# 重複は静かにスキップ（.tscnと.tresの両方存在時）
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
func get_preset(id: String) -> MapPreset:
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
func instantiate_map_from_preset(preset: MapPreset) -> Node3D:
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
const SPAWN_HOSTAGE_PATTERNS := ["spawn_hostage_", "SpawnHostage"]

## Extract spawn points and rotations from scene markers and update preset
## Markers should be named: spawn_ct_1, spawn_ct_2, ... or SpawnCT1, SpawnCT2, ...
## For T side: spawn_t_1, spawn_t_2, ... or SpawnT1, SpawnT2, ...
func _extract_spawn_points(map_instance: Node3D, preset: MapPreset) -> void:
	var ct_spawns: Array[Vector3] = []
	var ct_rotations: Array[float] = []
	var t_spawns: Array[Vector3] = []
	var t_rotations: Array[float] = []
	var hostage_spawns: Array[Vector3] = []
	var hostage_rotations: Array[float] = []

	# Recursively find spawn markers
	_find_spawn_markers(map_instance, ct_spawns, ct_rotations, t_spawns, t_rotations, hostage_spawns, hostage_rotations)

	# Update preset if markers were found
	if ct_spawns.size() > 0:
		preset.spawn_points_ct = ct_spawns
		preset.spawn_rotations_ct = ct_rotations
	if t_spawns.size() > 0:
		preset.spawn_points_t = t_spawns
		preset.spawn_rotations_t = t_rotations
	if hostage_spawns.size() > 0:
		preset.spawn_points_hostage = hostage_spawns
		preset.spawn_rotations_hostage = hostage_rotations

## Recursively find spawn marker nodes
func _find_spawn_markers(
	node: Node,
	ct_spawns: Array[Vector3],
	ct_rotations: Array[float],
	t_spawns: Array[Vector3],
	t_rotations: Array[float],
	hostage_spawns: Array[Vector3],
	hostage_rotations: Array[float]
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

	# Check for Hostage spawn markers
	for pattern in SPAWN_HOSTAGE_PATTERNS:
		if node_name.begins_with(pattern.to_lower()):
			if node is Node3D:
				var node3d := node as Node3D
				hostage_spawns.append(node3d.position)
				hostage_rotations.append(node3d.rotation.y)
			break

	# Recursively process children
	for child in node.get_children():
		_find_spawn_markers(child, ct_spawns, ct_rotations, t_spawns, t_rotations, hostage_spawns, hostage_rotations)
