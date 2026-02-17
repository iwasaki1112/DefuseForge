extends Node
## Character Registry - Manages all character presets
## Use as Autoload singleton (CharacterRegistry)

## Shared animation library sources (GLB files with animations)
const ANIMATION_SOURCE := "res://assets/animations/character_anims_kubold.glb"
const ANIMATION_SOURCE_MIXAMO := "res://assets/animations/character_anims_mixamo.glb"
var _animation_library: AnimationLibrary = null

# ============================================
# Preset Storage
# ============================================

## All registered presets indexed by ID
var _presets: Dictionary[String, CharacterPreset] = {}  # { id: CharacterPreset }

## Presets organized by team
var _by_team: Dictionary[GameCharacter.Team, Array] = {}  # { Team: Array[CharacterPreset] }

# ============================================
# Preset Directory
# ============================================

## Directory containing .tres preset files
const PRESET_DIR := "res://data/characters/"

## Static list of character preset files (required for exported builds)
## DirAccess does not work with res:// in exported .pck files
const PRESET_FILES := [
	"res://data/characters/alpha.tres",
	"res://data/characters/bravo.tres",
	"res://data/characters/ares.tres",
	"res://data/characters/dummy_ct.tres",
	"res://data/characters/dummy_t.tres",
	"res://data/characters/hostage_lucas.tres",
]

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_init_team_arrays()
	_load_animation_library()
	_load_presets_from_list()

func _init_team_arrays() -> void:
	for team in GameCharacter.Team.values():
		_by_team[team] = []

## Load shared animation library from GLB files
func _load_animation_library() -> void:
	_animation_library = _extract_animation_library(ANIMATION_SOURCE)
	if not _animation_library:
		return

	# Merge additional MIXAMO animations into the same library
	var mixamo_lib := _extract_animation_library(ANIMATION_SOURCE_MIXAMO)
	if mixamo_lib:
		for anim_name in mixamo_lib.get_animation_list():
			if not _animation_library.has_animation(anim_name):
				_animation_library.add_animation(anim_name, mixamo_lib.get_animation(anim_name))

## Extract AnimationLibrary from a GLB PackedScene
func _extract_animation_library(source_path: String) -> AnimationLibrary:
	if not ResourceLoader.exists(source_path):
		push_warning("CharacterRegistry: Animation source not found: %s" % source_path)
		return null

	var anim_scene := load(source_path) as PackedScene
	if not anim_scene:
		push_warning("CharacterRegistry: Could not load animation source: %s" % source_path)
		return null

	var anim_instance := anim_scene.instantiate()
	var source_anim_player := _find_animation_player(anim_instance)
	var lib: AnimationLibrary = null
	if source_anim_player:
		lib = source_anim_player.get_animation_library("")
	anim_instance.queue_free()
	return lib

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

## Load all preset files from static list
func _load_presets_from_list() -> void:
	for path in PRESET_FILES:
		if ResourceLoader.exists(path):
			var preset := load(path) as CharacterPreset
			if preset:
				register(preset)
		else:
			push_warning("CharacterRegistry: Preset file not found: %s" % path)

# ============================================
# Registration API
# ============================================

## Register a preset
func register(preset: CharacterPreset) -> void:
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

	var preset: CharacterPreset = _presets[id]
	_by_team[preset.team].erase(preset)
	_presets.erase(id)

# ============================================
# Query API
# ============================================

## Get preset by ID
func get_preset(id: String) -> CharacterPreset:
	return _presets.get(id)

## Check if preset exists
func has_preset(id: String) -> bool:
	return _presets.has(id)

## Get all presets
func get_all() -> Array:
	return _presets.values()

## Get presets by team
func get_by_team(team: GameCharacter.Team) -> Array:
	return _by_team.get(team, [])

## Get all Terrorist presets
func get_terrorists() -> Array:
	return get_by_team(GameCharacter.Team.TERRORIST)

## Get all Counter-Terrorist presets
func get_counter_terrorists() -> Array:
	return get_by_team(GameCharacter.Team.COUNTER_TERRORIST)

## Get shared animation library
func get_animation_library() -> AnimationLibrary:
	return _animation_library

# ============================================
# Factory API
# ============================================

## Create a GameCharacter instance from preset
## Returns null if preset not found or model_scene not set
func create_character(preset_id: String, spawn_position: Vector3 = Vector3.ZERO) -> Node:
	var preset := get_preset(preset_id)
	if not preset:
		push_error("CharacterRegistry: Preset not found: %s" % preset_id)
		return null

	return create_character_from_preset(preset, spawn_position)

## Create a GameCharacter instance from preset object
func create_character_from_preset(preset: CharacterPreset, spawn_position: Vector3 = Vector3.ZERO) -> Node:
	if not preset.model_scene:
		push_error("CharacterRegistry: Preset has no model_scene: %s" % preset.id)
		return null

	# Instance the model scene
	var model := preset.model_scene.instantiate()

	# Create GameCharacter as parent
	var character := GameCharacter.new()
	character.name = preset.id
	character.character_preset_id = preset.id
	character.max_health = preset.max_health
	character.team = preset.team
	character.position = spawn_position

	model.name = "CharacterModel"
	character.add_child(model)

	# Setup collision shape (物理衝突用 - 小さめ)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35  # 小さめに設定（キャラクター同士が近づきやすくする）
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	character.add_child(collision)

	# コリジョンマスク設定（Layer 1:床 + Layer 2:壁 に衝突する）
	character.collision_mask = 3

	# Setup tap area (タップ検出用 - 大きめ)
	var tap_area := Area3D.new()
	tap_area.name = "TapArea"
	var tap_collision := CollisionShape3D.new()
	tap_collision.name = "TapCollision"
	var tap_capsule := CapsuleShape3D.new()
	tap_capsule.radius = 0.7  # 物理コライダーの2倍（モバイルでタップしやすく）
	tap_capsule.height = 1.8
	tap_collision.shape = tap_capsule
	tap_collision.position.y = 0.9
	tap_area.add_child(tap_collision)
	character.add_child(tap_area)

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
	var anim_ctrl := CharacterAnimationController.new()
	character.add_child(anim_ctrl)
	character.set_anim_controller(anim_ctrl)

	# Defer setup until character is in scene tree
	# 初期向きはGameCharacter.set_facing_direction()で設定される
	character.ready.connect(func():
		anim_ctrl.setup(model, anim_player)
		# _facing_directionが設定されていればモデルを回転
		if character._facing_direction.length_squared() > 0.001:
			anim_ctrl.set_model_direction(character._facing_direction)
		# アニメーション適用後にSkeleton3Dオフセットを補正
		await character.get_tree().process_frame
		var skel := _find_skeleton(model)
		if skel:
			model.position.y = -skel.position.y
	, CONNECT_ONE_SHOT)

	return character


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null
