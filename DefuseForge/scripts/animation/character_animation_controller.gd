extends Node
class_name CharacterAnimationController
## Character Animation Controller API
## Provides simple interface for character animations (movement, aiming, combat, death)

# Enums
enum Stance { STAND, CROUCH }
enum Weapon { NONE, RIFLE, PISTOL }
enum HitDirection { FRONT, BACK, LEFT, RIGHT }

# Signals (reserved for future use)

# Export settings
@export_group("Movement Speed")
@export var walk_speed := 2.5
@export var run_speed := 5.0
@export var crouch_speed := 1.5
@export var aim_walk_speed := 2.0
@export var rotation_speed := 15.0

@export_group("Animation Speed Sync")
@export var anim_walk_speed := 1.4
@export var anim_run_speed := 5.5
@export var anim_crouch_speed := 1.2

@export_group("Recoil")
@export var rifle_recoil_strength := 0.08
@export var pistol_recoil_strength := 0.12
@export var rifle_fire_rate := 0.1
@export var pistol_fire_rate := 0.2
@export var recoil_recovery := 10.0

@export_group("Bone Names")
@export var upper_body_root := "mixamorig_Spine1"
@export var spine_bone := "mixamorig_Spine2"

# Internal references
var _model: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _skeleton: Skeleton3D
var _recoil_modifier: SkeletonModifier3D

# State
var _stance := Stance.STAND
var _weapon := Weapon.RIFLE
var _is_aiming := false
var _is_running := false
var _is_dead := false
var _aim_direction := Vector3.FORWARD  # 現在のエイム方向（視界計算用）

# Death animation mapping
const DEATH_ANIMS := {
	"stand_front": "death_from_the_front",
	"stand_back": "death_from_the_back",
	"stand_right": "death_from_right",
	"stand_front_headshot": "death_from_front_headshot",
	"stand_back_headshot": "death_from_back_headshot",
	"crouch_front": "death_crouching_headshot_front",
}

# Blend values
var _input_dir := Vector2.ZERO
var _movement_blend := 0.0
var _crouch_blend := 0.0
var _aim_blend := 0.0
var _weapon_blend := 0.0
var _fire_cooldown := 0.0

# Internal nodes
var _aim_upper_blend: AnimationNodeBlend2

const RecoilModifierScript = preload("res://scripts/modifiers/recoil_modifier.gd")

#region Public API

## Setup the animation controller
func setup(model: Node3D, anim_player: AnimationPlayer) -> void:
	_model = model
	_anim_player = anim_player
	_skeleton = _find_skeleton(model)

	if _skeleton:
		_setup_recoil_modifier()
		# Set AnimationPlayer root_node to model node (parent of Skeleton3D)
		# Animation tracks use paths like "Skeleton3D:bonename"
		if _anim_player:
			_anim_player.root_node = NodePath("..")

	if _anim_player:
		_setup_animation_loops()

	_setup_animation_tree()
	call_deferred("_setup_upper_body_filter")

	# 初期のエイム方向をモデルの前方向に設定
	if _model:
		_aim_direction = _model.global_transform.basis.z
		_aim_direction.y = 0
		if _aim_direction.length_squared() > 0.001:
			_aim_direction = _aim_direction.normalized()
		else:
			_aim_direction = Vector3.FORWARD

## Main update function - call every frame
func update_animation(
	movement_direction: Vector3,
	aim_direction: Vector3,
	is_running: bool,
	delta: float
) -> void:
	if _is_dead:
		return

	# エイム方向を保存（視界計算用）
	if aim_direction.length_squared() > 0.001:
		_aim_direction = aim_direction.normalized()

	_is_running = is_running and _stance != Stance.CROUCH and not _is_aiming

	# Update model rotation
	_update_model_rotation(aim_direction, delta)

	# Calculate strafe blend
	_update_strafe_blend(movement_direction, delta)

	# Update fire cooldown
	_fire_cooldown -= delta

	# Update animation tree parameters
	_update_animation_tree()

## Set stance (STAND or CROUCH)
func set_stance(stance: Stance) -> void:
	_stance = stance


## Get current stance
func get_stance() -> Stance:
	return _stance


## Set weapon type
func set_weapon(weapon: Weapon) -> void:
	_weapon = weapon

## Set aiming state (upper body layer)
func set_aiming(aiming: bool) -> void:
	_is_aiming = aiming

## Trigger fire action (recoil)
func fire() -> void:
	if _fire_cooldown > 0:
		return

	var strength: float
	var fire_rate: float

	match _weapon:
		Weapon.PISTOL:
			strength = pistol_recoil_strength
			fire_rate = pistol_fire_rate
		_:
			strength = rifle_recoil_strength
			fire_rate = rifle_fire_rate

	_fire_cooldown = fire_rate

	if _recoil_modifier:
		_recoil_modifier.recovery_speed = recoil_recovery
		_recoil_modifier.trigger_recoil(strength)

## Get current movement speed based on state
func get_current_speed() -> float:
	if _is_dead:
		return 0.0
	if _stance == Stance.CROUCH:
		return crouch_speed
	elif _is_aiming:
		return aim_walk_speed
	elif _is_running:
		return run_speed
	else:
		return walk_speed

## Check if character is dead
func is_dead() -> bool:
	return _is_dead

## Get current aim direction (for vision calculation)
func get_look_direction() -> Vector3:
	return _aim_direction


## Set aim direction directly (for rotation mode)
func set_look_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		_aim_direction = direction.normalized()
		_aim_direction.y = 0
		# モデルの向きを即座に更新（_update_model_rotationと同じ計算）
		if _model:
			var target_basis := Basis.looking_at(-_aim_direction, Vector3.UP)
			_model.transform.basis = target_basis

## Play death animation
## hit_direction: Direction the hit came FROM (e.g., FRONT means shot from front, falls backward)
## headshot: If true, plays headshot variant if available
func play_death(hit_direction: HitDirection = HitDirection.FRONT, headshot: bool = false) -> void:
	if _is_dead:
		return

	_is_dead = true

	# Stop AnimationTree
	if _anim_tree:
		_anim_tree.active = false

	# Select death animation
	var anim_key := ""
	var stance_prefix := "crouch" if _stance == Stance.CROUCH else "stand"

	match hit_direction:
		HitDirection.FRONT:
			if headshot:
				anim_key = stance_prefix + "_front_headshot"
			else:
				anim_key = stance_prefix + "_front"
		HitDirection.BACK:
			if headshot:
				anim_key = stance_prefix + "_back_headshot"
			else:
				anim_key = stance_prefix + "_back"
		HitDirection.RIGHT:
			anim_key = stance_prefix + "_right"
		HitDirection.LEFT:
			# Use right animation (no left variant available)
			anim_key = stance_prefix + "_right"

	# Get animation name with fallback
	var anim_name: String = DEATH_ANIMS.get(anim_key, "")
	if anim_name.is_empty() or not _anim_player.has_animation(anim_name):
		# Fallback to front death
		anim_name = DEATH_ANIMS.get("stand_front", "death_from_the_front") as String

	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_anim_player.animation_finished.connect(_on_death_animation_finished, CONNECT_ONE_SHOT)

func _on_death_animation_finished(_anim_name: String) -> void:
	pass  # Death animation completed

#endregion

#region Internal Implementation

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null

func _setup_recoil_modifier() -> void:
	_recoil_modifier = RecoilModifierScript.new()
	_recoil_modifier.spine_bone_name = spine_bone
	_skeleton.add_child(_recoil_modifier)

func _setup_animation_loops() -> void:
	var loop_anims := [
		"idle", "idle_aiming", "idle_crouching", "idle_crouching_aiming",
		"pistol_idle",
		"walk_forward", "walk_backward", "walk_left", "walk_right",
		"walk_forward_left", "walk_forward_right", "walk_backward_left", "walk_backward_right",
		"run_forward", "run_backward", "run_left", "run_right",
		"run_forward_left", "run_forward_right", "run_backward_left", "run_backward_right",
		"walk_crouching_forward", "walk_crouching_backward", "walk_crouching_left", "walk_crouching_right",
		"walk_crouching_forward_left", "walk_crouching_forward_right",
		"walk_crouching_backward_left", "walk_crouching_backward_right",
	]

	var anim_lib = _anim_player.get_animation_library("")
	for anim_name in loop_anims:
		if _anim_player.has_animation(anim_name):
			var anim = anim_lib.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR

func _setup_animation_tree() -> void:
	# Create or get AnimationTree
	_anim_tree = _model.get_node_or_null("AnimationTree") as AnimationTree
	if not _anim_tree:
		_anim_tree = AnimationTree.new()
		_anim_tree.name = "AnimationTree"
		_model.get_parent().add_child(_anim_tree)

	var blend_tree := AnimationNodeBlendTree.new()

	# Standing animations
	var walk_blend_space := _create_blend_space({
		Vector2(0, -1): "walk_forward",
		Vector2(0, 1): "walk_backward",
		Vector2(-1, 0): "walk_left",
		Vector2(1, 0): "walk_right",
		Vector2(-0.707, -0.707): "walk_forward_left",
		Vector2(0.707, -0.707): "walk_forward_right",
		Vector2(-0.707, 0.707): "walk_backward_left",
		Vector2(0.707, 0.707): "walk_backward_right",
	})

	var run_blend_space := _create_blend_space({
		Vector2(0, -1): "run_forward",
		Vector2(0, 1): "run_backward",
		Vector2(-1, 0): "run_left",
		Vector2(1, 0): "run_right",
		Vector2(-0.707, -0.707): "run_forward_left",
		Vector2(0.707, -0.707): "run_forward_right",
		Vector2(-0.707, 0.707): "run_backward_left",
		Vector2(0.707, 0.707): "run_backward_right",
	})

	var idle_anim := AnimationNodeAnimation.new()
	idle_anim.animation = "idle"

	# Crouching animations
	var crouch_walk_blend_space := _create_blend_space({
		Vector2(0, -1): "walk_crouching_forward",
		Vector2(0, 1): "walk_crouching_backward",
		Vector2(-1, 0): "walk_crouching_left",
		Vector2(1, 0): "walk_crouching_right",
		Vector2(-0.707, -0.707): "walk_crouching_forward_left",
		Vector2(0.707, -0.707): "walk_crouching_forward_right",
		Vector2(-0.707, 0.707): "walk_crouching_backward_left",
		Vector2(0.707, 0.707): "walk_crouching_backward_right",
	})

	var crouch_idle_anim := AnimationNodeAnimation.new()
	crouch_idle_anim.animation = "idle_crouching"

	# Aiming animations - Rifle
	var aim_rifle_stand := AnimationNodeAnimation.new()
	aim_rifle_stand.animation = "idle_aiming"

	var aim_rifle_crouch := AnimationNodeAnimation.new()
	aim_rifle_crouch.animation = "idle_crouching_aiming"

	# Aiming animations - Pistol
	var aim_pistol_stand := AnimationNodeAnimation.new()
	aim_pistol_stand.animation = "pistol_idle"

	var aim_pistol_crouch := AnimationNodeAnimation.new()
	aim_pistol_crouch.animation = "pistol_idle"

	# TimeScale nodes
	var walk_speed_node := AnimationNodeTimeScale.new()
	var run_speed_node := AnimationNodeTimeScale.new()
	var crouch_speed_node := AnimationNodeTimeScale.new()

	# Blend nodes
	var walk_run_blend := AnimationNodeBlend2.new()
	var standing_idle_move_blend := AnimationNodeBlend2.new()
	var crouch_idle_move_blend := AnimationNodeBlend2.new()
	var stand_crouch_blend := AnimationNodeBlend2.new()

	# Weapon blend nodes
	var weapon_stand_blend := AnimationNodeBlend2.new()
	var weapon_crouch_blend := AnimationNodeBlend2.new()

	# Aiming blend with filter
	var aim_pose_blend := AnimationNodeBlend2.new()
	_aim_upper_blend = AnimationNodeBlend2.new()
	_aim_upper_blend.filter_enabled = true

	# Add nodes
	blend_tree.add_node("Idle", idle_anim, Vector2(-400, -100))
	blend_tree.add_node("WalkBlend", walk_blend_space, Vector2(-600, 100))
	blend_tree.add_node("RunBlend", run_blend_space, Vector2(-600, 300))
	blend_tree.add_node("WalkSpeed", walk_speed_node, Vector2(-400, 100))
	blend_tree.add_node("RunSpeed", run_speed_node, Vector2(-400, 300))
	blend_tree.add_node("WalkRunBlend", walk_run_blend, Vector2(-200, 200))
	blend_tree.add_node("StandingBlend", standing_idle_move_blend, Vector2(0, 0))

	blend_tree.add_node("CrouchIdle", crouch_idle_anim, Vector2(-400, 500))
	blend_tree.add_node("CrouchWalkBlend", crouch_walk_blend_space, Vector2(-600, 700))
	blend_tree.add_node("CrouchSpeed", crouch_speed_node, Vector2(-400, 700))
	blend_tree.add_node("CrouchingBlend", crouch_idle_move_blend, Vector2(0, 600))

	blend_tree.add_node("StandCrouchBlend", stand_crouch_blend, Vector2(200, 300))

	blend_tree.add_node("AimRifleStand", aim_rifle_stand, Vector2(100, 600))
	blend_tree.add_node("AimRifleCrouch", aim_rifle_crouch, Vector2(100, 800))
	blend_tree.add_node("AimPistolStand", aim_pistol_stand, Vector2(300, 600))
	blend_tree.add_node("AimPistolCrouch", aim_pistol_crouch, Vector2(300, 800))

	blend_tree.add_node("WeaponStandBlend", weapon_stand_blend, Vector2(200, 700))
	blend_tree.add_node("WeaponCrouchBlend", weapon_crouch_blend, Vector2(200, 900))

	blend_tree.add_node("AimPoseBlend", aim_pose_blend, Vector2(400, 800))
	blend_tree.add_node("AimUpperBlend", _aim_upper_blend, Vector2(500, 400))

	# Connect nodes
	blend_tree.connect_node("WalkSpeed", 0, "WalkBlend")
	blend_tree.connect_node("RunSpeed", 0, "RunBlend")
	blend_tree.connect_node("WalkRunBlend", 0, "WalkSpeed")
	blend_tree.connect_node("WalkRunBlend", 1, "RunSpeed")
	blend_tree.connect_node("StandingBlend", 0, "Idle")
	blend_tree.connect_node("StandingBlend", 1, "WalkRunBlend")

	blend_tree.connect_node("CrouchSpeed", 0, "CrouchWalkBlend")
	blend_tree.connect_node("CrouchingBlend", 0, "CrouchIdle")
	blend_tree.connect_node("CrouchingBlend", 1, "CrouchSpeed")

	blend_tree.connect_node("StandCrouchBlend", 0, "StandingBlend")
	blend_tree.connect_node("StandCrouchBlend", 1, "CrouchingBlend")

	blend_tree.connect_node("WeaponStandBlend", 0, "AimRifleStand")
	blend_tree.connect_node("WeaponStandBlend", 1, "AimPistolStand")
	blend_tree.connect_node("WeaponCrouchBlend", 0, "AimRifleCrouch")
	blend_tree.connect_node("WeaponCrouchBlend", 1, "AimPistolCrouch")

	blend_tree.connect_node("AimPoseBlend", 0, "WeaponStandBlend")
	blend_tree.connect_node("AimPoseBlend", 1, "WeaponCrouchBlend")

	blend_tree.connect_node("AimUpperBlend", 0, "StandCrouchBlend")
	blend_tree.connect_node("AimUpperBlend", 1, "AimPoseBlend")

	blend_tree.connect_node("output", 0, "AimUpperBlend")

	_anim_tree.tree_root = blend_tree
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.active = true

func _setup_upper_body_filter() -> void:
	if not _skeleton or not _aim_upper_blend:
		return

	var armature = _skeleton.get_parent()
	var armature_name = armature.name if armature else "Armature"
	var skeleton_name = _skeleton.name
	var skeleton_path = "%s/%s" % [armature_name, skeleton_name]

	_add_bone_filter_recursive(skeleton_path, upper_body_root)

func _add_bone_filter_recursive(skeleton_path: String, bone_name: String) -> void:
	var bone_idx = _skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return

	var filter_path = "%s:%s" % [skeleton_path, bone_name]
	_aim_upper_blend.set_filter_path(NodePath(filter_path), true)

	for i in range(_skeleton.get_bone_count()):
		if _skeleton.get_bone_parent(i) == bone_idx:
			var child_name = _skeleton.get_bone_name(i)
			_add_bone_filter_recursive(skeleton_path, child_name)

func _create_blend_space(anims: Dictionary) -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	blend_space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	blend_space.auto_triangles = true
	blend_space.min_space = Vector2(-1, -1)
	blend_space.max_space = Vector2(1, 1)

	for pos in anims:
		var anim_name: String = anims[pos]
		if _anim_player.has_animation(anim_name):
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			blend_space.add_blend_point(anim_node, pos)

	return blend_space

func _update_model_rotation(aim_direction: Vector3, delta: float) -> void:
	if not _model:
		return

	var look_dir := aim_direction
	look_dir.y = 0

	if look_dir.length() > 0.1:
		var target_basis := Basis.looking_at(-look_dir.normalized(), Vector3.UP)
		var target_quat := target_basis.get_rotation_quaternion()
		var current_quat := Quaternion(_model.transform.basis)
		var new_quat := current_quat.slerp(target_quat, rotation_speed * delta)
		_model.transform.basis = Basis(new_quat)

func _update_strafe_blend(movement_direction: Vector3, delta: float) -> void:
	var move_dir := movement_direction
	move_dir.y = 0

	if move_dir.length() > 0.1:
		var char_forward := _model.global_transform.basis.z
		var angle := char_forward.signed_angle_to(move_dir.normalized(), Vector3.UP)
		var target_blend := Vector2(-sin(angle), -cos(angle))

		var blend_speed := 0.3 if target_blend.length() > _input_dir.length() else 0.1
		_input_dir = _input_dir.lerp(target_blend, blend_speed)

		_movement_blend = lerp(_movement_blend, 1.0, 0.1)
	else:
		_movement_blend = lerp(_movement_blend, 0.0, 0.1)
		_input_dir = _input_dir.lerp(Vector2.ZERO, 0.1)

func _update_animation_tree() -> void:
	if not _anim_tree or not _anim_tree.active:
		return

	# Update blend positions
	if _movement_blend > 0.01:
		_anim_tree.set("parameters/WalkBlend/blend_position", _input_dir)
		_anim_tree.set("parameters/RunBlend/blend_position", _input_dir)
		_anim_tree.set("parameters/CrouchWalkBlend/blend_position", _input_dir)

	# Update animation speed
	var current_speed := get_current_speed()
	var walk_scale := current_speed / anim_walk_speed if anim_walk_speed > 0 else 1.0
	var run_scale := current_speed / anim_run_speed if anim_run_speed > 0 else 1.0
	var crouch_scale := current_speed / anim_crouch_speed if anim_crouch_speed > 0 else 1.0

	walk_scale = clamp(walk_scale, 0.5, 2.0)
	run_scale = clamp(run_scale, 0.5, 2.0)
	crouch_scale = clamp(crouch_scale, 0.5, 2.0)

	_anim_tree.set("parameters/WalkSpeed/scale", walk_scale)
	_anim_tree.set("parameters/RunSpeed/scale", run_scale)
	_anim_tree.set("parameters/CrouchSpeed/scale", crouch_scale)

	# Update blend amounts
	var target_run := 1.0 if _is_running else 0.0
	var target_crouch := 1.0 if _stance == Stance.CROUCH else 0.0
	var target_aim := 1.0 if _is_aiming else 0.0
	var target_weapon := 1.0 if _weapon == Weapon.PISTOL else 0.0

	_crouch_blend = lerp(_crouch_blend, target_crouch, 0.15)
	_aim_blend = lerp(_aim_blend, target_aim, 0.2)
	_weapon_blend = lerp(_weapon_blend, target_weapon, 0.2)

	_anim_tree.set("parameters/WalkRunBlend/blend_amount", target_run)
	_anim_tree.set("parameters/StandingBlend/blend_amount", _movement_blend)
	_anim_tree.set("parameters/CrouchingBlend/blend_amount", _movement_blend)
	_anim_tree.set("parameters/StandCrouchBlend/blend_amount", _crouch_blend)

	_anim_tree.set("parameters/WeaponStandBlend/blend_amount", _weapon_blend)
	_anim_tree.set("parameters/WeaponCrouchBlend/blend_amount", _weapon_blend)
	_anim_tree.set("parameters/AimPoseBlend/blend_amount", _crouch_blend)
	_anim_tree.set("parameters/AimUpperBlend/blend_amount", _aim_blend)

#endregion
