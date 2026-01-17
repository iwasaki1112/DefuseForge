extends Node
class_name EnemyVisibilitySystem
## Enemy visibility management system
## Controls enemy character visibility based on friendly vision polygons
## Works with PlayerState, VisionComponent, and FogOfWarSystem
##
## Supports two visibility modes:
## - FULL_VISION: Uses polygon-based visibility (for FoW ON)
## - LIGHTWEIGHT: Uses single raycast per enemy (for FoW OFF, 97% less rays)

# ============================================
# Enums
# ============================================
enum VisibilityMode {
	FULL_VISION,   ## Full polygon-based visibility (FoW ON)
	LIGHTWEIGHT    ## Lightweight single-raycast visibility (FoW OFF)
}

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
var _mode: VisibilityMode = VisibilityMode.FULL_VISION

# Lightweight mode update settings
const LIGHTWEIGHT_UPDATE_INTERVAL: float = 0.05  # 50ms (20 FPS)
var _lightweight_update_timer: float = 0.0

# ============================================
# Lifecycle
# ============================================

func _physics_process(delta: float) -> void:
	# In LIGHTWEIGHT mode, periodically update visibility
	# (since VisionComponent signals are disabled)
	if _mode == VisibilityMode.LIGHTWEIGHT and _is_enabled:
		_lightweight_update_timer += delta
		if _lightweight_update_timer >= LIGHTWEIGHT_UPDATE_INTERVAL:
			_lightweight_update_timer = 0.0
			update_visibility()


# ============================================
# Setup
# ============================================

## Initialize with FogOfWarSystem reference
func setup(fog_of_war: Node3D) -> void:
	_fog_of_war_system = fog_of_war
	PlayerState.team_changed.connect(_on_player_team_changed)


## Register a character to be managed
func register_character(character: Node) -> void:
	if character in _characters:
		return
	_characters.append(character)

	# Connect vision signal for friendly characters
	var game_char := character as GameCharacter
	if game_char and game_char.vision:
		if game_char.vision.has_signal("vision_updated"):
			if not game_char.vision.vision_updated.is_connected(_on_vision_updated):
				game_char.vision.vision_updated.connect(_on_vision_updated.bind(character))

	# Apply initial visibility
	_update_single_character_vision(character)
	update_visibility()


## Unregister a character
func unregister_character(character: Node) -> void:
	_characters.erase(character)
	_visibility_cache.erase(character.get_instance_id())

	var game_char := character as GameCharacter
	if game_char and game_char.vision:
		if game_char.vision.vision_updated.is_connected(_on_vision_updated):
			game_char.vision.vision_updated.disconnect(_on_vision_updated)


# ============================================
# Enable/Disable
# ============================================

## Enable the system (normal gameplay)
func enable() -> void:
	enable_full()


## Disable the system (debug mode - show all)
func disable() -> void:
	_is_enabled = false
	_mode = VisibilityMode.FULL_VISION
	# Show all characters
	for character in _characters:
		character.visible = true
	# Enable all vision for FoW
	_show_all_vision()


## Enable with full polygon-based visibility (FoW ON)
func enable_full() -> void:
	_is_enabled = true
	_mode = VisibilityMode.FULL_VISION
	_update_all_vision_registration()

	# Force FoW to update after re-registering visions
	if _fog_of_war_system and _fog_of_war_system.has_method("force_update"):
		_fog_of_war_system.force_update()

	update_visibility()


## Enable with lightweight raycast visibility (FoW OFF)
## Disables polygon calculation for better performance
func enable_lightweight() -> void:
	_is_enabled = true
	_mode = VisibilityMode.LIGHTWEIGHT

	# In lightweight mode, disable VisionComponent polygon calculation
	# but keep the component for is_position_in_view() calls
	for character in _characters:
		var game_char := character as GameCharacter
		if game_char and game_char.vision:
			game_char.vision.disable()
			if _fog_of_war_system:
				_fog_of_war_system.unregister_vision(game_char.vision)

	update_visibility()


## Check if system is enabled
func is_enabled() -> bool:
	return _is_enabled


## Get current visibility mode
func get_mode() -> VisibilityMode:
	return _mode


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

	# Check enemy visibility with mode-based dispatch
	for enemy in _get_enemy_characters():
		var is_visible: bool
		var enemy_node3d := enemy as Node3D
		if not enemy_node3d:
			continue
		var enemy_pos: Vector3 = enemy_node3d.global_position

		if _mode == VisibilityMode.FULL_VISION:
			is_visible = _is_position_visible_to_friendlies(enemy_pos)
		else:
			is_visible = _is_position_visible_lightweight(enemy_pos)

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

func _is_position_visible_to_friendlies(world_pos: Vector3) -> bool:
	var pos_2d := Vector2(world_pos.x, world_pos.z)

	for friendly in _get_friendly_characters():
		var game_char := friendly as GameCharacter
		if not game_char or not game_char.vision or not game_char.is_alive:
			continue

		var polygon_3d := game_char.vision.get_visible_polygon()
		if polygon_3d.size() < 3:
			continue

		# Project 3D polygon to 2D (XZ plane)
		var polygon_2d := PackedVector2Array()
		for point in polygon_3d:
			polygon_2d.append(Vector2(point.x, point.z))

		if Geometry2D.is_point_in_polygon(pos_2d, polygon_2d):
			return true

	return false


## Lightweight visibility check using VisionComponent.is_position_in_view()
## Uses single raycast per enemy instead of polygon calculation
func _is_position_visible_lightweight(world_pos: Vector3) -> bool:
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
# Internal - FoW Vision Registration
# ============================================

func _update_all_vision_registration() -> void:
	for character in _characters:
		_update_single_character_vision(character)


func _update_single_character_vision(character: Node) -> void:
	if not _fog_of_war_system:
		return

	var game_char := character as GameCharacter
	if not game_char or not game_char.vision:
		return

	if PlayerState.is_friendly(character):
		# Friendly: Register with FoW first, then enable vision
		# (so the vision_updated signal is received by FoW)
		if _is_enabled:
			_fog_of_war_system.register_vision(game_char.vision)
			game_char.vision.enable()
	else:
		# Enemy: Disable vision and unregister from FoW
		_fog_of_war_system.unregister_vision(game_char.vision)
		game_char.vision.disable()


func _show_all_vision() -> void:
	if not _fog_of_war_system:
		return

	for character in _characters:
		var game_char := character as GameCharacter
		if game_char and game_char.vision:
			game_char.vision.enable()
			_fog_of_war_system.register_vision(game_char.vision)


# ============================================
# Signal Handlers
# ============================================

func _on_player_team_changed(_new_team: GameCharacter.Team) -> void:
	_visibility_cache.clear()
	_update_all_vision_registration()
	update_visibility()


func _on_vision_updated(_visible_points: PackedVector3Array, character: Node) -> void:
	# Only update when friendly vision changes
	if PlayerState.is_friendly(character):
		update_visibility()
