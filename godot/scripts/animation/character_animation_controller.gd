extends Node
class_name CharacterAnimationController
## Character Animation Controller API
## Provides simple interface for character animations (movement, aiming, combat, death)

# Enums
enum Weapon { NONE, RIFLE, PISTOL }
enum HitDirection { FRONT, BACK, LEFT, RIGHT }

# Signals
signal fired()
signal door_kick_impact()   # キックがドアに当たるタイミング（フレーム36/66）
signal door_kick_finished() # アニメーション完了
signal throw_release()      # グレネードをリリースするタイミング（フレーム50/120）
signal throw_finished()     # 投擲アニメーション完了
signal door_open_finished() # ドアそっと開けアニメーション完了

# Export settings
@export_group("Movement Speed")
@export var walk_speed := 2.0
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
var _weapon := Weapon.RIFLE
var _is_dead := false
var _is_door_kicking := false
var _is_throwing := false
var _is_opening_door := false
var _aim_direction := Vector3.FORWARD  # 現在のエイム方向（視界計算用）
var _lean_amount := 0.0  # ロール角（ラジアン）
var _remote_last_fire_state := false  # リモート同期用: 前回のfire状態

# Animation visual speeds at 1x playback (1-second/30-frame animations at 30fps)
# Different directions have different stride lengths
# Rifle walk speeds
const ANIM_SPEED_FORWARD := 2.0   # Forward/backward: large strides
const ANIM_SPEED_STRAFE := 1.2    # Left/right: small strides
# Pistol walk speeds (shorter strides than rifle)
const PISTOL_ANIM_SPEED_FORWARD := 1.4
const PISTOL_ANIM_SPEED_STRAFE := 0.85

# Death animation names
const DEATH_ANIM := GameConstants.ANIM_DEATH
const DEATH_ANIM_FORWARD := GameConstants.ANIM_DEATH_FORWARD
const DEATH_ANIM_BACKWARD := GameConstants.ANIM_DEATH_BACKWARD
const DEATH_ANIM_RIGHT := GameConstants.ANIM_DEATH_RIGHT

# Door kick animation names
const RIFLE_DOOR_KICK_ANIM := GameConstants.ANIM_RIFLE_DOOR_KICK
const PISTOL_DOOR_KICK_ANIM := GameConstants.ANIM_PISTOL_DOOR_KICK
const DOOR_KICK_IMPACT_TIME := 1.2  # インパクトタイミング（フレーム36 / 30fps）

# Throw animation
const PISTOL_LOW_THROWING_ANIM := GameConstants.ANIM_PISTOL_LOW_THROWING
const THROW_RELEASE_TIME := 1.67  # リリースタイミング（フレーム50 / 30fps）

# Door open animation
const RIFLE_OPEN_DOOR_ANIM := GameConstants.ANIM_RIFLE_OPEN_DOOR

# Blend values
var _input_dir := Vector2.ZERO
var _movement_blend := 0.0
var _weapon_blend := 0.0
var _fire_cooldown := 0.0
var _walk_time_scale := 1.0  # 移動速度に連動するアニメーション再生速度

# Internal nodes


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
	_is_running: bool,
	delta: float
) -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return

	# エイム方向を保存（視界計算用）
	if aim_direction.length_squared() > 0.001:
		_aim_direction = aim_direction.normalized()

	_update_lean(movement_direction, aim_direction, delta)

	# Update model rotation
	_update_model_rotation(aim_direction, delta)

	# Calculate strafe blend
	_update_strafe_blend(movement_direction, delta)

	# Update fire cooldown
	_fire_cooldown -= delta

	# Update animation tree parameters
	_update_animation_tree()

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
	_anim_tree.set("parameters/WeaponIdleBlend/blend_amount", blend_value)

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

	# Trigger shoot animation OneShot
	if _anim_tree:
		_anim_tree.set("parameters/ShootOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	fired.emit()

## Get current movement speed based on state and direction
## Returns the animation's visual speed for the current blend direction
func get_current_speed() -> float:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return 0.0
	# Calculate direction-based speed from current blend position
	return _get_directional_anim_speed()

## Calculate animation visual speed based on blend direction and weapon type
func _get_directional_anim_speed() -> float:
	# Select speed constants based on weapon type
	var fwd_speed := PISTOL_ANIM_SPEED_FORWARD if _weapon == Weapon.PISTOL else ANIM_SPEED_FORWARD
	var strafe_speed := PISTOL_ANIM_SPEED_STRAFE if _weapon == Weapon.PISTOL else ANIM_SPEED_STRAFE

	if _input_dir.length() < 0.01:
		return fwd_speed  # Default when idle

	# Normalize input direction
	var dir := _input_dir.normalized()

	# Calculate weights for forward/backward vs strafe
	var forward_weight := absf(dir.y)  # Y = forward/backward
	var strafe_weight := absf(dir.x)   # X = left/right

	# Blend between forward and strafe speeds based on direction
	var speed := fwd_speed * forward_weight + strafe_speed * strafe_weight

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


## リモートキャラクター用の回転補間速度（ローカルより少し速く追従）
const REMOTE_ROTATION_SPEED: float = 20.0

## リモートキャラクター用の回転更新（四元数SLERPで滑らかに補間）
## ローカルキャラクターと同じ補間方式を使用し、滑らかで一貫した回転を実現
## target_direction: ターゲット方向（正規化不要、内部で処理）
## delta: フレーム時間
func update_model_rotation_smooth(target_direction: Vector3, delta: float) -> void:
	if not _model or target_direction.length_squared() < 0.001:
		return

	var look_dir := target_direction.normalized()
	look_dir.y = 0

	if look_dir.length_squared() < 0.001:
		return

	# 四元数SLERPで滑らかに補間（ローカルの_update_model_rotationと同じ方式）
	# -look_dir 必須！（Mixamo+Z前方向 vs looking_at -Z前方向）
	var target_basis := Basis.looking_at(-look_dir, Vector3.UP)
	var target_quat := target_basis.get_rotation_quaternion()
	var current_quat := Quaternion(_model.transform.basis)
	var new_quat := current_quat.slerp(target_quat, REMOTE_ROTATION_SPEED * delta)
	_model.transform.basis = Basis(new_quat)

	_aim_direction = look_dir

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

	# 方向別アニメーション候補から存在するものを選択
	var anim_name := _pick_death_anim(hit_direction)

	if not anim_name.is_empty() and _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_anim_player.animation_finished.connect(_on_death_animation_finished, CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Death animation not found for direction: %s" % hit_direction)


## 被弾方向に応じた死亡アニメーション候補を優先度順に探索
## 存在するアニメーションの中から最適なものを返す
func _pick_death_anim(hit_direction: HitDirection) -> String:
	var candidates: Array[String]
	match hit_direction:
		HitDirection.FRONT:
			candidates = [DEATH_ANIM_FORWARD, DEATH_ANIM_BACKWARD, DEATH_ANIM_RIGHT]
		HitDirection.BACK:
			candidates = [DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD, DEATH_ANIM_RIGHT]
		HitDirection.RIGHT:
			candidates = [DEATH_ANIM_RIGHT, DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD]
		HitDirection.LEFT:
			# death_leftがないので後方→前方→右の順でフォールバック
			candidates = [DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD, DEATH_ANIM_RIGHT]
		_:
			candidates = [DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD, DEATH_ANIM_RIGHT]

	for anim_name in candidates:
		if _anim_player.has_animation(anim_name):
			return anim_name
	return ""

func _on_death_animation_finished(_anim_name: String) -> void:
	pass  # Death animation completed


## Play door kick animation (weapon-appropriate version)
func play_door_kick() -> void:
	if _is_dead or _is_door_kicking or _is_opening_door:
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

	# Play door kick animation (crossfade from current pose)
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, 0.15)
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
	if is_instance_valid(_anim_tree) and not _is_dead and not _is_door_kicking and not _is_throwing and not _is_opening_door:
		_anim_tree.active = true


## Check if door kick animation is playing
func is_door_kicking() -> bool:
	return _is_door_kicking


## Play throw animation (underhand grenade throw with pistol)
func play_throw() -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return

	_is_throwing = true

	# Stop AnimationTree during throw
	if _anim_tree:
		_anim_tree.active = false

	# Play throw animation (crossfade from current pose)
	if _anim_player.has_animation(PISTOL_LOW_THROWING_ANIM):
		_anim_player.play(PISTOL_LOW_THROWING_ANIM, 0.15)
		_anim_player.animation_finished.connect(_on_throw_finished, CONNECT_ONE_SHOT)
		# リリースタイミングでシグナルを発火するタイマー
		get_tree().create_timer(THROW_RELEASE_TIME).timeout.connect(_on_throw_release, CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Throw animation not found: %s" % PISTOL_LOW_THROWING_ANIM)
		_is_throwing = false
		if _anim_tree:
			_anim_tree.active = true


func _on_throw_release() -> void:
	if _is_throwing:
		throw_release.emit()


func _on_throw_finished(_anim_name: String) -> void:
	_is_throwing = false

	# スムーズにアイドルへ遷移してからAnimationTreeを再開
	if _anim_player and not _is_dead:
		var idle_anim_name := "rifle_idle" if _weapon == Weapon.RIFLE else "pistol_idle"
		var crossfade_time := 0.3
		if _anim_player.has_animation(idle_anim_name):
			_anim_player.play(idle_anim_name, crossfade_time)
		if _anim_tree:
			get_tree().create_timer(crossfade_time).timeout.connect(_resume_animation_tree, CONNECT_ONE_SHOT)

	throw_finished.emit()


## Check if throw animation is playing
func is_throwing() -> bool:
	return _is_throwing


## Play door open animation (quietly open door)
func play_door_open() -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return

	_is_opening_door = true

	if _anim_tree:
		_anim_tree.active = false

	if _anim_player.has_animation(RIFLE_OPEN_DOOR_ANIM):
		_anim_player.play(RIFLE_OPEN_DOOR_ANIM, 0.15)
		_anim_player.animation_finished.connect(_on_door_open_finished, CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Door open animation not found: %s" % RIFLE_OPEN_DOOR_ANIM)
		_is_opening_door = false
		if _anim_tree:
			_anim_tree.active = true


func _on_door_open_finished(_anim_name: String) -> void:
	_is_opening_door = false

	if _anim_player and not _is_dead:
		var idle_anim_name := "rifle_idle" if _weapon == Weapon.RIFLE else "pistol_idle"
		var crossfade_time := 0.3
		if _anim_player.has_animation(idle_anim_name):
			_anim_player.play(idle_anim_name, crossfade_time)
		if _anim_tree:
			get_tree().create_timer(crossfade_time).timeout.connect(_resume_animation_tree, CONNECT_ONE_SHOT)

	door_open_finished.emit()


## Check if door open animation is playing
func is_opening_door() -> bool:
	return _is_opening_door


## Get current animation state for network synchronization
## Returns encoded state: "is_moving,is_firing,blend_x,blend_y"
## Example: "1,1,-50,100" = moving, firing, blend(-0.5, 1.0)
func get_animation_state() -> String:
	var is_moving := 1 if _movement_blend > 0.1 else 0
	var is_firing := 1 if _fire_cooldown > 0 else 0
	var blend_x := int(_input_dir.x * 100)
	var blend_y := int(_input_dir.y * 100)
	return "%d,%d,%d,%d" % [is_moving, is_firing, blend_x, blend_y]


## Apply animation state from network (for remote characters)
## state: encoded state string from get_animation_state()
func apply_animation_state(state: String, delta: float) -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return

	var parts := state.split(",")
	if parts.size() < 4:
		return

	var is_moving := parts[0].to_int() == 1
	var is_firing := parts[1].to_int() == 1
	var blend_x := parts[2].to_int() / 100.0
	var blend_y := parts[3].to_int() / 100.0

	# リモートキャラクター用のcooldown減算（update_animation()が呼ばれないため）
	_fire_cooldown -= delta

	# リモートキャラクターの射撃エフェクト再生
	# is_firing=true が続く間、_fire_cooldownが0になったタイミングでfire()を呼び出す
	if is_firing and _fire_cooldown <= 0:
		fire()
	_remote_last_fire_state = is_firing

	# Smooth interpolation for blend values
	var target_movement := 1.0 if is_moving else 0.0
	_movement_blend = lerpf(_movement_blend, target_movement, 1.0 - exp(-10.0 * delta))

	if is_moving:
		var target_blend := Vector2(blend_x, blend_y)
		_input_dir = _input_dir.lerp(target_blend, 1.0 - exp(-12.0 * delta))
	else:
		if _movement_blend < 0.01:
			_input_dir = Vector2.ZERO

	# Update animation tree
	_update_animation_tree()


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
	_recoil_modifier = RecoilModifier.new()
	_recoil_modifier.spine_bone_name = spine_bone
	_recoil_modifier.active = true
	_skeleton.add_child(_recoil_modifier)

func _setup_lean_modifier() -> void:
	_lean_modifier = LeanModifier.new()
	_lean_modifier.spine_bone_name = spine_bone
	_lean_modifier.recovery_speed = lean_speed
	_skeleton.add_child(_lean_modifier)

func _setup_animation_loops() -> void:
	var loop_anims := [
		# Idle animations
		"rifle_idle",
		"pistol_idle",
		# Rifle walk
		"rifle_walk_forward", "rifle_walk_backward", "rifle_walk_left", "rifle_walk_right",
		"rifle_walk_forward_left", "rifle_walk_forward_right", "rifle_walk_backward_left", "rifle_walk_backward_right",
		# Pistol walk
		"pistol_walk_forward", "pistol_walk_backward", "pistol_walk_left", "pistol_walk_right",
		"pistol_walk_forward_left", "pistol_walk_forward_right", "pistol_walk_backward_left", "pistol_walk_backward_right",
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

	# Walk animations - Rifle
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

	# Walk animations - Pistol (fallback to rifle if not available)
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

	# Weapon walk blend node
	var walk_weapon_blend := AnimationNodeBlend2.new()

	var idle_anim := AnimationNodeAnimation.new()
	idle_anim.animation = "pistol_idle"

	# Rifle idle
	var rifle_idle_anim := AnimationNodeAnimation.new()
	rifle_idle_anim.animation = "rifle_idle"

	# TimeScale node for walk animations
	var walk_speed_node := AnimationNodeTimeScale.new()

	# Blend nodes
	var idle_move_blend := AnimationNodeBlend2.new()

	# Weapon idle blend node (switches idle based on weapon type)
	var weapon_idle_blend := AnimationNodeBlend2.new()

	# Add nodes
	blend_tree.add_node("Idle", idle_anim, Vector2(-600, -200))
	blend_tree.add_node("RifleIdle", rifle_idle_anim, Vector2(-600, -50))
	blend_tree.add_node("WeaponIdleBlend", weapon_idle_blend, Vector2(-400, -100))
	# Rifle/Pistol walk
	blend_tree.add_node("RifleWalkBlend", rifle_walk_blend_space, Vector2(-800, 100))
	blend_tree.add_node("PistolWalkBlend", pistol_walk_blend_space, Vector2(-800, 150))
	# Weapon-based walk blend
	blend_tree.add_node("WalkWeaponBlend", walk_weapon_blend, Vector2(-600, 100))
	blend_tree.add_node("WalkSpeed", walk_speed_node, Vector2(-400, 100))
	blend_tree.add_node("IdleMoveBlend", idle_move_blend, Vector2(0, 0))

	# Connect nodes
	# Weapon-based idle blend (0 = rifle idle, 1 = normal idle; controlled by weapon type)
	blend_tree.connect_node("WeaponIdleBlend", 0, "RifleIdle")
	blend_tree.connect_node("WeaponIdleBlend", 1, "Idle")

	# Connect weapon-based walk (0 = rifle, 1 = pistol)
	blend_tree.connect_node("WalkWeaponBlend", 0, "RifleWalkBlend")
	blend_tree.connect_node("WalkWeaponBlend", 1, "PistolWalkBlend")
	blend_tree.connect_node("WalkSpeed", 0, "WalkWeaponBlend")
	blend_tree.connect_node("IdleMoveBlend", 0, "WeaponIdleBlend")
	blend_tree.connect_node("IdleMoveBlend", 1, "WalkSpeed")

	# Fire animation OneShot (weapon-based)
	var rifle_shoot_anim := AnimationNodeAnimation.new()
	rifle_shoot_anim.animation = "rifle_shoot" if _anim_player.has_animation("rifle_shoot") else ""

	var pistol_shoot_anim := AnimationNodeAnimation.new()
	pistol_shoot_anim.animation = "pistol_shoot" if _anim_player.has_animation("pistol_shoot") else ""

	var shoot_weapon_blend := AnimationNodeBlend2.new()
	var shoot_oneshot := AnimationNodeOneShot.new()
	shoot_oneshot.fadein_time = 0.05
	shoot_oneshot.fadeout_time = 0.15

	# Upper body filter: shoot animation only affects spine and above
	_apply_upper_body_filter(shoot_oneshot)

	blend_tree.add_node("RifleShoot", rifle_shoot_anim, Vector2(100, 150))
	blend_tree.add_node("PistolShoot", pistol_shoot_anim, Vector2(100, 200))
	blend_tree.add_node("ShootWeaponBlend", shoot_weapon_blend, Vector2(200, 150))
	blend_tree.add_node("ShootOneShot", shoot_oneshot, Vector2(300, 0))

	blend_tree.connect_node("ShootWeaponBlend", 0, "RifleShoot")
	blend_tree.connect_node("ShootWeaponBlend", 1, "PistolShoot")
	blend_tree.connect_node("ShootOneShot", 0, "IdleMoveBlend")
	blend_tree.connect_node("ShootOneShot", 1, "ShootWeaponBlend")

	blend_tree.connect_node("output", 0, "ShootOneShot")

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

## Apply upper body bone filter to an AnimationNode (e.g. OneShot)
## Only filtered bones will play the one-shot; unfiltered bones continue the base animation
func _apply_upper_body_filter(node: AnimationNode) -> void:
	if not _skeleton:
		return

	# Find the bone track path prefix from actual animation data
	var prefix := _detect_bone_track_prefix()
	if prefix.is_empty():
		return

	# Get all upper body bones (Spine and its descendants)
	var spine_idx := _skeleton.find_bone("mixamorig_Spine")
	if spine_idx < 0:
		return

	var upper_bones: Array[String] = []
	_collect_descendant_bones(spine_idx, upper_bones)

	# Enable filter and set paths
	node.filter_enabled = true
	for bone_name in upper_bones:
		node.set_filter_path(NodePath("%s:%s" % [prefix, bone_name]), true)


## Detect the skeleton path prefix from animation track data
func _detect_bone_track_prefix() -> String:
	var anim_lib = _anim_player.get_animation_library("")
	for anim_name in anim_lib.get_animation_list():
		var anim := anim_lib.get_animation(anim_name)
		for i in range(anim.get_track_count()):
			var path_str := str(anim.track_get_path(i))
			var colon_idx := path_str.find(":mixamorig_")
			if colon_idx >= 0:
				return path_str.substr(0, colon_idx)
	return ""


## Recursively collect a bone and all its descendants
func _collect_descendant_bones(bone_idx: int, result: Array[String]) -> void:
	result.append(_skeleton.get_bone_name(bone_idx))
	for child_idx in _skeleton.get_bone_children(bone_idx):
		_collect_descendant_bones(child_idx, result)


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

	var move_len := move_dir.length()
	if move_len > 0.1:
		var char_forward := _model.global_transform.basis.z
		var angle := char_forward.signed_angle_to(move_dir.normalized(), Vector3.UP)
		var target_blend := Vector2(-sin(angle), -cos(angle))

		# Smooth but fast interpolation for direction changes
		# This prevents "popping" when changing direction while keeping responsiveness
		var blend_speed := 12.0  # Higher = faster response
		_input_dir = _input_dir.lerp(target_blend, 1.0 - exp(-blend_speed * delta))
		_movement_blend = lerpf(_movement_blend, 1.0, 1.0 - exp(-10.0 * delta))

		# TimeScaleを速度比に連動（0.3下限で極端なスロー再生を防ぐ）
		var target_scale := clampf(move_len, 0.3, 1.0)
		_walk_time_scale = lerpf(_walk_time_scale, target_scale, 1.0 - exp(-10.0 * delta))
	else:
		# Quick fade to idle when stopped
		_movement_blend = lerpf(_movement_blend, 0.0, 1.0 - exp(-8.0 * delta))
		if _movement_blend < 0.01:
			_input_dir = Vector2.ZERO
		_walk_time_scale = lerpf(_walk_time_scale, 1.0, 1.0 - exp(-6.0 * delta))

func _update_animation_tree() -> void:
	if not _anim_tree or not _anim_tree.active:
		return

	# Update blend positions
	if _movement_blend > 0.01:
		_anim_tree.set("parameters/RifleWalkBlend/blend_position", _input_dir)
		_anim_tree.set("parameters/PistolWalkBlend/blend_position", _input_dir)

	# TimeScale を移動速度比に連動（加減速時に足のテンポが追従）
	_anim_tree.set("parameters/WalkSpeed/scale", _walk_time_scale)

	# Update blend amounts
	var target_weapon := 1.0 if _weapon == Weapon.PISTOL else 0.0
	_weapon_blend = lerp(_weapon_blend, target_weapon, 0.2)

	_anim_tree.set("parameters/IdleMoveBlend/blend_amount", _movement_blend)
	# Weapon-based walk animation (0 = rifle, 1 = pistol)
	_anim_tree.set("parameters/WalkWeaponBlend/blend_amount", _weapon_blend)
	# Weapon-based shoot animation (0 = rifle, 1 = pistol)
	_anim_tree.set("parameters/ShootWeaponBlend/blend_amount", _weapon_blend)

#endregion
