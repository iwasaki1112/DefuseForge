extends Node
## Character Registry - Manages all character presets
## Use as Autoload singleton (CharacterRegistry)

const GameCharacterScript = preload("res://scripts/characters/game_character.gd")
const CharacterPresetScript = preload("res://scripts/resources/character_preset.gd")
const CharAnimCtrl = preload("res://scripts/animation/character_animation_controller.gd")

## Shared animation library source (GLB with character and all animations)
const ANIMATION_SOURCE := "res://assets/animations/character_anims.glb"
var _animation_library: AnimationLibrary = null

# ============================================
# Preset Storage
# ============================================

## All registered presets indexed by ID
var _presets: Dictionary = {}  # { id: CharacterPreset }

## Presets organized by team
var _by_team: Dictionary = {}  # { Team: Array[CharacterPreset] }

# ============================================
# Preset Directory
# ============================================

## Directory containing .tres preset files
const PRESET_DIR := "res://data/characters/"

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_init_team_arrays()
	_load_animation_library()
	_load_presets_from_directory()

func _init_team_arrays() -> void:
	for team in GameCharacterScript.Team.values():
		_by_team[team] = []

## Load shared animation library from blend file
func _load_animation_library() -> void:
	if not ResourceLoader.exists(ANIMATION_SOURCE):
		push_warning("CharacterRegistry: Animation source not found: %s" % ANIMATION_SOURCE)
		return

	var anim_scene := load(ANIMATION_SOURCE) as PackedScene
	if not anim_scene:
		push_warning("CharacterRegistry: Could not load animation source")
		return

	# Instance temporarily to extract animations
	var anim_instance := anim_scene.instantiate()
	var source_anim_player := _find_animation_player(anim_instance)

	if source_anim_player:
		_animation_library = source_anim_player.get_animation_library("")
		if _animation_library:
			print("CharacterRegistry: Loaded %d animations from %s" % [
				_animation_library.get_animation_list().size(),
				ANIMATION_SOURCE.get_file()
			])

	anim_instance.queue_free()

## Find AnimationPlayer in node tree
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null

# ============================================
# Loading
# ============================================

## Load all preset .tres files from PRESET_DIR
func _load_presets_from_directory() -> void:
	if not DirAccess.dir_exists_absolute(PRESET_DIR):
		push_warning("CharacterRegistry: Preset directory not found: %s" % PRESET_DIR)
		return

	var dir := DirAccess.open(PRESET_DIR)
	if not dir:
		push_warning("CharacterRegistry: Could not open preset directory: %s" % PRESET_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := PRESET_DIR + file_name
			var preset := load(path) as CharacterPresetScript
			if preset:
				register(preset)
		file_name = dir.get_next()

	dir.list_dir_end()
	print("CharacterRegistry: Loaded %d presets" % _presets.size())

# ============================================
# Registration API
# ============================================

## Register a preset
func register(preset: CharacterPresetScript) -> void:
	if preset.id.is_empty():
		push_warning("CharacterRegistry: Cannot register preset with empty ID")
		return

	if _presets.has(preset.id):
		push_warning("CharacterRegistry: Preset already registered: %s" % preset.id)
		return

	_presets[preset.id] = preset
	_by_team[preset.team].append(preset)

## Unregister a preset
func unregister(id: String) -> void:
	if not _presets.has(id):
		return

	var preset: CharacterPresetScript = _presets[id]
	_by_team[preset.team].erase(preset)
	_presets.erase(id)

# ============================================
# Query API
# ============================================

## Get preset by ID
func get_preset(id: String) -> CharacterPresetScript:
	return _presets.get(id)

## Check if preset exists
func has_preset(id: String) -> bool:
	return _presets.has(id)

## Get all presets
func get_all() -> Array:
	return _presets.values()

## Get presets by team
func get_by_team(team: GameCharacterScript.Team) -> Array:
	return _by_team.get(team, [])

## Get all Terrorist presets
func get_terrorists() -> Array:
	return get_by_team(GameCharacterScript.Team.TERRORIST)

## Get all Counter-Terrorist presets
func get_counter_terrorists() -> Array:
	return get_by_team(GameCharacterScript.Team.COUNTER_TERRORIST)

# ============================================
# Factory API
# ============================================

## Create a GameCharacter instance from preset
## Returns null if preset not found or model_scene not set
func create_character(preset_id: String, position: Vector3 = Vector3.ZERO) -> Node:
	var preset := get_preset(preset_id)
	if not preset:
		push_error("CharacterRegistry: Preset not found: %s" % preset_id)
		return null

	return create_character_from_preset(preset, position)

## Create a GameCharacter instance from preset object
func create_character_from_preset(preset: CharacterPresetScript, position: Vector3 = Vector3.ZERO) -> Node:
	if not preset.model_scene:
		push_error("CharacterRegistry: Preset has no model_scene: %s" % preset.id)
		return null

	# Instance the model scene
	var model := preset.model_scene.instantiate()

	# Create GameCharacter as parent
	var character := GameCharacterScript.new()
	character.name = preset.id
	character.max_health = preset.max_health
	character.team = preset.team
	character.position = position

	# Add model as child
	model.name = "CharacterModel"
	character.add_child(model)

	# Setup collision shape
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	character.add_child(collision)

	# Setup AnimationPlayer with shared animation library
	var anim_player := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		model.add_child(anim_player)

	# Replace or add shared animation library
	if _animation_library:
		if anim_player.has_animation_library(""):
			anim_player.remove_animation_library("")
		anim_player.add_animation_library("", _animation_library)

	# Setup animation controller (deferred until added to scene tree)
	# Speed settings are defined in CharacterAnimationController defaults
	var anim_ctrl := CharAnimCtrl.new()
	character.add_child(anim_ctrl)
	character.set_anim_controller(anim_ctrl)
	# Defer setup until character is in scene tree
	character.ready.connect(func(): anim_ctrl.setup(model, anim_player), CONNECT_ONE_SHOT)

	return character
