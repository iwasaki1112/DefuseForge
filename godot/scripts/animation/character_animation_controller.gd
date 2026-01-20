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
@export var walk_speed := 2.0
@export var run_speed := 5.0
@export var crouch_speed := 1.5
@export var rotation_speed := 15.0

@export_group("Recoil")
@export var rifle_recoil_strength := 0.08
@export var pistol_recoil_strength := 0.12
@export var rifle_fire_rate := 0.1
@export var pistol_fire_rate := 0.2
@export var recoil_recovery := 10.0

@export_group("Root Motion")
@export var use_root_motion: bool = true
@export var root_bone_name: String = "mixamorig_Hips"

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
var _is_running := false
var _is_dead := false
var _aim_direction := Vector3.FORWARD  # 現在のエイム方向（視界計算用）

# Animation visual speeds at 1x playback (2-second/60-frame animations)
# Different directions have different stride lengths
const ANIM_SPEED_FORWARD := 2.0   # Forward/backward: large strides
const ANIM_SPEED_STRAFE := 1.2    # Left/right: small strides
const ANIM_SPEED_DIAGONAL := 1.6  # Diagonal: medium strides
const ANIM_REF_RUN := 5.5         # Sprint animation
const ANIM_REF_CROUCH := 1.5      # Crouch walk

# Death animation name
const DEATH_ANIM := "death"

# Blend values
var _input_dir := Vector2(0, -1)  # 前方向で初期化
var _movement_blend := 0.0
var _crouch_blend := 0.0
var _weapon_blend := 0.0
var _fire_cooldown := 0.0
var _current_walk_state := "rifle_walk_forward"  # 現在のwalkステート

# 8方向ベクトルとステート名のマッピング
const DIR8_VECTORS := [
	Vector2(0, -1),       # Forward
	Vector2(0, 1),        # Backward
	Vector2(-1, 0),       # Left
	Vector2(1, 0),        # Right
	Vector2(-0.707, -0.707),  # Forward-Left
	Vector2(0.707, -0.707),   # Forward-Right
	Vector2(-0.707, 0.707),   # Backward-Left
	Vector2(0.707, 0.707),    # Backward-Right
]

const DIR8_STATE_NAMES := [
	"walk_forward",
	"walk_backward",
	"walk_left",
	"walk_right",
	"walk_forward_left",
	"walk_forward_right",
	"walk_backward_left",
	"walk_backward_right",
]

# Internal nodes

const RecoilModifierScript = preload("res://scripts/modifiers/recoil_modifier.gd")

#region Public API

## Setup the animation controller
func setup(model: Node3D, anim_player: AnimationPlayer) -> void:
	_model = model
	_anim_player = anim_player
	_skeleton = _find_skeleton(model)

	if _skeleton:
		_setup_recoil_modifier()
		# AnimationPlayer root_node はデフォルト（自身の親）のままにする
		# GLBインポート時のトラックパスと一致させるため

	if _anim_player:
		_setup_animation_loops()

	_setup_animation_tree()
	_update_weapon_idle_blend()

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

	_is_running = is_running and _stance != Stance.CROUCH

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
	_update_weapon_idle_blend()

## Update weapon-based idle blend (rifle uses aiming pose, pistol uses normal idle)
func _update_weapon_idle_blend() -> void:
	if not _anim_tree:
		return
	# 0 = rifle idle (aiming pose), 1 = normal idle
	var blend_value := 1.0 if _weapon != Weapon.RIFLE else 0.0
	_anim_tree.set("parameters/WeaponIdleStandBlend/blend_amount", blend_value)
	_anim_tree.set("parameters/WeaponIdleCrouchBlend/blend_amount", blend_value)

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

## Get current movement speed based on state and direction
## Returns the animation's visual speed for the current blend direction
func get_current_speed() -> float:
	if _is_dead:
		return 0.0
	if _stance == Stance.CROUCH:
		return crouch_speed
	elif _is_running:
		return run_speed
	else:
		# Calculate direction-based speed from current blend position
		return _get_directional_anim_speed()

## Calculate animation visual speed based on blend direction
func _get_directional_anim_speed() -> float:
	if _input_dir.length() < 0.01:
		return ANIM_SPEED_FORWARD  # Default when idle

	# Normalize input direction
	var dir := _input_dir.normalized()

	# Calculate weights for forward/backward vs strafe
	var forward_weight := absf(dir.y)  # Y = forward/backward
	var strafe_weight := absf(dir.x)   # X = left/right

	# Blend between forward and strafe speeds based on direction
	# Pure forward/backward: forward_weight=1, strafe_weight=0
	# Pure strafe: forward_weight=0, strafe_weight=1
	# Diagonal: both ~0.707
	var speed := ANIM_SPEED_FORWARD * forward_weight + ANIM_SPEED_STRAFE * strafe_weight

	# Normalize for diagonal (weights sum to ~1.414 for diagonal)
	var total_weight := forward_weight + strafe_weight
	if total_weight > 0.01:
		speed /= total_weight

	return speed

## Check if character is dead
func is_dead() -> bool:
	return _is_dead


## Get root motion position delta for this frame (world space)
## Returns Vector3.ZERO if not moving (idle) to prevent drift
func get_root_motion_delta() -> Vector3:
	if not _anim_tree or not use_root_motion or _is_dead:
		return Vector3.ZERO

	var local_motion := _anim_tree.get_root_motion_position()

	# Idleドリフト対策: 微小な移動は無視
	if local_motion.length_squared() < 0.0001:
		return Vector3.ZERO

	# モデルの回転を適用してワールド座標に変換
	if _model:
		local_motion = _model.global_transform.basis * local_motion

	return local_motion


## Set AnimationTree active state
func set_animation_tree_active(active: bool) -> void:
	if _anim_tree:
		_anim_tree.active = active

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
## hit_direction: Direction the hit came FROM (reserved for future use)
## headshot: Reserved for future use
func play_death(_hit_direction: HitDirection = HitDirection.FRONT, _headshot: bool = false) -> void:
	if _is_dead:
		return

	_is_dead = true

	# Stop AnimationTree
	if _anim_tree:
		_anim_tree.active = false

	# Play death animation
	if _anim_player.has_animation(DEATH_ANIM):
		_anim_player.play(DEATH_ANIM)
		_anim_player.animation_finished.connect(_on_death_animation_finished, CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Death animation not found: %s" % DEATH_ANIM)

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
		# Idle animations
		"rifle_idle", "rifle_idle_crouching",
		"pistol_idle", "pistol_idle_crouching",
		# Rifle walk
		"rifle_walk_forward", "rifle_walk_backward", "rifle_walk_left", "rifle_walk_right",
		"rifle_walk_forward_left", "rifle_walk_forward_right", "rifle_walk_backward_left", "rifle_walk_backward_right",
		# Rifle sprint
		"rifle_sprint",
		# Pistol walk
		"pistol_walk_forward", "pistol_walk_backward", "pistol_walk_left", "pistol_walk_right",
		"pistol_walk_forward_left", "pistol_walk_forward_right", "pistol_walk_backward_left", "pistol_walk_backward_right",
		# Pistol sprint
		"pistol_sprint",
		# Crouching (TODO: add rifle_/pistol_ prefix)
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
	# Create or get AnimationTree (must be sibling of AnimationPlayer for track resolution)
	_anim_tree = _model.get_node_or_null("AnimationTree") as AnimationTree
	if not _anim_tree:
		_anim_tree = AnimationTree.new()
		_anim_tree.name = "AnimationTree"
		_model.add_child(_anim_tree)

	var blend_tree := AnimationNodeBlendTree.new()

	# Standing animations - Rifle (StateMachine for instant direction switching)
	var rifle_walk_sm := _create_walk_state_machine("rifle")

	# Sprint animations (single animation, not BlendSpace)
	var rifle_sprint_anim := AnimationNodeAnimation.new()
	rifle_sprint_anim.animation = _get_animation_with_fallback("rifle_sprint", "rifle_walk_forward")

	var pistol_sprint_anim := AnimationNodeAnimation.new()
	pistol_sprint_anim.animation = _get_animation_with_fallback("pistol_sprint", "rifle_sprint")

	# Standing animations - Pistol (StateMachine with fallback to rifle)
	var pistol_walk_sm := _create_walk_state_machine("pistol")

	# Weapon walk/run blend nodes
	var walk_weapon_blend := AnimationNodeBlend2.new()
	var run_weapon_blend := AnimationNodeBlend2.new()

	var idle_anim := AnimationNodeAnimation.new()
	idle_anim.animation = _get_animation_with_fallback("pistol_idle", "rifle_idle")

	# Rifle idle (standing)
	var rifle_idle_anim := AnimationNodeAnimation.new()
	rifle_idle_anim.animation = _get_animation_with_fallback("rifle_idle", "rifle_walk_forward")

	# Crouching animations (BlendSpace2D - less frequent direction changes)
	var crouch_walk_blend_space := _create_crouch_blend_space({
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
	crouch_idle_anim.animation = _get_animation_with_fallback("pistol_idle_crouching", "rifle_idle_crouching", "rifle_idle")

	# Rifle idle (crouching)
	var rifle_crouch_idle_anim := AnimationNodeAnimation.new()
	rifle_crouch_idle_anim.animation = _get_animation_with_fallback("rifle_idle_crouching", "rifle_idle")

	# TimeScale nodes
	var walk_speed_node := AnimationNodeTimeScale.new()
	var run_speed_node := AnimationNodeTimeScale.new()
	var crouch_speed_node := AnimationNodeTimeScale.new()

	# Blend nodes
	var walk_run_blend := AnimationNodeBlend2.new()
	var standing_idle_move_blend := AnimationNodeBlend2.new()
	var crouch_idle_move_blend := AnimationNodeBlend2.new()
	var stand_crouch_blend := AnimationNodeBlend2.new()

	# Weapon idle blend nodes (switches idle based on weapon type)
	var weapon_idle_stand_blend := AnimationNodeBlend2.new()
	var weapon_idle_crouch_blend := AnimationNodeBlend2.new()

	# Add nodes
	blend_tree.add_node("Idle", idle_anim, Vector2(-600, -200))
	blend_tree.add_node("RifleIdle", rifle_idle_anim, Vector2(-600, -50))
	blend_tree.add_node("WeaponIdleStandBlend", weapon_idle_stand_blend, Vector2(-400, -100))
	# Rifle walk/sprint (StateMachine for instant direction switching)
	blend_tree.add_node("RifleWalkSM", rifle_walk_sm, Vector2(-800, 100))
	blend_tree.add_node("RifleSprint", rifle_sprint_anim, Vector2(-800, 300))
	# Pistol walk/sprint (StateMachine for instant direction switching)
	blend_tree.add_node("PistolWalkSM", pistol_walk_sm, Vector2(-800, 150))
	blend_tree.add_node("PistolSprint", pistol_sprint_anim, Vector2(-800, 350))
	# Weapon-based walk/run blend
	blend_tree.add_node("WalkWeaponBlend", walk_weapon_blend, Vector2(-600, 100))
	blend_tree.add_node("RunWeaponBlend", run_weapon_blend, Vector2(-600, 300))
	blend_tree.add_node("WalkSpeed", walk_speed_node, Vector2(-400, 100))
	blend_tree.add_node("RunSpeed", run_speed_node, Vector2(-400, 300))
	blend_tree.add_node("WalkRunBlend", walk_run_blend, Vector2(-200, 200))
	blend_tree.add_node("StandingBlend", standing_idle_move_blend, Vector2(0, 0))

	blend_tree.add_node("CrouchIdle", crouch_idle_anim, Vector2(-600, 450))
	blend_tree.add_node("RifleCrouchIdle", rifle_crouch_idle_anim, Vector2(-600, 550))
	blend_tree.add_node("WeaponIdleCrouchBlend", weapon_idle_crouch_blend, Vector2(-400, 500))
	blend_tree.add_node("CrouchWalkBlend", crouch_walk_blend_space, Vector2(-600, 700))
	blend_tree.add_node("CrouchSpeed", crouch_speed_node, Vector2(-400, 700))
	blend_tree.add_node("CrouchingBlend", crouch_idle_move_blend, Vector2(0, 600))

	blend_tree.add_node("StandCrouchBlend", stand_crouch_blend, Vector2(200, 300))

	# Connect nodes
	# Weapon-based idle blend (0 = rifle idle, 1 = normal idle; controlled by weapon type)
	blend_tree.connect_node("WeaponIdleStandBlend", 0, "RifleIdle")
	blend_tree.connect_node("WeaponIdleStandBlend", 1, "Idle")
	blend_tree.connect_node("WeaponIdleCrouchBlend", 0, "RifleCrouchIdle")
	blend_tree.connect_node("WeaponIdleCrouchBlend", 1, "CrouchIdle")

	# Connect weapon-based walk/sprint (0 = rifle, 1 = pistol)
	blend_tree.connect_node("WalkWeaponBlend", 0, "RifleWalkSM")
	blend_tree.connect_node("WalkWeaponBlend", 1, "PistolWalkSM")
	blend_tree.connect_node("RunWeaponBlend", 0, "RifleSprint")
	blend_tree.connect_node("RunWeaponBlend", 1, "PistolSprint")
	blend_tree.connect_node("WalkSpeed", 0, "WalkWeaponBlend")
	blend_tree.connect_node("RunSpeed", 0, "RunWeaponBlend")
	blend_tree.connect_node("WalkRunBlend", 0, "WalkSpeed")
	blend_tree.connect_node("WalkRunBlend", 1, "RunSpeed")
	blend_tree.connect_node("StandingBlend", 0, "WeaponIdleStandBlend")
	blend_tree.connect_node("StandingBlend", 1, "WalkRunBlend")

	blend_tree.connect_node("CrouchSpeed", 0, "CrouchWalkBlend")
	blend_tree.connect_node("CrouchingBlend", 0, "WeaponIdleCrouchBlend")
	blend_tree.connect_node("CrouchingBlend", 1, "CrouchSpeed")

	blend_tree.connect_node("StandCrouchBlend", 0, "StandingBlend")
	blend_tree.connect_node("StandCrouchBlend", 1, "CrouchingBlend")

	blend_tree.connect_node("output", 0, "StandCrouchBlend")

	_anim_tree.tree_root = blend_tree
	# Godot 4.x: anim_player is deprecated, but still works
	# AnimationMixer (parent class) root_node must be set for track resolution
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.root_node = NodePath("..")  # Point to CharacterModel for track resolution
	_anim_tree.active = true

	# Initialize all blend parameters to default values
	_anim_tree.set("parameters/StandCrouchBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/StandingBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/CrouchingBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/WalkRunBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/WalkWeaponBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/RunWeaponBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/WeaponIdleStandBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/WeaponIdleCrouchBlend/blend_amount", 0.0)
	_anim_tree.set("parameters/WalkSpeed/scale", 1.0)
	_anim_tree.set("parameters/RunSpeed/scale", 1.0)
	_anim_tree.set("parameters/CrouchSpeed/scale", 1.0)
	# Crouch用BlendSpace2Dの初期位置
	_anim_tree.set("parameters/CrouchWalkBlend/blend_position", Vector2(0, -1))

	print("[CharAnim] AnimationTree setup complete:")
	print("[CharAnim]   tree_root: %s" % _anim_tree.tree_root)
	print("[CharAnim]   anim_player: %s" % _anim_tree.anim_player)
	print("[CharAnim]   root_node: %s" % _anim_tree.root_node)
	print("[CharAnim]   active: %s" % _anim_tree.active)

	# Process mode: PHYSICS for consistent timing with move_and_slide()
	_anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

	# NOTE: root_motion_track is DISABLED because it causes T-pose in complex BlendTrees.
	# When root_motion_track is set, Godot removes the Hips bone animation from skeleton pose
	# and makes it available via get_root_motion_position(). However, this breaks the skeleton
	# hierarchy causing all other bones to render incorrectly (T-pose).
	# TODO: Investigate alternative RootMotion approaches or use dedicated Root bone.
	# if use_root_motion and _skeleton and _anim_player:
	# 	var anim_root := _anim_player.get_node(_anim_player.root_node)
	# 	if anim_root:
	# 		var skeleton_path := anim_root.get_path_to(_skeleton)
	# 		var track_path := "%s:%s" % [skeleton_path, root_bone_name]
	# 		_anim_tree.root_motion_track = NodePath(track_path)
	# 		print("[CharacterAnimationController] RootMotion enabled, track: %s" % track_path)


## 8方向walkステートマシンを作成（BlendSpace2Dの代わり）
func _create_walk_state_machine(prefix: String) -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()

	# 8方向のアニメーションをステートとして追加
	var state_anims := {
		"walk_forward": prefix + "_walk_forward",
		"walk_backward": prefix + "_walk_backward",
		"walk_left": prefix + "_walk_left",
		"walk_right": prefix + "_walk_right",
		"walk_forward_left": prefix + "_walk_forward_left",
		"walk_forward_right": prefix + "_walk_forward_right",
		"walk_backward_left": prefix + "_walk_backward_left",
		"walk_backward_right": prefix + "_walk_backward_right",
	}

	for state_name in state_anims.keys():
		var anim_name: String = state_anims[state_name]
		# フォールバック: prefixのアニメがなければrifle_を試す
		if not _anim_player.has_animation(anim_name):
			anim_name = "rifle_" + state_name  # rifle_walk_forward等
		if _anim_player.has_animation(anim_name):
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			sm.add_node(state_name, anim_node)

	# Godot 4.x: Startノードから最初のステートへの遷移を追加
	if sm.has_node("walk_forward"):
		var start_tr := AnimationNodeStateMachineTransition.new()
		start_tr.xfade_time = 0.08  # 短いブレンド時間
		start_tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
		sm.add_transition("Start", "walk_forward", start_tr)

	# すべてのステート間に短いブレンド遷移を作成
	# 即時(0)だとパカパカ、長すぎると変なポーズになるため0.08秒に設定
	var state_names := state_anims.keys()
	for from_state in state_names:
		if not sm.has_node(from_state):
			continue
		for to_state in state_names:
			if from_state == to_state or not sm.has_node(to_state):
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = 0.08  # 短いブレンド時間（パカパカ防止）
			tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC  # 位相同期
			tr.reset = false
			sm.add_transition(from_state, to_state, tr)

	return sm

## Crouch用BlendSpace2D（こちらは急な方向変化が少ないのでBlendSpace2Dのまま）
func _create_crouch_blend_space(anims: Dictionary) -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	blend_space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	blend_space.auto_triangles = true
	blend_space.min_space = Vector2(-1, -1)
	blend_space.max_space = Vector2(1, 1)
	blend_space.sync = true

	for pos in anims:
		var anim_name: String = anims[pos]
		if _anim_player.has_animation(anim_name):
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			blend_space.add_blend_point(anim_node, pos)

	return blend_space

## Get animation name with fallback support
## Returns the first animation that exists in the AnimationPlayer
func _get_animation_with_fallback(primary: String, fallback1: String, fallback2: String = "") -> String:
	if _anim_player.has_animation(primary):
		return primary
	if _anim_player.has_animation(fallback1):
		print("[CharAnim] Animation '%s' not found, using fallback '%s'" % [primary, fallback1])
		return fallback1
	if not fallback2.is_empty() and _anim_player.has_animation(fallback2):
		print("[CharAnim] Animation '%s' not found, using fallback '%s'" % [primary, fallback2])
		return fallback2
	# Return primary anyway (will show error in Godot if missing)
	push_warning("[CharAnim] Animation '%s' and fallbacks not found!" % primary)
	return primary

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
		var dir2 := Vector2(-sin(angle), -cos(angle))

		# 8方向にスナップしてステート名を取得
		var new_state := _dir_to_walk_state(dir2)

		# ステートが変わった場合のみtravel
		if new_state != _current_walk_state:
			_current_walk_state = new_state
			_travel_walk_state(new_state)

		# Crouch用BlendSpace2D（こちらは補間でOK）
		_input_dir = dir2

		_movement_blend = lerpf(_movement_blend, 1.0, 1.0 - exp(-15.0 * delta))
	else:
		# アイドルへ戻す
		_movement_blend = lerpf(_movement_blend, 0.0, 1.0 - exp(-5.0 * delta))

## 入力方向を最も近い8方向のステート名に変換
func _dir_to_walk_state(dir: Vector2) -> String:
	if dir.length() < 0.01:
		return "walk_forward"

	var best_idx := 0
	var best_dot := -2.0

	for i in range(DIR8_VECTORS.size()):
		var dot := dir.normalized().dot(DIR8_VECTORS[i].normalized())
		if dot > best_dot:
			best_dot = dot
			best_idx = i

	return DIR8_STATE_NAMES[best_idx]

## StateMachineのplaybackを使ってwalkステートを切り替え
func _travel_walk_state(state_name: String) -> void:
	if not _anim_tree:
		return

	# Rifle StateMachine
	var rifle_playback = _anim_tree.get("parameters/RifleWalkSM/playback") as AnimationNodeStateMachinePlayback
	if rifle_playback and rifle_playback.get_current_node() != state_name:
		rifle_playback.travel(state_name)

	# Pistol StateMachine
	var pistol_playback = _anim_tree.get("parameters/PistolWalkSM/playback") as AnimationNodeStateMachinePlayback
	if pistol_playback and pistol_playback.get_current_node() != state_name:
		pistol_playback.travel(state_name)

func _update_animation_tree() -> void:
	if not _anim_tree or not _anim_tree.active:
		return

	# Crouch用BlendSpace2Dのみblend_position更新（Rifle/PistolはStateMachineで制御）
	_anim_tree.set("parameters/CrouchWalkBlend/blend_position", _input_dir)

	# TimeScale = 1.0 for walk animations
	# Movement speed is adjusted per-direction to match animation visual speed
	# This ensures feet don't slide regardless of movement direction
	var walk_scale: float = 1.0
	var run_scale: float = run_speed / ANIM_REF_RUN
	var crouch_scale: float = crouch_speed / ANIM_REF_CROUCH

	run_scale = clampf(run_scale, 0.5, 2.0)
	crouch_scale = clampf(crouch_scale, 0.5, 2.0)

	_anim_tree.set("parameters/WalkSpeed/scale", walk_scale)
	_anim_tree.set("parameters/RunSpeed/scale", run_scale)
	_anim_tree.set("parameters/CrouchSpeed/scale", crouch_scale)

	# Update blend amounts
	var target_run := 1.0 if _is_running else 0.0
	var target_crouch := 1.0 if _stance == Stance.CROUCH else 0.0
	var target_weapon := 1.0 if _weapon == Weapon.PISTOL else 0.0

	_crouch_blend = lerp(_crouch_blend, target_crouch, 0.15)
	_weapon_blend = lerp(_weapon_blend, target_weapon, 0.2)

	_anim_tree.set("parameters/WalkRunBlend/blend_amount", target_run)
	_anim_tree.set("parameters/StandingBlend/blend_amount", _movement_blend)
	_anim_tree.set("parameters/CrouchingBlend/blend_amount", _movement_blend)
	_anim_tree.set("parameters/StandCrouchBlend/blend_amount", _crouch_blend)
	# Weapon-based walk/run animation (0 = rifle, 1 = pistol)
	_anim_tree.set("parameters/WalkWeaponBlend/blend_amount", _weapon_blend)
	_anim_tree.set("parameters/RunWeaponBlend/blend_amount", _weapon_blend)

#endregion
