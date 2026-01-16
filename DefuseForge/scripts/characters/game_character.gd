extends CharacterBody3D
class_name GameCharacter
## Character management class
## Provides HP, death state, and team management
## Works with CharacterAnimationController for animations

# ============================================
# Team Definition
# ============================================
enum Team { NONE = 0, COUNTER_TERRORIST = 1, TERRORIST = 2 }

# ============================================
# Signals (reserved for future use)
# ============================================

# ============================================
# Export Settings
# ============================================
@export_group("HP Settings")
@export var max_health: float = 100.0

@export_group("Team Settings")
@export var team: Team = Team.NONE

# ============================================
# State
# ============================================
var current_health: float = 100.0
var is_alive: bool = true

# ============================================
# References
# ============================================
var anim_ctrl: Node = null  # CharacterAnimationController
var vision: VisionComponent = null  # VisionComponent for FoW

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	current_health = max_health
	is_alive = true
	add_to_group("characters")

# ============================================
# HP API
# ============================================

## Take damage
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if not is_alive:
		return

	current_health = max(0.0, current_health - amount)

	if current_health <= 0.0:
		_die(attacker, is_headshot)

## Heal
func heal(amount: float) -> void:
	if not is_alive:
		return
	current_health = min(max_health, current_health + amount)

## Get health ratio (0.0 - 1.0)
func get_health_ratio() -> float:
	return current_health / max_health if max_health > 0 else 0.0

## Reset health
func reset_health() -> void:
	current_health = max_health
	is_alive = true
	# Re-enable vision on respawn
	if vision:
		vision.enable()

# ============================================
# Team API
# ============================================

## Check if target is enemy team
func is_enemy_of(other: GameCharacter) -> bool:
	if other == null:
		return false
	if team == Team.NONE or other.team == Team.NONE:
		return false
	return team != other.team

# ============================================
# Animation Controller API
# ============================================

## Set CharacterAnimationController
func set_anim_controller(controller: Node) -> void:
	anim_ctrl = controller

## Get CharacterAnimationController
func get_anim_controller() -> Node:
	return anim_ctrl

# ============================================
# Stance API
# ============================================

## Check if character is crouching
func is_crouching() -> bool:
	if anim_ctrl and anim_ctrl.has_method("get_stance"):
		return anim_ctrl.get_stance() == 1  # Stance.CROUCH
	return false


## Toggle crouch state
func toggle_crouch() -> void:
	if not anim_ctrl:
		return
	if not anim_ctrl.has_method("set_stance") or not anim_ctrl.has_method("get_stance"):
		return

	var current = anim_ctrl.get_stance()
	# Stance.STAND = 0, Stance.CROUCH = 1
	anim_ctrl.set_stance(0 if current == 1 else 1)


# ============================================
# Vision Component API
# ============================================

## Set VisionComponent
func set_vision_component(component: VisionComponent) -> void:
	vision = component

## Get VisionComponent
func get_vision_component() -> VisionComponent:
	return vision

## Setup vision component (auto-create if not exists)
func setup_vision(fov: float = 90.0, view_dist: float = 15.0) -> VisionComponent:
	if vision == null:
		vision = VisionComponent.new()
		vision.name = "VisionComponent"
		add_child(vision)

	vision.set_fov(fov)
	vision.set_view_distance(view_dist)
	return vision

# ============================================
# Death Processing
# ============================================

func _die(killer: Node3D = null, is_headshot: bool = false) -> void:
	is_alive = false

	# Play death animation via CharacterAnimationController
	if anim_ctrl and anim_ctrl.has_method("play_death"):
		var hit_dir := _calculate_hit_direction(killer)
		anim_ctrl.play_death(hit_dir, is_headshot)

	# Disable vision on death
	if vision:
		vision.disable()

	# Disable collision
	_disable_collision()

## Calculate HitDirection from attacker position
func _calculate_hit_direction(attacker: Node3D) -> int:
	if attacker == null:
		return 0  # FRONT

	var to_attacker := (attacker.global_position - global_position).normalized()
	to_attacker.y = 0

	var forward := global_transform.basis.z  # +Z forward
	forward.y = 0
	forward = forward.normalized()

	var angle := rad_to_deg(forward.signed_angle_to(to_attacker, Vector3.UP))

	# CharacterAnimationController.HitDirection
	# FRONT = 0, BACK = 1, LEFT = 2, RIGHT = 3
	if abs(angle) < 45:
		return 0  # FRONT
	elif abs(angle) > 135:
		return 1  # BACK
	elif angle < 0:
		return 2  # LEFT
	else:
		return 3  # RIGHT

func _disable_collision() -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		collision_shape.disabled = true
