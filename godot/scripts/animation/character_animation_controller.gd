extends Node
class_name CharacterAnimationController
## Character Animation Controller API
## Provides simple interface for character animations (movement, aiming, combat, death)

# Enums
enum Stance { STAND, CROUCH }
enum Weapon { NONE, RIFLE, PISTOL }
enum HitDirection { FRONT, BACK, LEFT, RIGHT }

# Signals
signal fired()
signal door_kick_impact()   # キックがドアに当たるタイミング（フレーム36/66）
signal door_kick_finished() # アニメーション完了

# Export settings
@export_group("Movement Speed")
@export var walk_speed := 2.0
@export var run_speed := 5.0
@export var crouch_speed := 1.5
@export var rotation_speed := 15.0

@export_group("Recoil")
@export var rifle_recoil_strength := 0.16
@export var pistol_recoil_strength := 0.24
@export var rifle_fire_rate := 0.1
@export var pistol_fire_rate := 0.2
@export var recoil_recovery := 10.0

@export_group("Lean")
@export var max_lean_degrees := 25.0
@export var lean_speed := 10.0
@export var lean_deadzone := 0.15

@export_group("Bone Names")
@export var upper_body_root := GameConstants.BONE_SPINE_1
@export var spine_bone := GameConstants.BONE_SPINE_2

# Internal references
var _model: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _skeleton: Skeleton3D
var _recoil_modifier: SkeletonModifier3D
var _lean_modifier: SkeletonModifier3D

# State
var _stance := Stance.STAND
var _weapon := Weapon.RIFLE
var _is_running := false
var _is_dead := false
var _is_door_kicking := false
var _aim_direction := Vector3.FORWARD  # 現在のエイム方向（視界計算用）
var _lean_amount := 0.0  # ロール角（ラジアン）

# Animation visual speeds at 1x playback (1-second/30-frame animations at 30fps)
# Different directions have different stride lengths
const ANIM_SPEED_FORWARD := 2.0   # Forward/backward: large strides
const ANIM_SPEED_STRAFE := 1.2    # Left/right: small strides
const ANIM_SPEED_DIAGONAL := 1.6  # Diagonal: medium strides
const ANIM_REF_RUN := 5.5         # Sprint animation (15 frames at 30fps = 0.5s)
const ANIM_REF_CROUCH := 1.5      # Crouch walk

# Death animation names
const DEATH_ANIM := GameConstants.ANIM_DEATH
const DEATH_ANIM_FORWARD := GameConstants.ANIM_DEATH_FORWARD
const DEATH_ANIM_BACKWARD := GameConstants.ANIM_DEATH_BACKWARD
const DEATH_ANIM_RIGHT := GameConstants.ANIM_DEATH_RIGHT

# Door kick animation names
const RIFLE_DOOR_KICK_ANIM := GameConstants.ANIM_RIFLE_DOOR_KICK
const PISTOL_DOOR_KICK_ANIM := GameConstants.ANIM_PISTOL_DOOR_KICK
const DOOR_KICK_IMPACT_TIME := 1.2  # インパクトタイミング（フレーム36 / 30fps）

# Blend values
var _input_dir := Vector2.ZERO
var _movement_blend := 0.0
var _crouch_blend := 0.0
var _weapon_blend := 0.0
var _run_blend := 0.0
var _fire_cooldown := 0.0

# Internal nodes

const RecoilModifierScript = preload("res://scripts/modifiers/recoil_modifier.gd")
const LeanModifierScript = preload("res://scripts/modifiers/lean_modifier.gd")

#region Public API

## Setup the animation controller
func setup(model: Node3D, anim_player: AnimationPlayer) -> void:
	_model = model
	_anim_player = anim_player
	_skeleton = _find_skeleton(model)

	if _skeleton:
		_setup_recoil_modifier()
		_setup_lean_modifier()
		# Set AnimationPlayer root_node to model node (parent of Skeleton3D)
		# Animation tracks use paths like "Skeleton3D:bonename"
		if _anim_player:
			_anim_player.root_node = NodePath("..")

	if not _anim_player:
		printerr("CharacterAnimationController: AnimationPlayer not found/provided")
		return

	_setup_animation_loops()
	_setup_animation_tree()
	_update_weapon_idle_blend()

	# 注意: 初期の向きはGameCharacter.set_facing_direction()で設定される
	# ここでは_aim_directionを初期化しない（デフォルトのVector3.FORWARDを使用）

## Main update function - call every frame
func update_animation(
	movement_direction: Vector3,
	aim_direction: Vector3,
	is_running: bool,
	delta: float
) -> void:
	if _is_dead or _is_door_kicking:
		return

	# エイム方向を保存（視界計算用）
	if aim_direction.length_squared() > 0.001:
		_aim_direction = aim_direction.normalized()

	_is_running = is_running and _stance != Stance.CROUCH

	_update_lean(movement_direction, aim_direction, delta)

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
	fired.emit()

## Get current movement speed based on state and direction
## Returns the animation's visual speed for the current blend direction
func get_current_speed() -> float:
	if _is_dead or _is_door_kicking:
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


## Set AnimationTree active state
func set_animation_tree_active(active: bool) -> void:
	if _anim_tree:
		_anim_tree.active = active

## Get current aim direction (for vision calculation)
func get_look_direction() -> Vector3:
	return _aim_direction


## Get the model node (for external rotation control)
func get_model() -> Node3D:
	return _model


## Set aim direction directly (for rotation mode)
## 非推奨: GameCharacter.set_facing_direction_vec()を使用してください
func set_look_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		_aim_direction = direction.normalized()
		_aim_direction.y = 0
		if _model:
			# -_aim_direction 必須！（Mixamo+Z前方向 vs looking_at -Z前方向）
			var target_basis := Basis.looking_at(-_aim_direction, Vector3.UP)
			_model.transform.basis = target_basis


## モデルの向きを設定（GameCharacterから呼ばれる）
## directionはキャラクターが向きたい方向（正規化済み）
## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
## !! 警告: -direction を変更しないこと！                            !!
## !! Mixamoモデルは+Zが前方向、looking_at()は-Zをターゲットに向ける !!
## !! この反転は必須。削除するとモデルが逆方向を向く                 !!
## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
func set_model_direction(direction: Vector3) -> void:
	if not _model or direction.length_squared() < 0.001:
		return
	_aim_direction = direction.normalized()
	var target_basis := Basis.looking_at(-direction, Vector3.UP)  # ← -direction 必須！
	_model.transform.basis = target_basis

## Play death animation
## hit_direction: Direction the hit came FROM (determines fall direction)
## headshot: Reserved for future use
func play_death(hit_direction: HitDirection = HitDirection.FRONT, _headshot: bool = false) -> void:
	if _is_dead:
		return

	_is_dead = true

	# Stop AnimationTree
	if _anim_tree:
		_anim_tree.active = false

	# 方向別アニメーション選択
	var anim_name: String
	match hit_direction:
		HitDirection.FRONT:
			anim_name = DEATH_ANIM_FORWARD
		HitDirection.BACK:
			anim_name = DEATH_ANIM_BACKWARD
		HitDirection.RIGHT:
			anim_name = DEATH_ANIM_RIGHT
		HitDirection.LEFT:
			# death_leftがないのでデフォルトにフォールバック
			anim_name = DEATH_ANIM_FORWARD
		_:
			anim_name = DEATH_ANIM_FORWARD

	# Play death animation with fallback
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_anim_player.animation_finished.connect(_on_death_animation_finished, CONNECT_ONE_SHOT)
	elif _anim_player.has_animation(DEATH_ANIM):
		# フォールバック: デフォルトアニメーション
		_anim_player.play(DEATH_ANIM)
		_anim_player.animation_finished.connect(_on_death_animation_finished, CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Death animation not found: %s" % anim_name)

func _on_death_animation_finished(_anim_name: String) -> void:
	pass  # Death animation completed


## Play door kick animation (weapon-appropriate version)
func play_door_kick() -> void:
	if _is_dead or _is_door_kicking:
		return

	_is_door_kicking = true

	# Stop AnimationTree during door kick
	if _anim_tree:
		_anim_tree.active = false

	# Select animation based on weapon type
	var anim_name: String
	match _weapon:
		Weapon.PISTOL:
			anim_name = PISTOL_DOOR_KICK_ANIM
		_:
			anim_name = RIFLE_DOOR_KICK_ANIM

	# Play door kick animation
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_anim_player.animation_finished.connect(_on_door_kick_finished, CONNECT_ONE_SHOT)
		# インパクトタイミングでシグナルを発火するタイマー
		get_tree().create_timer(DOOR_KICK_IMPACT_TIME).timeout.connect(_on_door_kick_impact, CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Door kick animation not found: %s" % anim_name)
		_is_door_kicking = false
		if _anim_tree:
			_anim_tree.active = true


func _on_door_kick_impact() -> void:
	if _is_door_kicking:
		door_kick_impact.emit()


func _on_door_kick_finished(_anim_name: String) -> void:
	_is_door_kicking = false

	# スムーズにアイドルへ遷移してからAnimationTreeを再開
	if _anim_player and not _is_dead:
		# 武器に応じたアイドルアニメーションを選択
		var idle_anim_name := "rifle_idle" if _weapon == Weapon.RIFLE else "pistol_idle"
		if _stance == Stance.CROUCH:
			idle_anim_name = "rifle_idle_crouching" if _weapon == Weapon.RIFLE else "pistol_idle_crouching"

		# クロスフェードでアイドルへ遷移（0.3秒）
		var crossfade_time := 0.3
		if _anim_player.has_animation(idle_anim_name):
			_anim_player.play(idle_anim_name, crossfade_time)

		# クロスフェード完了後にAnimationTreeを再開
		if _anim_tree:
			get_tree().create_timer(crossfade_time).timeout.connect(_resume_animation_tree, CONNECT_ONE_SHOT)

	door_kick_finished.emit()


## ドアキック後のAnimationTree再開
func _resume_animation_tree() -> void:
	if is_instance_valid(_anim_tree) and not _is_dead and not _is_door_kicking:
		_anim_tree.active = true


## Check if door kick animation is playing
func is_door_kicking() -> bool:
	return _is_door_kicking


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
	_recoil_modifier.active = true
	_skeleton.add_child(_recoil_modifier)

func _setup_lean_modifier() -> void:
	_lean_modifier = LeanModifierScript.new()
	_lean_modifier.spine_bone_name = spine_bone
	_lean_modifier.recovery_speed = lean_speed
	_skeleton.add_child(_lean_modifier)

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
	# Create or get AnimationTree
	_anim_tree = _model.get_node_or_null(GameConstants.NODE_ANIMATION_TREE) as AnimationTree
	if not _anim_tree:
		_anim_tree = AnimationTree.new()
		_anim_tree.name = GameConstants.NODE_ANIMATION_TREE
		_model.get_parent().add_child(_anim_tree)

	var blend_tree := AnimationNodeBlendTree.new()

	# Standing animations - Rifle
	var rifle_walk_blend_space := _create_blend_space({
		Vector2(0, -1): "rifle_walk_forward",
		Vector2(0, 1): "rifle_walk_backward",
		Vector2(-1, 0): "rifle_walk_left",
		Vector2(1, 0): "rifle_walk_right",
		Vector2(-0.707, -0.707): "rifle_walk_forward_left",
		Vector2(0.707, -0.707): "rifle_walk_forward_right",
		Vector2(-0.707, 0.707): "rifle_walk_backward_left",
		Vector2(0.707, 0.707): "rifle_walk_backward_right",
	})

	# Sprint animations (single animation, not BlendSpace)
	var rifle_sprint_anim := AnimationNodeAnimation.new()
	rifle_sprint_anim.animation = "rifle_sprint"

	var pistol_sprint_anim := AnimationNodeAnimation.new()
	pistol_sprint_anim.animation = "pistol_sprint"

	# Standing animations - Pistol (fallback to rifle if not available)
	var pistol_walk_blend_space := _create_blend_space_with_fallback({
		Vector2(0, -1): ["pistol_walk_forward", "rifle_walk_forward"],
		Vector2(0, 1): ["pistol_walk_backward", "rifle_walk_backward"],
		Vector2(-1, 0): ["pistol_walk_left", "rifle_walk_left"],
		Vector2(1, 0): ["pistol_walk_right", "rifle_walk_right"],
		Vector2(-0.707, -0.707): ["pistol_walk_forward_left", "rifle_walk_forward_left"],
		Vector2(0.707, -0.707): ["pistol_walk_forward_right", "rifle_walk_forward_right"],
		Vector2(-0.707, 0.707): ["pistol_walk_backward_left", "rifle_walk_backward_left"],
		Vector2(0.707, 0.707): ["pistol_walk_backward_right", "rifle_walk_backward_right"],
	})

	# Weapon walk/run blend nodes
	var walk_weapon_blend := AnimationNodeBlend2.new()
	var run_weapon_blend := AnimationNodeBlend2.new()

	var idle_anim := AnimationNodeAnimation.new()
	idle_anim.animation = "pistol_idle"

	# Rifle idle (standing)
	var rifle_idle_anim := AnimationNodeAnimation.new()
	rifle_idle_anim.animation = "rifle_idle"

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
	crouch_idle_anim.animation = "pistol_idle"  # TODO: Add pistol_idle_crouching

	# Rifle idle (crouching)
	var rifle_crouch_idle_anim := AnimationNodeAnimation.new()
	rifle_crouch_idle_anim.animation = "rifle_idle"  # TODO: Add rifle_idle_crouching

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
	# Rifle walk/sprint
	blend_tree.add_node("RifleWalkBlend", rifle_walk_blend_space, Vector2(-800, 100))
	blend_tree.add_node("RifleSprint", rifle_sprint_anim, Vector2(-800, 300))
	# Pistol walk/sprint
	blend_tree.add_node("PistolWalkBlend", pistol_walk_blend_space, Vector2(-800, 150))
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
	blend_tree.connect_node("WalkWeaponBlend", 0, "RifleWalkBlend")
	blend_tree.connect_node("WalkWeaponBlend", 1, "PistolWalkBlend")
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
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.active = true


func _create_blend_space(anims: Dictionary) -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	blend_space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	blend_space.auto_triangles = true
	blend_space.min_space = Vector2(-1, -1)
	blend_space.max_space = Vector2(1, 1)
	# Enable sync to keep animation phase synchronized across blend positions
	blend_space.sync = true

	for pos in anims:
		var anim_name: String = anims[pos]
		if _anim_player.has_animation(anim_name):
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			blend_space.add_blend_point(anim_node, pos)

	return blend_space

func _create_blend_space_with_fallback(anims: Dictionary) -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	blend_space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	blend_space.auto_triangles = true
	blend_space.min_space = Vector2(-1, -1)
	blend_space.max_space = Vector2(1, 1)
	# Enable sync to keep animation phase synchronized across blend positions
	blend_space.sync = true

	for pos in anims:
		var anim_names: Array = anims[pos]
		var found_anim := ""
		for anim_name in anim_names:
			if _anim_player.has_animation(anim_name):
				found_anim = anim_name
				break
		if not found_anim.is_empty():
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = found_anim
			blend_space.add_blend_point(anim_node, pos)

	return blend_space

func _update_model_rotation(aim_direction: Vector3, delta: float) -> void:
	if not _model:
		return

	var look_dir := aim_direction
	look_dir.y = 0

	if look_dir.length() > 0.1:
		# -look_dir 必須！（Mixamo+Z前方向 vs looking_at -Z前方向）
		var target_basis := Basis.looking_at(-look_dir.normalized(), Vector3.UP)
		var target_quat := target_basis.get_rotation_quaternion()
		var current_quat := Quaternion(_model.transform.basis)
		var new_quat := current_quat.slerp(target_quat, rotation_speed * delta)
		_model.transform.basis = Basis(new_quat)

func _update_lean(movement_direction: Vector3, aim_direction: Vector3, delta: float) -> void:
	var target_lean := 0.0
	if _stance != Stance.CROUCH and not _is_running:
		var move_dir := movement_direction
		move_dir.y = 0
		if move_dir.length() > 0.1:
			var look_dir := aim_direction
			look_dir.y = 0
			if look_dir.length() > 0.1:
				var forward := -look_dir.normalized()
				var right := forward.cross(Vector3.UP).normalized()
				var side_amount := move_dir.normalized().dot(right)
				if absf(side_amount) > lean_deadzone:
					var max_lean := deg_to_rad(max_lean_degrees)
					target_lean = clampf(side_amount, -1.0, 1.0) * max_lean

	_lean_amount = lerpf(_lean_amount, target_lean, 1.0 - exp(-lean_speed * delta))
	if _lean_modifier and _lean_modifier.has_method("set_target_lean"):
		_lean_modifier.set_target_lean(_lean_amount)

func _update_strafe_blend(movement_direction: Vector3, delta: float) -> void:
	var move_dir := movement_direction
	move_dir.y = 0

	if move_dir.length() > 0.1:
		var char_forward := _model.global_transform.basis.z
		var angle := char_forward.signed_angle_to(move_dir.normalized(), Vector3.UP)
		var target_blend := Vector2(-sin(angle), -cos(angle))

		# Smooth but fast interpolation for direction changes
		# This prevents "popping" when changing direction while keeping responsiveness
		var blend_speed := 12.0  # Higher = faster response
		_input_dir = _input_dir.lerp(target_blend, 1.0 - exp(-blend_speed * delta))
		_movement_blend = lerpf(_movement_blend, 1.0, 1.0 - exp(-10.0 * delta))
	else:
		# Quick fade to idle when stopped
		_movement_blend = lerpf(_movement_blend, 0.0, 1.0 - exp(-8.0 * delta))
		if _movement_blend < 0.01:
			_input_dir = Vector2.ZERO

func _update_animation_tree() -> void:
	if not _anim_tree or not _anim_tree.active:
		return

	# Update blend positions (walk only, sprint is a single animation)
	if _movement_blend > 0.01:
		_anim_tree.set("parameters/RifleWalkBlend/blend_position", _input_dir)
		_anim_tree.set("parameters/PistolWalkBlend/blend_position", _input_dir)
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

	_run_blend = lerp(_run_blend, target_run, 0.15)
	_crouch_blend = lerp(_crouch_blend, target_crouch, 0.15)
	_weapon_blend = lerp(_weapon_blend, target_weapon, 0.2)

	_anim_tree.set("parameters/WalkRunBlend/blend_amount", _run_blend)
	_anim_tree.set("parameters/StandingBlend/blend_amount", _movement_blend)
	_anim_tree.set("parameters/CrouchingBlend/blend_amount", _movement_blend)
	_anim_tree.set("parameters/StandCrouchBlend/blend_amount", _crouch_blend)
	# Weapon-based walk/run animation (0 = rifle, 1 = pistol)
	_anim_tree.set("parameters/WalkWeaponBlend/blend_amount", _weapon_blend)
	_anim_tree.set("parameters/RunWeaponBlend/blend_amount", _weapon_blend)

#endregion
