extends Node
## Weapon Registry - Manages all weapon presets
## Use as Autoload singleton (WeaponRegistry)

const WeaponPresetScript = preload("res://scripts/resources/weapon_preset.gd")

# ============================================
# Preset Storage
# ============================================

## All registered presets indexed by ID
var _presets: Dictionary = {}  # { id: WeaponPreset }

## Presets organized by category
var _by_category: Dictionary = {}  # { WeaponCategory: Array[WeaponPreset] }

# ============================================
# Preset Directory
# ============================================

## Directory containing .tres preset files
const PRESET_DIR := "res://data/weapons/"

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_init_category_arrays()
	_load_presets_from_directory()

func _init_category_arrays() -> void:
	for category in WeaponPresetScript.WeaponCategory.values():
		_by_category[category] = []

# ============================================
# Loading
# ============================================

## Load all preset .tres files from PRESET_DIR
func _load_presets_from_directory() -> void:
	if not DirAccess.dir_exists_absolute(PRESET_DIR):
		push_warning("WeaponRegistry: Preset directory not found: %s" % PRESET_DIR)
		return

	var dir := DirAccess.open(PRESET_DIR)
	if not dir:
		push_warning("WeaponRegistry: Could not open preset directory: %s" % PRESET_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := PRESET_DIR + file_name
			var preset := load(path) as WeaponPresetScript
			if preset:
				register(preset)
		file_name = dir.get_next()

	dir.list_dir_end()
	print("WeaponRegistry: Loaded %d presets" % _presets.size())

# ============================================
# Registration API
# ============================================

## Register a preset
func register(preset: WeaponPresetScript) -> void:
	if preset.id.is_empty():
		push_warning("WeaponRegistry: Cannot register preset with empty ID")
		return

	if _presets.has(preset.id):
		push_warning("WeaponRegistry: Preset already registered: %s" % preset.id)
		return

	_presets[preset.id] = preset
	_by_category[preset.category].append(preset)

## Unregister a preset
func unregister(id: String) -> void:
	if not _presets.has(id):
		return

	var preset: WeaponPresetScript = _presets[id]
	_by_category[preset.category].erase(preset)
	_presets.erase(id)

# ============================================
# Query API
# ============================================

## Get preset by ID
func get_preset(id: String) -> WeaponPresetScript:
	return _presets.get(id)

## Check if preset exists
func has_preset(id: String) -> bool:
	return _presets.has(id)

## Get all presets
func get_all() -> Array:
	return _presets.values()

## Get presets by category
func get_by_category(category: WeaponPresetScript.WeaponCategory) -> Array:
	return _by_category.get(category, [])

## Get all rifles
func get_rifles() -> Array:
	return get_by_category(WeaponPresetScript.WeaponCategory.RIFLE)

## Get all pistols
func get_pistols() -> Array:
	return get_by_category(WeaponPresetScript.WeaponCategory.PISTOL)

## Get all SMGs
func get_smgs() -> Array:
	return get_by_category(WeaponPresetScript.WeaponCategory.SMG)

## Get all shotguns
func get_shotguns() -> Array:
	return get_by_category(WeaponPresetScript.WeaponCategory.SHOTGUN)

## Get all snipers
func get_snipers() -> Array:
	return get_by_category(WeaponPresetScript.WeaponCategory.SNIPER)
