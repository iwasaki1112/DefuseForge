extends Node
## Combat Awareness Component
## Handles individual character enemy detection and tracking
## Automatically detects enemies in vision cone and provides aim direction override

# ============================================
# Signals
# ============================================
signal enemy_spotted(enemy: Node)
signal enemy_lost(enemy: Node)
signal target_changed(new_target: Node, old_target: Node)

# ============================================
# Configuration
# ============================================
const SCAN_INTERVAL: float = 0.05  ## Scan every 50ms (matches EnemyVisibilitySystem)
const TRACKING_TIMEOUT: float = 0.75  ## Time to track last known position after losing sight

# ============================================
# State
# ============================================
var _character: Node = null  # GameCharacter
var _current_target: Node = null
var _last_known_position: Vector3 = Vector3.ZERO
var _time_since_lost: float = 0.0
var _is_tracking_last_known: bool = false
var _scan_timer: float = 0.0
var _ignored_enemies: Array[Node] = []  ## Enemies dismissed by user action (e.g., rotation)


# ============================================
# Setup
# ============================================

## Initialize the component with the owning character
func setup(character: Node) -> void:
	_character = character


# ============================================
# Public API
# ============================================

## Get override look direction (returns ZERO if not tracking enemy)
func get_override_look_direction() -> Vector3:
	if not _character:
		return Vector3.ZERO

	var target_pos: Vector3 = Vector3.ZERO

	if _current_target and is_instance_valid(_current_target):
		# Active target - look at their current position
		target_pos = _current_target.global_position
	elif _is_tracking_last_known:
		# Lost sight but still within timeout - look at last known position
		target_pos = _last_known_position
	else:
		return Vector3.ZERO

	var char_pos: Vector3 = _character.global_position
	var direction: Vector3 = target_pos - char_pos
	direction.y = 0

	if direction.length_squared() < 0.01:
		return Vector3.ZERO

	return direction.normalized()


## Check if currently tracking an enemy
func is_tracking_enemy() -> bool:
	if _current_target and is_instance_valid(_current_target):
		return true
	return _is_tracking_last_known


## Get current target (may be null)
func get_current_target() -> Node:
	return _current_target


## Clear current target (useful when target dies, etc.)
func clear_target() -> void:
	if _current_target:
		var old_target := _current_target
		_current_target = null
		_is_tracking_last_known = false
		_time_since_lost = 0.0
		enemy_lost.emit(old_target)
		target_changed.emit(null, old_target)


## Dismiss current target due to user action (adds to ignore list)
## The enemy will be ignored until it leaves the field of view
func dismiss_current_target() -> void:
	if _current_target and is_instance_valid(_current_target):
		_ignored_enemies.append(_current_target)
	clear_target()


## Process function - call from owner's _physics_process
func process(delta: float) -> void:
	if not _character:
		return

	# Update tracking timeout
	if _is_tracking_last_known:
		_time_since_lost += delta
		if _time_since_lost >= TRACKING_TIMEOUT:
			_is_tracking_last_known = false
			_time_since_lost = 0.0

	# Periodic enemy scan
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL:
		_scan_timer = 0.0
		_scan_for_enemies()


# ============================================
# Internal Methods
# ============================================

## Update ignored enemies list - remove enemies that are no longer in view
func _update_ignored_list() -> void:
	var vision: VisionComponent = _character.get_vision_component() if _character.has_method("get_vision_component") else null
	if not vision:
		return

	var to_remove: Array[Node] = []
	for enemy in _ignored_enemies:
		if not is_instance_valid(enemy):
			to_remove.append(enemy)
			continue
		# Remove from ignore list when enemy leaves field of view
		if not vision.is_position_in_view(enemy.global_position):
			to_remove.append(enemy)

	for enemy in to_remove:
		_ignored_enemies.erase(enemy)


## Scan for enemies in vision cone
func _scan_for_enemies() -> void:
	if not _character:
		return

	var vision: VisionComponent = _character.get_vision_component() if _character.has_method("get_vision_component") else null
	if not vision:
		return

	# Update ignored list (remove enemies that left field of view)
	_update_ignored_list()

	# Check if character is alive
	if _character.has_method("is_alive") or "is_alive" in _character:
		if not _character.is_alive:
			clear_target()
			return

	# Get all enemy characters
	var enemies := _get_enemy_characters()
	if enemies.is_empty():
		_handle_no_enemy_in_sight()
		return

	# Find closest visible enemy
	var closest_enemy: Node = null
	var closest_distance: float = INF

	var char_pos: Vector3 = _character.global_position

	for enemy in enemies:
		# Skip ignored enemies (dismissed by user action)
		if enemy in _ignored_enemies:
			continue

		# Skip dead enemies
		if "is_alive" in enemy and not enemy.is_alive:
			continue

		var enemy_pos: Vector3 = enemy.global_position
		# Check if enemy is in vision cone
		if vision.is_position_in_view(enemy_pos):
			var dist: float = char_pos.distance_to(enemy_pos)
			if dist < closest_distance:
				closest_distance = dist
				closest_enemy = enemy

	if closest_enemy:
		_handle_enemy_in_sight(closest_enemy)
	else:
		_handle_no_enemy_in_sight()


## Handle enemy detection
func _handle_enemy_in_sight(enemy: Node) -> void:
	_is_tracking_last_known = false
	_time_since_lost = 0.0

	# Update last known position
	_last_known_position = enemy.global_position

	if enemy != _current_target:
		var old_target := _current_target
		_current_target = enemy

		if old_target == null:
			enemy_spotted.emit(enemy)

		target_changed.emit(enemy, old_target)


## Handle no enemy in sight
func _handle_no_enemy_in_sight() -> void:
	if _current_target:
		var old_target := _current_target
		_last_known_position = old_target.global_position
		_current_target = null
		_is_tracking_last_known = true
		_time_since_lost = 0.0
		enemy_lost.emit(old_target)
		target_changed.emit(null, old_target)


## Get all enemy characters
func _get_enemy_characters() -> Array[Node]:
	var enemies: Array[Node] = []

	# Use characters group
	var all_characters := get_tree().get_nodes_in_group("characters")

	for character in all_characters:
		if character == _character:
			continue

		# Check if enemy using PlayerState or direct comparison
		var is_enemy := false

		if character is GameCharacter and _character is GameCharacter:
			is_enemy = _character.is_enemy_of(character)
		elif Engine.has_singleton("PlayerState") or has_node("/root/PlayerState"):
			var player_state = get_node_or_null("/root/PlayerState")
			if player_state and player_state.has_method("is_enemy"):
				# If our character is player team's ally, their enemies are our enemies
				if player_state.is_friendly(_character):
					is_enemy = player_state.is_enemy(character)
				else:
					# If our character is enemy team, player's allies are our enemies
					is_enemy = player_state.is_friendly(character)

		if is_enemy:
			enemies.append(character)

	return enemies
