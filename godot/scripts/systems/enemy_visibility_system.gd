extends Node
class_name EnemyVisibilitySystem
## Enemy visibility management system
## Controls enemy character visibility based on friendly vision
## Works with PlayerState, VisionComponent, and FogOfWarSystem (Light2D方式)
##
## Light2D方式ではFoWの描画はGPUで行われるが、
## 敵の可視判定はVisionComponent.is_position_in_view()で行う（単発レイキャスト）

# ============================================
# Signals
# ============================================
signal visibility_changed(enemy: Node, is_visible: bool)

# ============================================
# References
# ============================================
var _fog_of_war_system: Node3D = null
var _characters: Array[Node] = []

# ============================================
# State
# ============================================
var _visibility_cache: Dictionary = {}  # { instance_id: bool }
var _is_enabled: bool = true

# SmokeAreaManager reference
var _smoke_area_manager: SmokeAreaManager = null

# Update settings
const UPDATE_INTERVAL: float = 0.033  # 30Hz
var _update_timer: float = 0.0

# ============================================
# Lifecycle
# ============================================

func _physics_process(delta: float) -> void:
	if not _is_enabled:
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		update_visibility()


# ============================================
# Setup
# ============================================

## Initialize with FogOfWarSystem reference
func setup(fog_of_war: Node3D) -> void:
	_fog_of_war_system = fog_of_war
	PlayerState.team_changed.connect(_on_player_team_changed)


## Set SmokeAreaManager reference
func set_smoke_area_manager(manager: SmokeAreaManager) -> void:
	_smoke_area_manager = manager


## Register a character to be managed
func register_character(character: Node) -> void:
	if character in _characters:
		return
	_characters.append(character)

	# Apply initial visibility
	update_visibility()


## Unregister a character
func unregister_character(character: Node) -> void:
	_characters.erase(character)
	var char_id := character.get_instance_id()
	_visibility_cache.erase(char_id)


# ============================================
# Enable/Disable
# ============================================

## Enable the system (normal gameplay)
func enable() -> void:
	enable_full()


## Disable the system (debug mode - show all)
func disable() -> void:
	_is_enabled = false
	# Show all characters
	for character in _characters:
		character.visible = true


## Enable with full visibility checking (FoW ON)
func enable_full() -> void:
	_is_enabled = true
	update_visibility()


## Enable with lightweight visibility (FoW OFF)
## Same as enable_full in Light2D mode since we always use is_position_in_view()
func enable_lightweight() -> void:
	_is_enabled = true
	update_visibility()


## Check if system is enabled
func is_enabled() -> bool:
	return _is_enabled


# ============================================
# Visibility API
# ============================================

## Update visibility of all enemy characters
func update_visibility() -> void:
	if not _is_enabled:
		return

	# Friendly characters are always visible
	for friendly in _get_friendly_characters():
		friendly.visible = true

	# Check enemy visibility
	for enemy in _get_enemy_characters():
		var enemy_node3d := enemy as Node3D
		if not enemy_node3d:
			continue

		var enemy_pos: Vector3 = enemy_node3d.global_position
		var is_visible := _is_position_visible_to_friendlies(enemy_pos)

		var instance_id := enemy.get_instance_id()

		# Update only if changed
		if _visibility_cache.get(instance_id) != is_visible:
			_visibility_cache[instance_id] = is_visible
			enemy.visible = is_visible
			visibility_changed.emit(enemy, is_visible)


## Check if a world position is visible to any friendly character
func is_position_visible(world_pos: Vector3) -> bool:
	return _is_position_visible_to_friendlies(world_pos)


## Get cached visibility state for a character
func get_visibility(character: Node) -> bool:
	return _visibility_cache.get(character.get_instance_id(), false)


# ============================================
# Internal - Vision Check
# ============================================

## FoWテクスチャを直接サンプリングして可視判定
## Light2D方式では視覚的なFoW表示と完全に同期した判定を行う
func _is_position_visible_to_friendlies(world_pos: Vector3) -> bool:
	# FogOfWarSystemのテクスチャサンプリングを使用
	# これにより視覚的な可視性と論理的な可視性が完全に一致する
	if _fog_of_war_system and _fog_of_war_system.has_method("is_position_visible_in_fow"):
		return _fog_of_war_system.is_position_visible_in_fow(world_pos)

	# フォールバック: FoWシステムが利用できない場合はVisionComponentを使用
	for friendly in _get_friendly_characters():
		var game_char := friendly as GameCharacter
		if not game_char or not game_char.vision or not game_char.is_alive:
			continue

		if game_char.vision.is_position_in_view(world_pos):
			return true

	return false


# ============================================
# Internal - Character Classification
# ============================================

func _get_friendly_characters() -> Array[Node]:
	return PlayerState.filter_friendlies(_characters)


func _get_enemy_characters() -> Array[Node]:
	return PlayerState.filter_enemies(_characters)


# ============================================
# Signal Handlers
# ============================================

func _on_player_team_changed(_new_team: GameCharacter.Team) -> void:
	_visibility_cache.clear()
	update_visibility()
