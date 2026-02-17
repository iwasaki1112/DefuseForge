extends Node
class_name CharacterAnimationController
## Character Animation Controller API
## Provides simple interface for character animations (movement, aiming, combat, death)
## ARP rig + in-place animation system with TimeScale speed sync

# Enums
enum Weapon { NONE, RIFLE, PISTOL }
enum HitDirection { FRONT, BACK, LEFT, RIGHT }

# Signals
signal fired()
signal throw_release()      # グレネードをリリースするタイミング
signal throw_finished()     # 投擲アニメーション完了
signal door_open_finished() # ドアそっと開けアニメーション完了
signal door_open_impact()   # ドアを実際に開くインパクトタイミング

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
@export var max_lean_degrees := 10.0
@export var lean_speed := 10.0
@export var lean_deadzone := 0.15

@export_group("Turn Lean")
@export var turn_lean_degrees := 15.0    ## 方向転換時の最大リーン角度（度）
@export var turn_lean_smoothing := 15.0  ## 角速度のスムージング速度
@export var turn_lean_angular_ref := 1.5 ## 最大リーンとなる角速度(rad/s)

@export_group("Model Offset")
@export var model_y_offset := 0.40  ## Hips高さ補正（新アニメーション vs 旧アニメーションの差 + 微調整）

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
var _left_hand_ik: LeftHandIKModifier = null

# State
var _weapon := Weapon.RIFLE
var _is_dead := false
var _is_door_kicking := false
var _is_throwing := false
var _is_opening_door := false
var _is_talking := false
var _aim_direction := Vector3.FORWARD  # 現在のエイム方向（視界計算用）
var _lean_amount := 0.0  # ロール角（ラジアン）
var _prev_aim_for_turn := Vector3.FORWARD  # ターンリーン用: 前フレームのエイム方向
var _smoothed_angular_vel := 0.0  # スムージング済み角速度(rad/s)
var _remote_last_fire_state := false  # リモート同期用: 前回のfire状態
var _is_sprinting := false

# Speed constants
const WALK_SPEED := 2.0
const SPRINT_SPEED := 6.0

# Per-direction natural walk speeds (m/s) from root motion data
const PISTOL_ANIM_SPEEDS := {
	"fwd": 2.016, "bwd": 1.845,
	"left": 1.663, "right": 2.142,
	"fwd_left": 1.724, "fwd_right": 2.016,
	"bwd_left": 1.663, "bwd_right": 1.724,
	"sprint": 4.299,
}
const RIFLE_ANIM_SPEEDS := {
	"fwd": 2.016, "bwd": 1.845,
	"left": 1.663, "right": 2.142,
	"fwd_left": 1.724, "fwd_right": 2.016,
	"bwd_left": 1.663, "bwd_right": 1.724,
	"sprint": 4.299,
}

# Death animation names
const DEATH_ANIM := GameConstants.ANIM_DEATH
const DEATH_ANIM_FORWARD := GameConstants.ANIM_DEATH_FORWARD
const DEATH_ANIM_BACKWARD := GameConstants.ANIM_DEATH_BACKWARD
const DEATH_ANIM_LEFT := GameConstants.ANIM_DEATH_LEFT
const DEATH_ANIM_RIGHT := GameConstants.ANIM_DEATH_RIGHT

# Door kick animation names
const RIFLE_DOOR_KICK_ANIM := GameConstants.ANIM_RIFLE_DOOR_KICK
const PISTOL_DOOR_KICK_ANIM := GameConstants.ANIM_PISTOL_DOOR_KICK
const DOOR_KICK_IMPACT_TIME := 1.2  # インパクトタイミング（フレーム36 / 30fps）

# Throw animation
const PISTOL_LOW_THROWING_ANIM := GameConstants.ANIM_PISTOL_LOW_THROWING
const THROW_RELEASE_TIME := 1.67  # リリースタイミング（フレーム50 / 30fps）

# Far throw animation (weapon-dependent)
const RIFLE_THROW_FAR_ANIM := GameConstants.ANIM_RIFLE_GRENADE_THROW_FAR
const PISTOL_THROW_FAR_ANIM := GameConstants.ANIM_PISTOL_LOW_THROWING  # Pistolはfar専用がないためSingle使用
const THROW_FAR_RELEASE_TIME := 0.433  # キー13 / 30fps

# Close throw animation (weapon-dependent)
const RIFLE_THROW_CLOSE_ANIM := GameConstants.ANIM_RIFLE_GRENADE_THROW_CLOSE
const PISTOL_THROW_CLOSE_ANIM := GameConstants.ANIM_PISTOL_GRENADE_THROW_CLOSE
const THROW_CLOSE_RELEASE_TIME := 0.333  # キー10 / 30fps

# Door open animation
const RIFLE_OPEN_DOOR_ANIM := GameConstants.ANIM_RIFLE_OPEN_DOOR
const PISTOL_OPEN_DOOR_ANIM := GameConstants.ANIM_PISTOL_OPEN_DOOR
const DOOR_OPEN_IMPACT_TIME := 0.5  # ドアを開くインパクトタイミング（15フレーム目 @30fps）

# Blend values
var _input_dir := Vector2.ZERO
var _movement_blend := 0.0  # 0=idle, 1=walking
var _speed_blend := 0.0     # 0=walk, 1=sprint
var _fire_cooldown := 0.0

# Blend smoothing
const BLEND_SMOOTH := 10.0


#region Public API

## Setup the animation controller
func setup(model: Node3D, anim_player: AnimationPlayer) -> void:
	_model = model
	_anim_player = anim_player
	_skeleton = _find_skeleton(model)

	if _skeleton:
		# Hips高さ補正: 新アニメーションのHips位置が旧より低いためモデルを持ち上げる
		if model_y_offset != 0.0:
			_skeleton.position.y += model_y_offset

		_setup_recoil_modifier()
		_setup_lean_modifier()
		_setup_left_hand_ik()
		# AnimationPlayer root_node: トラックパス root/Skeleton3D:Bone の解決基点
		if _anim_player:
			_anim_player.root_node = NodePath("..")

	if not _anim_player:
		printerr("CharacterAnimationController: AnimationPlayer not found/provided")
		return

	_setup_animation_loops()
	_setup_animation_tree()

	# 注意: 初期の向きはGameCharacter.set_facing_direction()で設定される
	# ここでは_aim_directionを初期化しない（デフォルトのVector3.FORWARDを使用）

## Main update function - call every frame
func update_animation(
	movement_direction: Vector3,
	aim_direction: Vector3,
	is_running: bool,
	delta: float
) -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door or _is_talking:
		return

	# is_running パラメータをスプリントとして使用
	_is_sprinting = is_running and movement_direction.length() > 0.1

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
	_update_animation_tree(delta)

## Set weapon type
func set_weapon(weapon: Weapon) -> void:
	if _weapon == weapon:
		return
	_weapon = weapon
	_switch_weapon_animations()
	# PISTOLは片手持ちなのでIK無効
	if _left_hand_ik:
		_left_hand_ik.set_enabled(weapon != Weapon.PISTOL and _left_hand_ik.has_grip_source())

## Set left hand grip source node for IK
## grip_node: 武器モデル内のLeftHandGripノード（nullで無効化）
func set_left_hand_grip(grip_node: Node3D) -> void:
	if not _left_hand_ik:
		return
	if grip_node:
		_left_hand_ik.set_grip_source(grip_node)
		if _weapon != Weapon.PISTOL:
			_left_hand_ik.set_enabled(true)
	else:
		_left_hand_ik.clear_grip_source()

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
func get_current_speed() -> float:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door or _is_talking:
		return 0.0
	if _is_sprinting:
		return SPRINT_SPEED
	if _movement_blend > 0.1:
		return WALK_SPEED
	return 0.0

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


## Get bone global position (world space)
func get_bone_global_position(bone_name: String) -> Vector3:
	if not _skeleton:
		return Vector3.ZERO
	var idx := _skeleton.find_bone(bone_name)
	if idx < 0:
		return Vector3.ZERO
	var bone_pose := _skeleton.get_bone_global_pose(idx)
	return _skeleton.global_transform * bone_pose.origin


## Set aim direction directly (for rotation mode)
## 非推奨: GameCharacter.set_facing_direction_vec()を使用してください
func set_look_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		_aim_direction = direction.normalized()
		_aim_direction.y = 0
		if _model:
			# -_aim_direction 必須！（モデル+Z前方向 vs looking_at -Z前方向）
			var target_basis := Basis.looking_at(-_aim_direction, Vector3.UP)
			_model.transform.basis = target_basis


## モデルの向きを設定（GameCharacterから呼ばれる）
## directionはキャラクターが向きたい方向（正規化済み）
## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
## !! 警告: -direction を変更しないこと！                            !!
## !! モデルは+Zが前方向、looking_at()は-Zをターゲットに向ける      !!
## !! この反転は必須。削除するとモデルが逆方向を向く                 !!
## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
var _smooth_rotating: bool = false  ## smooth_rotate_to() 中は set_model_direction を無視

func set_model_direction(direction: Vector3) -> void:
	if _smooth_rotating:
		return
	if not _model or direction.length_squared() < 0.001:
		return
	_aim_direction = direction.normalized()
	var target_basis := Basis.looking_at(-direction, Vector3.UP)  # ← -direction 必須！
	_model.transform.basis = target_basis


## モデルを指定方向へ滑らかに回転（Tween SLERP）
## 回転中は set_model_direction を無効化し、完了後に復帰する
func smooth_rotate_to(direction: Vector3, duration: float = 0.2) -> Signal:
	if not _model or direction.length_squared() < 0.001:
		# 即座に完了するシグナルを返す
		set_model_direction(direction)
		return get_tree().process_frame
	direction = direction.normalized()
	direction.y = 0.0
	_aim_direction = direction
	_smooth_rotating = true
	var current_quat := Quaternion(_model.transform.basis.orthonormalized())
	var target_quat := Quaternion(Basis.looking_at(-direction, Vector3.UP))
	var tween := _model.create_tween()
	tween.tween_method(func(t: float) -> void:
		_model.transform.basis = Basis(current_quat.slerp(target_quat, t))
	, 0.0, 1.0, duration)
	tween.tween_callback(func() -> void:
		_smooth_rotating = false
	)
	return tween.finished


## リモートキャラクター用の回転補間速度（ローカルより少し速く追従）
const REMOTE_ROTATION_SPEED: float = 20.0

## リモートキャラクター用の回転更新（四元数SLERPで滑らかに補間）
func update_model_rotation_smooth(target_direction: Vector3, delta: float) -> void:
	if not _model or target_direction.length_squared() < 0.001:
		return

	var look_dir := target_direction.normalized()
	look_dir.y = 0

	if look_dir.length_squared() < 0.001:
		return

	# 四元数SLERPで滑らかに補間
	# -look_dir 必須！（モデル+Z前方向 vs looking_at -Z前方向）
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

	# 左手IKを即座に無効化
	if _left_hand_ik:
		_left_hand_ik.disable_immediate()

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
func _pick_death_anim(hit_direction: HitDirection) -> String:
	var candidates: Array[String]
	match hit_direction:
		HitDirection.FRONT:
			candidates = [DEATH_ANIM_FORWARD, DEATH_ANIM_BACKWARD, DEATH_ANIM_RIGHT, DEATH_ANIM_LEFT]
		HitDirection.BACK:
			candidates = [DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD, DEATH_ANIM_RIGHT, DEATH_ANIM_LEFT]
		HitDirection.RIGHT:
			candidates = [DEATH_ANIM_RIGHT, DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD, DEATH_ANIM_LEFT]
		HitDirection.LEFT:
			candidates = [DEATH_ANIM_LEFT, DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD, DEATH_ANIM_RIGHT]
		_:
			candidates = [DEATH_ANIM_BACKWARD, DEATH_ANIM_FORWARD, DEATH_ANIM_RIGHT, DEATH_ANIM_LEFT]

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

	# 左手IKを無効化
	if _left_hand_ik:
		_left_hand_ik.set_enabled(false)

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
	pass  # Impact timing (available for future use)


func _on_door_kick_finished(_anim_name: String) -> void:
	# _is_door_kicking は _resume_animation_tree で解除（早期解除すると update_animation が割り込む）

	# スムーズにアイドルへ遷移してからAnimationTreeを再開
	if _anim_player and not _is_dead:
		var idle_anim_name := _get_idle_anim_name()
		var crossfade_time := 0.3
		if _anim_player.has_animation(idle_anim_name):
			_anim_player.play(idle_anim_name, crossfade_time)
		if _anim_tree:
			get_tree().create_timer(crossfade_time).timeout.connect(_resume_animation_tree, CONNECT_ONE_SHOT)
		else:
			_is_door_kicking = false
	else:
		_is_door_kicking = false



## ドアキック後のAnimationTree再開
func _resume_animation_tree() -> void:
	# アクション完了フラグを解除
	_is_door_kicking = false
	_is_opening_door = false

	if is_instance_valid(_anim_tree) and not _is_dead and not _is_throwing and not _is_talking:
		# ブレンドパラメータをアイドル状態にリセット（古い移動状態でのピクつき防止）
		_movement_blend = 0.0
		_speed_blend = 0.0
		_anim_tree.set("parameters/IdleBlend/blend_amount", 0.0)
		_anim_tree.set("parameters/SpeedBlend/blend_amount", 0.0)
		_anim_tree.active = true
		# 左手IKを武器に応じて再有効化
		if _left_hand_ik and _left_hand_ik.has_grip_source() and _weapon != Weapon.PISTOL:
			_left_hand_ik.set_enabled(true)


## Check if door kick animation is playing
func is_door_kicking() -> bool:
	return _is_door_kicking


## Play throw animation (legacy: underhand grenade throw with pistol)
func play_throw() -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return
	_start_throw(PISTOL_LOW_THROWING_ANIM, THROW_RELEASE_TIME)


func _on_throw_release() -> void:
	if _is_throwing:
		throw_release.emit()


func _on_throw_finished(_anim_name: String) -> void:
	_is_throwing = false

	# スムーズにアイドルへ遷移してからAnimationTreeを再開
	if _anim_player and not _is_dead:
		var idle_anim_name := _get_idle_anim_name()
		var crossfade_time := 0.3
		if _anim_player.has_animation(idle_anim_name):
			_anim_player.play(idle_anim_name, crossfade_time)
		if _anim_tree:
			get_tree().create_timer(crossfade_time).timeout.connect(_resume_animation_tree, CONNECT_ONE_SHOT)

	throw_finished.emit()


## Play far throw animation (weapon-appropriate overhand throw)
func play_throw_far() -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return

	var anim_name: String
	match _weapon:
		Weapon.PISTOL:
			anim_name = PISTOL_THROW_FAR_ANIM
		_:
			anim_name = RIFLE_THROW_FAR_ANIM

	_start_throw(anim_name, THROW_FAR_RELEASE_TIME)


## Play close throw animation (weapon-appropriate underhand throw)
func play_throw_close() -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return

	var anim_name: String
	match _weapon:
		Weapon.PISTOL:
			anim_name = PISTOL_THROW_CLOSE_ANIM
		_:
			anim_name = RIFLE_THROW_CLOSE_ANIM

	_start_throw(anim_name, THROW_CLOSE_RELEASE_TIME)


## 投擲アニメーション共通処理
func _start_throw(anim_name: String, release_time: float) -> void:
	_is_throwing = true

	# 左手IKを無効化
	if _left_hand_ik:
		_left_hand_ik.set_enabled(false)

	# Stop AnimationTree during throw
	if _anim_tree:
		_anim_tree.active = false

	# Play throw animation (crossfade from current pose)
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, 0.15)
		_anim_player.animation_finished.connect(_on_throw_finished, CONNECT_ONE_SHOT)
		# リリースタイミングでシグナルを発火するタイマー
		get_tree().create_timer(release_time).timeout.connect(_on_throw_release, CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Throw animation not found: %s" % anim_name)
		_is_throwing = false
		if _anim_tree:
			_anim_tree.active = true


## Check if throw animation is playing
func is_throwing() -> bool:
	return _is_throwing


## Play door open animation (quietly open door)
func play_door_open() -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door:
		return

	_is_opening_door = true

	# 左手IKを無効化
	if _left_hand_ik:
		_left_hand_ik.set_enabled(false)

	if _anim_tree:
		_anim_tree.active = false

	var anim_name: String
	match _weapon:
		Weapon.PISTOL:
			anim_name = PISTOL_OPEN_DOOR_ANIM
		_:
			anim_name = RIFLE_OPEN_DOOR_ANIM

	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, 0.15)
		_anim_player.animation_finished.connect(_on_door_open_finished, CONNECT_ONE_SHOT)
		# インパクトタイミングでシグナルを発火するタイマー
		get_tree().create_timer(DOOR_OPEN_IMPACT_TIME).timeout.connect(
			func(): door_open_impact.emit(), CONNECT_ONE_SHOT)
	else:
		push_warning("CharacterAnimationController: Door open animation not found: %s" % anim_name)
		_is_opening_door = false
		if _anim_tree:
			_anim_tree.active = true


func _on_door_open_finished(_anim_name: String) -> void:
	# _is_opening_door は _resume_animation_tree で解除（早期解除すると update_animation が割り込む）

	if _anim_player and not _is_dead:
		var idle_anim_name := _get_idle_anim_name()
		var crossfade_time := 0.3
		if _anim_player.has_animation(idle_anim_name):
			_anim_player.play(idle_anim_name, crossfade_time)
		if _anim_tree:
			get_tree().create_timer(crossfade_time).timeout.connect(_resume_animation_tree, CONNECT_ONE_SHOT)
		else:
			_is_opening_door = false
	else:
		_is_opening_door = false

	door_open_finished.emit()


## Check if door open animation is playing
func is_opening_door() -> bool:
	return _is_opening_door


## Play talking animation (looping, used during hostage negotiation)
func play_talking() -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door or _is_talking:
		return

	_is_talking = true

	# 左手IKを無効化
	if _left_hand_ik:
		_left_hand_ik.set_enabled(false)

	# AnimationTreeを無効化
	if _anim_tree:
		_anim_tree.active = false

	# Talkingアニメーションをループ再生
	var anim_name := GameConstants.ANIM_TALKING
	if _anim_player.has_animation(anim_name):
		var anim_lib := _anim_player.get_animation_library("")
		if anim_lib:
			var anim := anim_lib.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(anim_name, 0.15)
	else:
		push_warning("CharacterAnimationController: Talking animation not found: %s" % anim_name)
		_is_talking = false
		if _anim_tree:
			_anim_tree.active = true


## Stop talking animation and return to idle
func stop_talking() -> void:
	if not _is_talking:
		return

	_is_talking = false

	# スムーズにアイドルへ遷移してからAnimationTreeを再開
	if _anim_player and not _is_dead:
		var idle_anim_name := _get_idle_anim_name()
		var crossfade_time := 0.3
		if _anim_player.has_animation(idle_anim_name):
			_anim_player.play(idle_anim_name, crossfade_time)
		if _anim_tree:
			get_tree().create_timer(crossfade_time).timeout.connect(_resume_animation_tree, CONNECT_ONE_SHOT)


## Check if talking animation is playing
func is_talking() -> bool:
	return _is_talking


## Get current animation state for network synchronization
## Returns encoded state: "move_state,is_firing,blend_x,blend_y"
## move_state: 0=idle, 1=walking, 2=sprinting
func get_animation_state() -> String:
	var move_state := 0
	if _is_sprinting:
		move_state = 2
	elif _movement_blend > 0.1:
		move_state = 1
	var is_firing := 1 if _fire_cooldown > 0 else 0
	var blend_x := int(_input_dir.x * 100)
	var blend_y := int(_input_dir.y * 100)
	return "%d,%d,%d,%d" % [move_state, is_firing, blend_x, blend_y]


## Apply animation state from network (for remote characters)
## state: encoded state string from get_animation_state()
func apply_animation_state(state: String, delta: float) -> void:
	if _is_dead or _is_door_kicking or _is_throwing or _is_opening_door or _is_talking:
		return

	var parts := state.split(",")
	if parts.size() < 4:
		return

	var move_state := parts[0].to_int()
	var is_firing := parts[1].to_int() == 1
	var blend_x := parts[2].to_int() / 100.0
	var blend_y := parts[3].to_int() / 100.0

	# 後方互換: 旧フォーマットの0/1をidle/walkingとして扱う
	var is_moving := move_state > 0
	_is_sprinting = move_state >= 2

	# リモートキャラクター用のcooldown減算（update_animation()が呼ばれないため）
	_fire_cooldown -= delta

	# リモートキャラクターの射撃エフェクト再生
	if is_firing and _fire_cooldown <= 0:
		fire()
	_remote_last_fire_state = is_firing

	# Smooth interpolation for blend values
	var target_movement := 1.0 if is_moving else 0.0
	_movement_blend = lerpf(_movement_blend, target_movement, 1.0 - exp(-10.0 * delta))

	# Sprint blend
	var target_speed := 1.0 if _is_sprinting else 0.0
	_speed_blend = lerpf(_speed_blend, target_speed, 1.0 - exp(-8.0 * delta))

	if is_moving:
		var target_blend := Vector2(blend_x, blend_y)
		_input_dir = _input_dir.lerp(target_blend, 1.0 - exp(-12.0 * delta))
	else:
		if _movement_blend < 0.01:
			_input_dir = Vector2.ZERO

	# Update animation tree
	_update_animation_tree(delta)


#endregion

#region Internal Implementation

## 武器プレフィックスを取得
func _get_weapon_prefix() -> String:
	return "game_rifle" if _weapon != Weapon.PISTOL else "game_pistol"

## 現在の武器のアイドルアニメーション名
func _get_idle_anim_name() -> String:
	return _get_weapon_prefix() + "_idle"

## 現在の武器のアニメーション速度テーブル
func _get_anim_speeds() -> Dictionary:
	return RIFLE_ANIM_SPEEDS if _weapon != Weapon.PISTOL else PISTOL_ANIM_SPEEDS

## ブレンド位置から方向別アニメーション速度を計算（重み付き補間）
func _get_blended_anim_speed(blend_pos: Vector2) -> float:
	var dir := blend_pos.normalized() if blend_pos.length() > 0.01 else Vector2.ZERO
	var s := _get_anim_speeds()
	if dir == Vector2.ZERO:
		return s["fwd"]

	var directions: Array[Vector2] = [
		Vector2(0, 1), Vector2(0, -1),
		Vector2(-1, 0), Vector2(1, 0),
		Vector2(-0.707, 0.707), Vector2(0.707, 0.707),
		Vector2(-0.707, -0.707), Vector2(0.707, -0.707),
	]
	var speeds: Array[float] = [
		s["fwd"], s["bwd"],
		s["left"], s["right"],
		s["fwd_left"], s["fwd_right"],
		s["bwd_left"], s["bwd_right"],
	]

	var total_weight := 0.0
	var blended_speed := 0.0
	for i in range(directions.size()):
		var w := maxf(0.0, dir.dot(directions[i].normalized()))
		w = w * w
		total_weight += w
		blended_speed += w * speeds[i]

	if total_weight > 0.001:
		return blended_speed / total_weight
	return s["fwd"]


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
	_lean_modifier.recovery_speed = lean_speed
	_skeleton.add_child(_lean_modifier)

func _setup_left_hand_ik() -> void:
	var script = load("res://scripts/modifiers/left_hand_ik_modifier.gd")
	if not script:
		push_warning("CharacterAnimationController: left_hand_ik_modifier.gd not found")
		return
	_left_hand_ik = script.new()
	_left_hand_ik.name = "LeftHandIKModifier"
	_model.add_child(_left_hand_ik)  # Nodeとして追加（_process用）
	_left_hand_ik.setup(_skeleton)

func _setup_animation_loops() -> void:
	var loop_anims := [
		# Idle animations
		"game_rifle_idle", "game_pistol_idle",
		# Rifle walk (8 directions)
		"game_rifle_walk_forward", "game_rifle_walk_backward",
		"game_rifle_strafe_left", "game_rifle_strafe_right",
		"game_rifle_strafe_left_45", "game_rifle_strafe_right_45",
		"game_rifle_strafe_left_135", "game_rifle_strafe_right_135",
		# Pistol walk (8 directions)
		"game_pistol_walk_forward", "game_pistol_walk_backward",
		"game_pistol_strafe_left", "game_pistol_strafe_right",
		"game_pistol_strafe_left_45", "game_pistol_strafe_right_45",
		"game_pistol_strafe_left_135", "game_pistol_strafe_right_135",
		# Sprint
		"game_rifle_sprint", "game_pistol_sprint",
	]

	var anim_lib = _anim_player.get_animation_library("")
	for anim_name in loop_anims:
		if _anim_player.has_animation(anim_name):
			var anim = anim_lib.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR


## AnimationTree構造:
## output → ShootOneShot → TimeScale → SpeedBlend → IdleBlend → WalkBlend(単一BlendSpace2D)
##                                       └→ Sprint(単一アニメーション)
##            └→ ShootAnim（上半身フィルター付き）
## ShootOneShotはTimeScaleの上流 = 射撃アニメーション速度がTimeScaleに影響されない
func _setup_animation_tree() -> void:
	# Create or get AnimationTree
	_anim_tree = _model.get_node_or_null(GameConstants.NODE_ANIMATION_TREE) as AnimationTree
	if not _anim_tree:
		_anim_tree = AnimationTree.new()
		_anim_tree.name = GameConstants.NODE_ANIMATION_TREE
		_model.get_parent().add_child(_anim_tree)

	var blend_tree := AnimationNodeBlendTree.new()

	# --- Walk BlendSpace2D (単一、武器切替時にアニメーション名を動的スワップ) ---
	var prefix := _get_weapon_prefix()
	var walk_blend_space := _create_walk_blend_space(prefix)

	# --- Idle animation ---
	var idle_anim := AnimationNodeAnimation.new()
	idle_anim.animation = prefix + "_idle"

	# --- Sprint animation ---
	var sprint_anim := AnimationNodeAnimation.new()
	var sprint_name := prefix + "_sprint"
	if _anim_player.has_animation(sprint_name):
		sprint_anim.animation = sprint_name
	else:
		# SprintLoopがない場合はWalkFwdLoopで代替（TimeScaleで速度調整）
		sprint_anim.animation = prefix + "_walk_forward"

	# --- IdleBlend: 0=Idle, 1=Walk ---
	var idle_blend := AnimationNodeBlend2.new()

	# --- SpeedBlend: 0=Idle+Walk, 1=Sprint ---
	var speed_blend := AnimationNodeBlend2.new()

	# --- TimeScale: 移動アニメーション速度同期 ---
	var time_scale := AnimationNodeTimeScale.new()

	# --- Shoot OneShot (上半身フィルター) ---
	var shoot_anim := AnimationNodeAnimation.new()
	shoot_anim.animation = prefix + "_shoot_once" if _anim_player.has_animation(prefix + "_shoot_once") else ""
	var shoot_oneshot := AnimationNodeOneShot.new()
	shoot_oneshot.fadein_time = 0.05
	shoot_oneshot.fadeout_time = 0.15
	_apply_upper_body_filter(shoot_oneshot)

	# --- Add nodes to blend tree ---
	blend_tree.add_node("Idle", idle_anim, Vector2(-400, 100))
	blend_tree.add_node("WalkBlend", walk_blend_space, Vector2(-400, 300))
	blend_tree.add_node("IdleBlend", idle_blend, Vector2(-50, 200))
	blend_tree.add_node("Sprint", sprint_anim, Vector2(-50, 500))
	blend_tree.add_node("SpeedBlend", speed_blend, Vector2(200, 300))
	blend_tree.add_node("TimeScale", time_scale, Vector2(400, 200))
	blend_tree.add_node("ShootAnim", shoot_anim, Vector2(500, 400))
	blend_tree.add_node("ShootOneShot", shoot_oneshot, Vector2(600, 200))

	# --- Connect: IdleBlend(0=Idle, 1=WalkBlend) ---
	blend_tree.connect_node("IdleBlend", 0, "Idle")
	blend_tree.connect_node("IdleBlend", 1, "WalkBlend")

	# --- Connect: SpeedBlend(0=IdleBlend, 1=Sprint) ---
	blend_tree.connect_node("SpeedBlend", 0, "IdleBlend")
	blend_tree.connect_node("SpeedBlend", 1, "Sprint")

	# --- Connect: TimeScale → SpeedBlend ---
	blend_tree.connect_node("TimeScale", 0, "SpeedBlend")

	# --- Connect: ShootOneShot(base=TimeScale, oneshot=ShootAnim) ---
	blend_tree.connect_node("ShootOneShot", 0, "TimeScale")
	blend_tree.connect_node("ShootOneShot", 1, "ShootAnim")

	# --- Connect: output → ShootOneShot ---
	blend_tree.connect_node("output", 0, "ShootOneShot")

	_anim_tree.tree_root = blend_tree
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.clear_caches()
	_anim_tree.active = true


## WalkBlend用BlendSpace2D作成
## Forward=(0,1), Backward=(0,-1) (animation_testの座標系)
func _create_walk_blend_space(prefix: String) -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	blend_space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	blend_space.auto_triangles = true
	blend_space.min_space = Vector2(-1, -1)
	blend_space.max_space = Vector2(1, 1)
	blend_space.sync = true

	# 8方向: position → animation name
	# Forward=(0,1), FwdRight=(0.707,0.707), Right=(1,0), BwdRight=(0.707,-0.707)
	# Backward=(0,-1), BwdLeft=(-0.707,-0.707), Left=(-1,0), FwdLeft=(-0.707,0.707)
	var walk_points := {
		Vector2(0, 1): prefix + "_walk_forward",
		Vector2(0.707, 0.707): prefix + "_strafe_right_45",
		Vector2(1, 0): prefix + "_strafe_right",
		Vector2(0.707, -0.707): prefix + "_strafe_right_135",
		Vector2(0, -1): prefix + "_walk_backward",
		Vector2(-0.707, -0.707): prefix + "_strafe_left_135",
		Vector2(-1, 0): prefix + "_strafe_left",
		Vector2(-0.707, 0.707): prefix + "_strafe_left_45",
	}

	for pos in walk_points:
		var anim_name: String = walk_points[pos]
		if _anim_player.has_animation(anim_name):
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			blend_space.add_blend_point(anim_node, pos)

	return blend_space


## 武器切替時にアニメーション名を動的スワップ
func _switch_weapon_animations() -> void:
	if not _anim_tree or not _anim_tree.active:
		return

	var bt := _anim_tree.tree_root as AnimationNodeBlendTree
	if not bt:
		return

	var prefix := _get_weapon_prefix()

	# Idle
	var idle_node := bt.get_node("Idle") as AnimationNodeAnimation
	if idle_node:
		idle_node.animation = prefix + "_idle"

	# Sprint
	var sprint_node := bt.get_node("Sprint") as AnimationNodeAnimation
	if sprint_node:
		var sprint_name := prefix + "_sprint"
		if not _anim_player.has_animation(sprint_name):
			sprint_name = prefix + "_walk_forward"
		sprint_node.animation = sprint_name

	# Shoot
	var shoot_node := bt.get_node("ShootAnim") as AnimationNodeAnimation
	if shoot_node:
		var shoot_name := prefix + "_shoot_once"
		shoot_node.animation = shoot_name if _anim_player.has_animation(shoot_name) else ""

	# WalkBlend (BlendSpace2D) - 8方向のアニメーション名を更新
	var walk_blend := bt.get_node("WalkBlend") as AnimationNodeBlendSpace2D
	if walk_blend:
		var walk_anims := [
			prefix + "_walk_forward",
			prefix + "_strafe_right_45",
			prefix + "_strafe_right",
			prefix + "_strafe_right_135",
			prefix + "_walk_backward",
			prefix + "_strafe_left_135",
			prefix + "_strafe_left",
			prefix + "_strafe_left_45",
		]
		for i in range(mini(walk_anims.size(), walk_blend.get_blend_point_count())):
			var anim_node := walk_blend.get_blend_point_node(i) as AnimationNodeAnimation
			if anim_node:
				anim_node.animation = walk_anims[i]


## Apply upper body bone filter to an AnimationNode (e.g. OneShot)
func _apply_upper_body_filter(node: AnimationNode) -> void:
	if not _skeleton:
		return

	# Find the bone track path prefix from actual animation data
	var prefix := _detect_bone_track_prefix()
	if prefix.is_empty():
		return

	# Get all upper body bones (Spine and its descendants)
	var spine_idx := _skeleton.find_bone("Spine")
	if spine_idx < 0:
		# Fallback: try other bone names
		for bone_name in ["UpperChest", "Chest", "Spine1"]:
			spine_idx = _skeleton.find_bone(bone_name)
			if spine_idx >= 0:
				break
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
	# ARP/Unity Humanoidボーン名で検索
	var search_bones := [":Spine", ":Chest", ":RightHand", ":Hips", ":UpperChest"]
	for anim_name in anim_lib.get_animation_list():
		var anim := anim_lib.get_animation(anim_name)
		for i in range(anim.get_track_count()):
			var path_str := str(anim.track_get_path(i))
			for search_bone in search_bones:
				var colon_idx := path_str.find(search_bone)
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
		# -look_dir 必須！（モデル+Z前方向 vs looking_at -Z前方向）
		var target_basis := Basis.looking_at(-look_dir.normalized(), Vector3.UP)
		var target_quat := target_basis.get_rotation_quaternion()
		var current_quat := Quaternion(_model.transform.basis)
		var new_quat := current_quat.slerp(target_quat, rotation_speed * delta)
		_model.transform.basis = Basis(new_quat)

func _update_lean(movement_direction: Vector3, aim_direction: Vector3, delta: float) -> void:
	var target_lean := 0.0

	# --- 移動方向ベースのリーン（既存） ---
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

	# --- 方向転換ベースのリーン（ターンリーン） ---
	var aim_dir := aim_direction
	aim_dir.y = 0
	if aim_dir.length_squared() > 0.001 and _prev_aim_for_turn.length_squared() > 0.001:
		var cur := aim_dir.normalized()
		var prev := _prev_aim_for_turn.normalized()
		var angle_diff := prev.signed_angle_to(cur, Vector3.UP)
		var angular_vel := angle_diff / maxf(delta, 0.001)
		# 角速度のみスムージング（ノイズ除去）
		_smoothed_angular_vel = lerpf(_smoothed_angular_vel, angular_vel, 1.0 - exp(-turn_lean_smoothing * delta))
	else:
		_smoothed_angular_vel = lerpf(_smoothed_angular_vel, 0.0, 1.0 - exp(-turn_lean_smoothing * delta))
	# 回転方向にリーン、直接target_leanに加算
	var max_turn := deg_to_rad(turn_lean_degrees)
	target_lean += clampf(_smoothed_angular_vel / turn_lean_angular_ref, -1.0, 1.0) * max_turn

	if aim_direction.length_squared() > 0.001:
		_prev_aim_for_turn = aim_direction

	_lean_amount = lerpf(_lean_amount, target_lean, 1.0 - exp(-lean_speed * delta))
	if _lean_modifier and _lean_modifier.has_method("set_target_lean"):
		_lean_modifier.set_target_lean(_lean_amount)

func _update_strafe_blend(movement_direction: Vector3, delta: float) -> void:
	var move_dir := movement_direction
	move_dir.y = 0

	if move_dir.length() > 0.1:
		# ターゲットのエイム方向を使用（SLERP途中のモデル回転ではなく）
		var char_forward := _aim_direction
		char_forward.y = 0
		if char_forward.length_squared() < 0.001:
			char_forward = _model.global_transform.basis.z
		var angle := char_forward.signed_angle_to(move_dir.normalized(), Vector3.UP)

		# 45度量子化（ジッターアニメーション切替防止）
		angle = round(angle / (PI / 4.0)) * (PI / 4.0)

		# Forward=(0,1) 座標系（signed_angle_toはatan2と符号が逆のためX反転）
		var target_blend := Vector2(-sin(angle), cos(angle))

		# ブレンド補間速度を変化量に応じて適応的に調整
		var blend_diff := target_blend.distance_to(_input_dir)
		if blend_diff > 1.0:
			_input_dir = target_blend
		else:
			var blend_speed := lerpf(12.0, 40.0, clampf(blend_diff * 2.0, 0.0, 1.0))
			_input_dir = _input_dir.lerp(target_blend, 1.0 - exp(-blend_speed * delta))
		_movement_blend = lerpf(_movement_blend, 1.0, 1.0 - exp(-10.0 * delta))
	else:
		# 停止時: アイドルへフェード
		_movement_blend = lerpf(_movement_blend, 0.0, 1.0 - exp(-8.0 * delta))
		if _movement_blend < 0.01:
			_input_dir = Vector2.ZERO

func _update_animation_tree(delta: float = 0.016) -> void:
	if not _anim_tree or not _anim_tree.active:
		return

	# Update walk blend position
	if _movement_blend > 0.01:
		_anim_tree.set("parameters/WalkBlend/blend_position", _input_dir)

	# IdleBlend: 0=idle, 1=walk (スプリント中はIdleBlend=0にして、SpeedBlendで切替)
	var target_idle := 1.0 if _movement_blend > 0.1 and not _is_sprinting else 0.0
	var current_idle: float = _anim_tree.get("parameters/IdleBlend/blend_amount")
	_anim_tree.set("parameters/IdleBlend/blend_amount", lerpf(current_idle, target_idle, 8.0 * delta))

	# SpeedBlend: 0=idle+walk, 1=sprint
	var target_speed := 1.0 if _is_sprinting else 0.0
	_speed_blend = lerpf(_speed_blend, target_speed, 1.0 - exp(-8.0 * delta))
	_anim_tree.set("parameters/SpeedBlend/blend_amount", _speed_blend)

	# TimeScale: 速度同期
	_update_time_scale()


## TimeScale速度同期
func _update_time_scale() -> void:
	if not _anim_tree:
		return

	var actual_speed: float
	if _is_sprinting:
		actual_speed = SPRINT_SPEED
	elif _movement_blend > 0.1:
		actual_speed = WALK_SPEED
	else:
		_anim_tree.set("parameters/TimeScale/scale", 1.0)
		return

	var time_scale := 1.0
	if _speed_blend < 0.5:
		# Walk mode: 方向別速度で同期
		var walk_pos: Vector2 = _anim_tree.get("parameters/WalkBlend/blend_position")
		var blended_natural := _get_blended_anim_speed(walk_pos)
		if blended_natural > 0.01:
			time_scale = actual_speed / blended_natural
	else:
		# Sprint mode: スプリント速度で同期
		var sprint_speed: float = _get_anim_speeds()["sprint"]
		if sprint_speed > 0.01:
			time_scale = actual_speed / sprint_speed

	_anim_tree.set("parameters/TimeScale/scale", time_scale)

#endregion
