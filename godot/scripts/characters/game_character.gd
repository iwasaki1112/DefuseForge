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
var combat_awareness: Node = null  # CombatAwarenessComponent for enemy tracking
var current_weapon: Resource = null  # WeaponPreset
var _weapon_attachment: BoneAttachment3D = null  # 武器アタッチメントノード
var _weapon_model: Node3D = null  # 現在の武器モデル

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
# Combat Awareness API
# ============================================

## Setup combat awareness component (auto-create if not exists)
func setup_combat_awareness() -> Node:
	if combat_awareness == null:
		var CombatAwarenessScript = preload("res://scripts/characters/combat_awareness_component.gd")
		combat_awareness = Node.new()
		combat_awareness.set_script(CombatAwarenessScript)
		combat_awareness.name = "CombatAwarenessComponent"
		add_child(combat_awareness)
		combat_awareness.setup(self)
	return combat_awareness


## Get CombatAwarenessComponent
func get_combat_awareness() -> Node:
	return combat_awareness

# ============================================
# Weapon API
# ============================================

## Find Skeleton3D recursively in node tree
func _find_skeleton_in_node(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton_in_node(child)
		if result:
			return result
	return null


## Create or get BoneAttachment3D for weapon
func _ensure_weapon_attachment() -> BoneAttachment3D:
	if _weapon_attachment:
		return _weapon_attachment

	var model = get_node_or_null("CharacterModel")
	if not model:
		print("GameCharacter: CharacterModel not found")
		return null

	var skeleton = _find_skeleton_in_node(model)
	if not skeleton:
		push_warning("GameCharacter: Skeleton not found")
		return null

	print("GameCharacter: Found skeleton: ", skeleton.name)
	print("GameCharacter: Bone count: ", skeleton.get_bone_count())

	var bone_idx = skeleton.find_bone("mixamorig_RightHand")
	if bone_idx < 0:
		# Try alternative bone names
		print("GameCharacter: mixamorig_RightHand not found, listing bones:")
		for i in range(min(skeleton.get_bone_count(), 20)):
			print("  Bone %d: %s" % [i, skeleton.get_bone_name(i)])
		push_warning("GameCharacter: mixamorig_RightHand bone not found")
		return null

	print("GameCharacter: Found RightHand bone at index ", bone_idx)

	_weapon_attachment = BoneAttachment3D.new()
	_weapon_attachment.name = "WeaponAttachment"
	_weapon_attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(_weapon_attachment)

	return _weapon_attachment


## Attach weapon model to right hand
func _attach_weapon_model(weapon: Resource) -> void:
	# Remove old weapon model
	if _weapon_model:
		_weapon_model.queue_free()
		_weapon_model = null

	if not weapon or not weapon.model_scene:
		print("GameCharacter: No model_scene for weapon")
		return

	var attachment = _ensure_weapon_attachment()
	if not attachment:
		return

	_weapon_model = weapon.model_scene.instantiate()
	_weapon_model.name = "WeaponModel"
	attachment.add_child(_weapon_model)

	# Mixamo skeleton is 0.01 scale, so weapon needs 100x scale
	_weapon_model.scale = Vector3.ONE * 100.0

	# Apply offset from WeaponPreset (use defaults for Mixamo if not set)
	if weapon.attach_offset != Vector3.ZERO:
		_weapon_model.position = weapon.attach_offset
	else:
		# Default offset for Mixamo right hand
		_weapon_model.position = Vector3(1, 7, 2)

	if weapon.attach_rotation != Vector3.ZERO:
		_weapon_model.rotation_degrees = weapon.attach_rotation
	else:
		# Default rotation for Mixamo right hand
		_weapon_model.rotation_degrees = Vector3(-79, -66, -28)

	print("GameCharacter: Attached weapon model: ", weapon.display_name)


## Equip a weapon from WeaponPreset
## Applies weapon type and recoil settings to CharacterAnimationController
## Also attaches weapon model to right hand bone
func equip_weapon(weapon: Resource) -> void:
	current_weapon = weapon

	# Attach weapon model to right hand
	_attach_weapon_model(weapon)

	if not anim_ctrl:
		return

	# Convert WeaponCategory to CharacterAnimationController.Weapon
	# WeaponCategory: RIFLE=0, PISTOL=1, SMG=2, SHOTGUN=3, SNIPER=4
	# Weapon: NONE=0, RIFLE=1, PISTOL=2
	var weapon_type: int = 1  # Default to RIFLE
	if weapon.category == 1:  # PISTOL
		weapon_type = 2

	if anim_ctrl.has_method("set_weapon"):
		anim_ctrl.set_weapon(weapon_type)

	# Apply recoil settings directly to controller
	if "rifle_recoil_strength" in anim_ctrl:
		# Apply weapon's recoil to both rifle/pistol slots based on category
		if weapon.category == 1:  # PISTOL
			anim_ctrl.pistol_recoil_strength = weapon.recoil_strength
		else:
			anim_ctrl.rifle_recoil_strength = weapon.recoil_strength

	if "recoil_recovery" in anim_ctrl:
		anim_ctrl.recoil_recovery = weapon.recoil_recovery

## Get current weapon
func get_current_weapon() -> Resource:
	return current_weapon

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

	# Clear combat awareness target on death
	if combat_awareness and combat_awareness.has_method("clear_target"):
		combat_awareness.clear_target()

	# Make corpse passable by other characters but keep ground collision
	_make_corpse_passable()

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

## Make corpse passable by other characters while keeping ground collision
func _make_corpse_passable() -> void:
	# Set collision_layer to 0 so other characters don't collide with this corpse
	# Keep collision_mask unchanged so corpse still detects ground
	collision_layer = 0
