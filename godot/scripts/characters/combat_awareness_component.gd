extends Node
class_name CombatAwarenessComponent
## Combat Awareness Component
## Handles individual character enemy detection and tracking
## Automatically detects enemies in vision cone and provides aim direction override

# ============================================
# Signals
# ============================================
signal enemy_spotted(enemy: Node)
signal enemy_lost(enemy: Node)
signal target_changed(new_target: Node, old_target: Node)
signal shot_missed(target: Node, miss_offset: Vector3)
signal critical_hit(target: Node, damage: float)  ## Emitted when a critical hit occurs
signal damage_dealt(attacker: Node, target: Node, damage: float, is_headshot: bool)  ## ダメージを与えた時（ネットワーク同期用）

# ============================================
# Configuration
# ============================================
const SCAN_INTERVAL: float = 0.05  ## Scan every 50ms (matches EnemyVisibilitySystem)
const TRACKING_TIMEOUT: float = 0.75  ## Time to track last known position after losing sight
const CHARACTERS_CACHE_INTERVAL: float = 0.2  ## キャラクターキャッシュ更新間隔（200ms）
const FIRE_INTERVAL: float = 0.5  ## 発砲間隔（500ms）
const MOVEMENT_ACCURACY_PENALTY: float = 0.3  ## Accuracy penalty when moving
const MOVEMENT_THRESHOLD: float = 0.5  ## Velocity threshold to consider "moving"

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
var _firing_enabled: bool = false  ## Whether automatic firing is enabled
var _fire_timer: float = 0.0  ## 発砲タイマー

# キャラクターキャッシュ（GC負荷削減）
var _characters_cache: Array = []
var _characters_cache_timer: float = CHARACTERS_CACHE_INTERVAL  # 初回即時更新

# 命中判定結果（最後の射撃）
var _last_shot_hit: bool = true
var _last_shot_miss_offset: Vector3 = Vector3.ZERO

# バースト射撃状態（Auto Firing Mode用）
var _burst_shots_remaining: int = 0  ## 残りバースト射撃数
var _is_in_burst: bool = false  ## バースト中フラグ
var _burst_interval_timer: float = 0.0  ## バースト内射撃間隔タイマー
var _post_burst_pause_timer: float = 0.0  ## バースト後の待機タイマー
var _current_firing_mode: int = -1  ## 現在の射撃モード（WeaponPreset.FiringMode）
var _last_critical_hit: bool = false  ## 最後の射撃がクリティカルだったか


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


## Enable automatic firing when enemy is in sight
func enable_firing() -> void:
	_firing_enabled = true


## Disable automatic firing
func disable_firing() -> void:
	_firing_enabled = false


## Check if automatic firing is enabled
func is_firing_enabled() -> bool:
	return _firing_enabled


## Get last shot result (hit status, miss offset, and critical hit)
func get_last_shot_result() -> Dictionary:
	return {
		"hit": _last_shot_hit,
		"miss_offset": _last_shot_miss_offset,
		"critical": _last_critical_hit
	}


## Process function - call from owner's _physics_process
func process(delta: float) -> void:
	if not _character:
		return

	# キャラクターキャッシュ更新（200ms間隔）
	_characters_cache_timer += delta
	if _characters_cache_timer >= CHARACTERS_CACHE_INTERVAL:
		_characters_cache_timer = 0.0
		_characters_cache = get_tree().get_nodes_in_group("characters")

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

	# Firing logic (when tracking enemy and firing is enabled)
	if _firing_enabled and _current_target and is_instance_valid(_current_target):
		_process_firing(delta)
	else:
		_reset_firing_state()  # Reset state when not firing


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

	# Clear target immediately if they died
	if _current_target and is_instance_valid(_current_target):
		if "is_alive" in _current_target and not _current_target.is_alive:
			clear_target()

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
		# Check if enemy is visible (FoWテクスチャベースで視覚と同期)
		if _is_enemy_visible(enemy_pos, vision):
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


## 敵が視界内にいるかを判定
## 戦闘ターゲティングでは、このキャラクター自身が見える敵だけを攻撃対象にする
## （FoWテクスチャは全味方の視界を合成しているため、ここでは使用しない）
func _is_enemy_visible(enemy_pos: Vector3, vision: VisionComponent) -> bool:
	# 各キャラクターは自分自身のVisionComponentで判定
	# これにより、壁越しに敵を攻撃することを防ぐ
	if vision:
		return vision.is_position_in_view(enemy_pos)

	return false


## Get all enemy characters
func _get_enemy_characters() -> Array[Node]:
	var enemies: Array[Node] = []

	# キャッシュを使用（GC負荷削減）
	for character in _characters_cache:
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


## Attempt to fire at current target
func _try_fire() -> void:
	if not _character:
		return
	var anim_ctrl = _character.get_anim_controller()
	if anim_ctrl and anim_ctrl.has_method("fire"):
		anim_ctrl.fire()  # Trigger recoil animation
		_apply_damage_to_target()


## Calculate hit chance based on weapon stats, distance, and movement
func _calculate_hit_chance(weapon: WeaponPreset, distance: float) -> float:
	if not weapon:
		return 0.5  # Default 50% if no weapon

	# Base accuracy from weapon
	var base_accuracy: float = weapon.accuracy

	# Apply auto firing mode accuracy modifier if applicable
	if _supports_auto_firing_mode():
		base_accuracy *= _get_current_accuracy_modifier()

	# Spread penalty (random factor)
	var spread_penalty: float = weapon.spread * randf() * 0.5

	# Distance factor
	var distance_factor: float = 1.0
	if distance > weapon.effective_range:
		distance_factor = weapon.effective_range / distance  # e.g., 2x range = 50%

	# Movement penalty
	var movement_penalty: float = 0.0
	if _character is CharacterBody3D:
		var velocity: Vector3 = _character.velocity
		if velocity.length() > MOVEMENT_THRESHOLD:
			movement_penalty = MOVEMENT_ACCURACY_PENALTY

	# Final accuracy calculation
	var final_accuracy: float = (base_accuracy - spread_penalty - movement_penalty) * distance_factor
	return clampf(final_accuracy, 0.05, 1.0)  # Minimum 5% hit chance


## Roll hit check and return true if hit
func _roll_hit_check(weapon: WeaponPreset, distance: float) -> bool:
	var hit_chance: float = _calculate_hit_chance(weapon, distance)
	return randf() < hit_chance


## Calculate miss offset vector (perpendicular to target direction)
func _calculate_miss_offset() -> Vector3:
	if not _current_target or not is_instance_valid(_current_target):
		return Vector3.ZERO

	# Direction from shooter to target
	var to_target: Vector3 = _current_target.global_position - _character.global_position
	to_target.y = 0
	if to_target.length_squared() < 0.01:
		return Vector3.ZERO
	to_target = to_target.normalized()

	# Perpendicular vector to target direction (horizontal)
	var right: Vector3 = to_target.cross(Vector3.UP).normalized()

	# Horizontal offset: left or right with random distance
	var horizontal_offset: float = (randf() * 2.0 - 1.0) * randf_range(0.3, 1.2)

	# Vertical offset (smaller range)
	var vertical_offset: float = randf_range(-0.4, 0.4)

	return right * horizontal_offset + Vector3.UP * vertical_offset


## Apply damage to the current target (with hit check)
func _apply_damage_to_target() -> void:
	if not _current_target or not is_instance_valid(_current_target):
		return
	if not _current_target.has_method("take_damage"):
		return

	var damage: float = 10.0  # Default damage
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if weapon and "damage" in weapon:
		damage = weapon.damage

	# Calculate distance to target
	var distance: float = _character.global_position.distance_to(_current_target.global_position)

	# Perform hit check
	var is_hit: bool = _roll_hit_check(weapon, distance)

	# Store result for bullet trail
	_last_shot_hit = is_hit

	if is_hit:
		# Hit - apply damage (with critical hit check)
		_last_shot_miss_offset = Vector3.ZERO
		var final_damage: float = damage
		var critical_rate: float = _get_current_critical_rate()
		_last_critical_hit = randf() < critical_rate
		if _last_critical_hit:
			final_damage *= 2.0  # Critical hit: 2x damage
			critical_hit.emit(_current_target, final_damage)
		_current_target.take_damage(final_damage, _character, _last_critical_hit)
		# ネットワーク同期用シグナル
		damage_dealt.emit(_character, _current_target, final_damage, _last_critical_hit)
	else:
		# Miss - calculate miss offset and emit signal
		_last_shot_miss_offset = _calculate_miss_offset()
		_last_critical_hit = false
		shot_missed.emit(_current_target, _last_shot_miss_offset)


# ============================================
# Auto Firing Mode System
# ============================================

## Check if weapon supports auto firing mode
func _supports_auto_firing_mode() -> bool:
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon:
		return false
	if not weapon.auto_firing_mode_enabled:
		return false
	# Only RIFLE and SMG support auto firing mode
	return weapon.category == WeaponPreset.WeaponCategory.RIFLE or weapon.category == WeaponPreset.WeaponCategory.SMG


## Get current range type based on distance (0=CQB, 1=Medium, 2=Long)
func _get_range_type(distance: float) -> int:
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon:
		return 2  # Default to long range
	if distance <= weapon.cqb_max_distance:
		return 0  # CQB
	elif distance <= weapon.medium_max_distance:
		return 1  # Medium
	else:
		return 2  # Long


## Get firing mode for current range
func _get_current_firing_mode() -> int:
	if not _current_target or not is_instance_valid(_current_target):
		return WeaponPreset.FiringMode.SINGLE
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon:
		return WeaponPreset.FiringMode.SINGLE
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_firing_mode
		1: return weapon.medium_firing_mode
		_: return weapon.long_firing_mode


## Get shots per burst for current range
func _get_current_shots_per_burst() -> int:
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 1
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_shots_per_burst
		1: return weapon.medium_shots_per_burst
		_: return weapon.long_shots_per_burst


## Get burst interval for current range
func _get_current_burst_interval() -> float:
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 0.1
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_burst_interval
		1: return weapon.medium_burst_interval
		_: return weapon.long_burst_interval


## Get pause after burst for current range
func _get_current_pause_after_burst() -> float:
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 0.5
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_pause_after_burst
		1: return weapon.medium_pause_after_burst
		_: return weapon.long_pause_after_burst


## Get accuracy modifier for current range
func _get_current_accuracy_modifier() -> float:
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 1.0
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_accuracy_modifier
		1: return weapon.medium_accuracy_modifier
		_: return weapon.long_accuracy_modifier


## Get critical hit rate for current range
func _get_current_critical_rate() -> float:
	if not _supports_auto_firing_mode():
		return 0.0  # No critical hits for non-auto firing mode weapons
	var weapon: WeaponPreset = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 0.0
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_critical_rate
		1: return weapon.medium_critical_rate
		_: return weapon.long_critical_rate


## Process firing state machine
func _process_firing(delta: float) -> void:
	# Use legacy firing for non-auto firing mode weapons
	if not _supports_auto_firing_mode():
		_process_legacy_firing(delta)
		return

	# Handle post-burst pause
	if _post_burst_pause_timer > 0.0:
		_post_burst_pause_timer -= delta
		if _post_burst_pause_timer <= 0.0:
			_post_burst_pause_timer = 0.0
			# Start new burst after pause
			_start_burst()
		return

	# Handle burst in progress
	if _is_in_burst:
		_burst_interval_timer -= delta
		if _burst_interval_timer <= 0.0:
			_fire_burst_shot()
		return

	# Not in burst and no pause - start new burst
	_start_burst()


## Legacy firing for pistols and other non-auto mode weapons
func _process_legacy_firing(delta: float) -> void:
	_fire_timer += delta
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_try_fire()


## Start a new burst sequence
func _start_burst() -> void:
	_current_firing_mode = _get_current_firing_mode()
	var shots: int = _get_current_shots_per_burst()

	if _current_firing_mode == WeaponPreset.FiringMode.FULL_AUTO and shots == 0:
		# Continuous fire mode - fire immediately and continue
		_is_in_burst = true
		_burst_shots_remaining = 999999  # Effectively unlimited
		_fire_burst_shot()
	elif _current_firing_mode == WeaponPreset.FiringMode.SINGLE or shots == 1:
		# Single shot mode
		_is_in_burst = false
		_try_fire()
		_post_burst_pause_timer = _get_current_pause_after_burst()
	else:
		# Burst mode
		_is_in_burst = true
		_burst_shots_remaining = shots
		_fire_burst_shot()


## Fire a single shot within a burst
func _fire_burst_shot() -> void:
	if not _current_target or not is_instance_valid(_current_target):
		_end_burst()
		return

	_try_fire()
	_burst_shots_remaining -= 1

	if _burst_shots_remaining <= 0 or (_current_firing_mode != WeaponPreset.FiringMode.FULL_AUTO and _burst_shots_remaining <= 0):
		_end_burst()
	else:
		# Schedule next shot in burst
		_burst_interval_timer = _get_current_burst_interval()


## End the current burst
func _end_burst() -> void:
	_is_in_burst = false
	_burst_shots_remaining = 0
	_burst_interval_timer = 0.0

	# Check if we should continue with full auto
	if _current_firing_mode == WeaponPreset.FiringMode.FULL_AUTO:
		var shots: int = _get_current_shots_per_burst()
		if shots == 0:
			# Continuous fire - very short pause
			_post_burst_pause_timer = _get_current_burst_interval()
		else:
			_post_burst_pause_timer = _get_current_pause_after_burst()
	else:
		_post_burst_pause_timer = _get_current_pause_after_burst()


## Reset all firing state
func _reset_firing_state() -> void:
	_fire_timer = 0.0
	_is_in_burst = false
	_burst_shots_remaining = 0
	_burst_interval_timer = 0.0
	_post_burst_pause_timer = 0.0
	_current_firing_mode = -1
