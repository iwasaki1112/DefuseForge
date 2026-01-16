extends CharacterBody3D
## Mixamo player with strafe movement using BlendSpace2D
## Supports: Walk, Run, Crouch, Aiming (upper body layer), Weapon switching

const RecoilModifierScript = preload("res://scripts/modifiers/recoil_modifier.gd")

enum WeaponType { RIFLE, PISTOL }

const WALK_SPEED := 2.5
const RUN_SPEED := 5.0
const CROUCH_SPEED := 1.5
const AIM_WALK_SPEED := 2.0
const ROTATION_SPEED := 15.0

const ANIM_WALK_SPEED := 1.4
const ANIM_RUN_SPEED := 5.5
const ANIM_CROUCH_SPEED := 1.2

# Recoil settings per weapon
const RECOIL_SETTINGS := {
	WeaponType.RIFLE: { "strength": 0.08, "recovery": 8.0, "fire_rate": 0.1 },
	WeaponType.PISTOL: { "strength": 0.12, "recovery": 10.0, "fire_rate": 0.2 },
}

# Upper body bones for filter (Mixamo rig - uses underscore format after GLTF import)
const UPPER_BODY_ROOT := "mixamorig_Spine1"
const SPINE_BONE := "mixamorig_Spine2"

@onready var model: Node3D = $CharacterModel
@onready var anim_player: AnimationPlayer = $CharacterModel/AnimationPlayer
@onready var anim_tree: AnimationTree = $AnimationTree

var current_speed := WALK_SPEED
var is_running := false
var is_crouching := false
var is_aiming := false
var aim_position := Vector3.ZERO
var current_weapon := WeaponType.RIFLE

var _input_dir := Vector2.ZERO
var _movement_blend := 0.0
var _crouch_blend := 0.0
var _aim_blend := 0.0
var _weapon_blend := 0.0  # 0 = rifle, 1 = pistol

var ground_plane := Plane(Vector3.UP, 0)
var _skeleton: Skeleton3D
var _aim_upper_blend: AnimationNodeBlend2

# Recoil state
var _fire_cooldown := 0.0
var _recoil_modifier: SkeletonModifier3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	_skeleton = _find_skeleton(model)

	if _skeleton:
		_setup_recoil_modifier()

	if anim_player:
		_setup_animation_loops()

	_setup_animation_tree()

	# Setup filter after tree is ready
	call_deferred("_setup_upper_body_filter")

func _setup_recoil_modifier() -> void:
	_recoil_modifier = RecoilModifierScript.new()
	_recoil_modifier.spine_bone_name = SPINE_BONE
	_skeleton.add_child(_recoil_modifier)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null

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

	var anim_lib = anim_player.get_animation_library("")
	for anim_name in loop_anims:
		if anim_player.has_animation(anim_name):
			var anim = anim_lib.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR

func _setup_animation_tree() -> void:
	if not anim_tree:
		push_error("AnimationTree not found!")
		return

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

	# For now, use same pistol animation for crouch (can add crouch pistol later)
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

	# Weapon blend nodes (rifle vs pistol)
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

	# Rifle aim animations
	blend_tree.add_node("AimRifleStand", aim_rifle_stand, Vector2(100, 600))
	blend_tree.add_node("AimRifleCrouch", aim_rifle_crouch, Vector2(100, 800))

	# Pistol aim animations
	blend_tree.add_node("AimPistolStand", aim_pistol_stand, Vector2(300, 600))
	blend_tree.add_node("AimPistolCrouch", aim_pistol_crouch, Vector2(300, 800))

	# Weapon blends (rifle vs pistol)
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

	# Weapon blends: 0=rifle, 1=pistol
	blend_tree.connect_node("WeaponStandBlend", 0, "AimRifleStand")
	blend_tree.connect_node("WeaponStandBlend", 1, "AimPistolStand")
	blend_tree.connect_node("WeaponCrouchBlend", 0, "AimRifleCrouch")
	blend_tree.connect_node("WeaponCrouchBlend", 1, "AimPistolCrouch")

	# Crouch blend for aim pose
	blend_tree.connect_node("AimPoseBlend", 0, "WeaponStandBlend")
	blend_tree.connect_node("AimPoseBlend", 1, "WeaponCrouchBlend")

	blend_tree.connect_node("AimUpperBlend", 0, "StandCrouchBlend")
	blend_tree.connect_node("AimUpperBlend", 1, "AimPoseBlend")

	blend_tree.connect_node("output", 0, "AimUpperBlend")

	anim_tree.tree_root = blend_tree
	anim_tree.anim_player = anim_player.get_path()
	anim_tree.active = true

func _setup_upper_body_filter() -> void:
	if not _skeleton or not _aim_upper_blend:
		return

	# Get skeleton path relative to model (which is the root for animations)
	var armature = _skeleton.get_parent()
	var armature_name = armature.name if armature else "Armature"
	var skeleton_name = _skeleton.name
	var skeleton_path = "%s/%s" % [armature_name, skeleton_name]

	# Add filter for all upper body bones and their children
	_add_bone_filter_recursive(skeleton_path, UPPER_BODY_ROOT)

func _add_bone_filter_recursive(skeleton_path: String, bone_name: String) -> void:
	var bone_idx = _skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return

	# Add this bone to filter
	var filter_path = "%s:%s" % [skeleton_path, bone_name]
	_aim_upper_blend.set_filter_path(NodePath(filter_path), true)

	# Add all children recursively
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
		if anim_player.has_animation(anim_name):
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			blend_space.add_blend_point(anim_node, pos)

	return blend_space

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CONFINED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	# Weapon switching: 1 = Rifle, 2 = Pistol
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			current_weapon = WeaponType.RIFLE
		elif event.keycode == KEY_2:
			current_weapon = WeaponType.PISTOL

func _physics_process(delta: float) -> void:
	_update_aim_position()

	var world_input := Vector3.ZERO
	world_input.x = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	world_input.z = float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))

	is_crouching = Input.is_key_pressed(KEY_C)
	is_aiming = Input.is_key_pressed(KEY_F)
	is_running = Input.is_key_pressed(KEY_SHIFT) and not is_crouching and not is_aiming

	if is_crouching:
		current_speed = CROUCH_SPEED
	elif is_aiming:
		current_speed = AIM_WALK_SPEED
	elif is_running:
		current_speed = RUN_SPEED
	else:
		current_speed = WALK_SPEED

	var look_dir := aim_position - global_position
	look_dir.y = 0
	if look_dir.length() > 0.1:
		var target_basis := Basis.looking_at(-look_dir.normalized(), Vector3.UP)
		var target_quat := target_basis.get_rotation_quaternion()
		var current_quat := Quaternion(model.transform.basis)
		var new_quat := current_quat.slerp(target_quat, ROTATION_SPEED * delta)
		model.transform.basis = Basis(new_quat)

	var move_dir := world_input.normalized()

	if move_dir.length() > 0.1:
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed

		var char_forward := model.global_transform.basis.z
		var angle := char_forward.signed_angle_to(move_dir, Vector3.UP)
		var target_blend := Vector2(-sin(angle), -cos(angle))

		var blend_speed := 0.3 if target_blend.length() > _input_dir.length() else 0.1
		_input_dir = _input_dir.lerp(target_blend, blend_speed)

		_movement_blend = lerp(_movement_blend, 1.0, 0.1)
	else:
		velocity.x = 0
		velocity.z = 0
		_movement_blend = lerp(_movement_blend, 0.0, 0.1)
		_input_dir = _input_dir.lerp(Vector2.ZERO, 0.1)

	var target_crouch := 1.0 if is_crouching else 0.0
	_crouch_blend = lerp(_crouch_blend, target_crouch, 0.15)

	var target_aim := 1.0 if is_aiming else 0.0
	_aim_blend = lerp(_aim_blend, target_aim, 0.2)

	var target_weapon := 1.0 if current_weapon == WeaponType.PISTOL else 0.0
	_weapon_blend = lerp(_weapon_blend, target_weapon, 0.2)

	_update_animation_tree()
	_update_shooting(delta)

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	move_and_slide()

func _update_aim_position() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		aim_position = intersection

func _update_animation_tree() -> void:
	if not anim_tree or not anim_tree.active:
		return

	if _movement_blend > 0.01:
		anim_tree.set("parameters/WalkBlend/blend_position", _input_dir)
		anim_tree.set("parameters/RunBlend/blend_position", _input_dir)
		anim_tree.set("parameters/CrouchWalkBlend/blend_position", _input_dir)

	var actual_speed := Vector2(velocity.x, velocity.z).length()
	var walk_scale := actual_speed / ANIM_WALK_SPEED if ANIM_WALK_SPEED > 0 else 1.0
	var run_scale := actual_speed / ANIM_RUN_SPEED if ANIM_RUN_SPEED > 0 else 1.0
	var crouch_scale := actual_speed / ANIM_CROUCH_SPEED if ANIM_CROUCH_SPEED > 0 else 1.0

	walk_scale = clamp(walk_scale, 0.5, 2.0)
	run_scale = clamp(run_scale, 0.5, 2.0)
	crouch_scale = clamp(crouch_scale, 0.5, 2.0)

	anim_tree.set("parameters/WalkSpeed/scale", walk_scale)
	anim_tree.set("parameters/RunSpeed/scale", run_scale)
	anim_tree.set("parameters/CrouchSpeed/scale", crouch_scale)

	var run_blend := 1.0 if is_running else 0.0
	anim_tree.set("parameters/WalkRunBlend/blend_amount", run_blend)
	anim_tree.set("parameters/StandingBlend/blend_amount", _movement_blend)
	anim_tree.set("parameters/CrouchingBlend/blend_amount", _movement_blend)
	anim_tree.set("parameters/StandCrouchBlend/blend_amount", _crouch_blend)

	anim_tree.set("parameters/WeaponStandBlend/blend_amount", _weapon_blend)
	anim_tree.set("parameters/WeaponCrouchBlend/blend_amount", _weapon_blend)
	anim_tree.set("parameters/AimPoseBlend/blend_amount", _crouch_blend)
	anim_tree.set("parameters/AimUpperBlend/blend_amount", _aim_blend)

func _update_shooting(delta: float) -> void:
	_fire_cooldown -= delta

	# Space key to shoot (only when aiming)
	if is_aiming and Input.is_key_pressed(KEY_SPACE) and _fire_cooldown <= 0:
		_shoot()

func _shoot() -> void:
	var settings = RECOIL_SETTINGS[current_weapon]
	_fire_cooldown = settings["fire_rate"]
	if _recoil_modifier:
		_recoil_modifier.recovery_speed = settings["recovery"]
		_recoil_modifier.trigger_recoil(settings["strength"])

