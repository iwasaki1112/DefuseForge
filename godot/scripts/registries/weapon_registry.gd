extends Node
## Weapon Registry - Manages all weapon presets
## Use as Autoload singleton (WeaponRegistry)


# ============================================
# Preset Storage
# ============================================

## All registered presets indexed by ID
var _presets: Dictionary[String, WeaponPreset] = {}  # { id: WeaponPreset }

## Presets organized by category
var _by_category: Dictionary[WeaponPreset.WeaponCategory, Array] = {}  # { WeaponCategory: Array[WeaponPreset] }

# ============================================
# Preset Directory
# ============================================

## Directory containing .tres preset files
const PRESET_DIR := "res://data/weapons/"

## Static list of weapon preset files (required for exported builds)
## DirAccess does not work with res:// in exported .pck files
const PRESET_FILES := [
	"res://data/weapons/ak47.tres",
	"res://data/weapons/glock.tres",
]

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_init_category_arrays()
	_load_presets_from_list()

func _init_category_arrays() -> void:
	for category in WeaponPreset.WeaponCategory.values():
		_by_category[category] = []

# ============================================
# Loading
# ============================================

## Load all preset files from static list
func _load_presets_from_list() -> void:
	for path in PRESET_FILES:
		if ResourceLoader.exists(path):
			var preset := load(path) as WeaponPreset
			if preset:
				register(preset)
		else:
			push_warning("WeaponRegistry: Preset file not found: %s" % path)

# ============================================
# Registration API
# ============================================

## Register a preset
func register(preset: WeaponPreset) -> void:
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

	var preset: WeaponPreset = _presets[id]
	_by_category[preset.category].erase(preset)
	_presets.erase(id)

# ============================================
# Query API
# ============================================

## Get preset by ID
func get_preset(id: String) -> WeaponPreset:
	return _presets.get(id)

## Check if preset exists
func has_preset(id: String) -> bool:
	return _presets.has(id)

## Get all presets
func get_all() -> Array:
	return _presets.values()

## Get presets by category
func get_by_category(category: WeaponPreset.WeaponCategory) -> Array:
	return _by_category.get(category, [])

## Get all rifles
func get_rifles() -> Array:
	return get_by_category(WeaponPreset.WeaponCategory.RIFLE)

## Get all pistols
func get_pistols() -> Array:
	return get_by_category(WeaponPreset.WeaponCategory.PISTOL)

## Get all SMGs
func get_smgs() -> Array:
	return get_by_category(WeaponPreset.WeaponCategory.SMG)

## Get all shotguns
func get_shotguns() -> Array:
	return get_by_category(WeaponPreset.WeaponCategory.SHOTGUN)

## Get all snipers
func get_snipers() -> Array:
	return get_by_category(WeaponPreset.WeaponCategory.SNIPER)
