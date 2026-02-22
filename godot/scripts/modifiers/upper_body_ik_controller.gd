extends Node
class_name UpperBodyIKController

## Upper body IK integrated controller
##
## 上半身を完全にIKで制御する統合コントローラー。
## RightArmIK + LeftHandIK + SpinePosture + HeadLookAt + IKRecoil を一元管理。
## IKのinfluence=1.0がアニメーションポーズを上書きするため、
## AnimationTreeへの上半身フィルター設定は不要。

# ============================================
# Enums
# ============================================
enum IKState { READY, GUN_UP, ACTION, DISABLED }

# ============================================
# IK Position Constants (character origin-relative, +Z forward)
# ============================================
const RIFLE_READY_HAND := Vector3(-0.19, 1.39, 0.13)
const RIFLE_READY_POLE := Vector3(-0.22, 1.13, -0.06)
const PISTOL_READY_HAND := Vector3(-0.15, 1.36, 0.23)
const PISTOL_READY_POLE := Vector3(-0.22, 0.99, -0.06)
const GUN_UP_HAND := Vector3(-0.15, 1.55, 0.03)
const GUN_UP_POLE := Vector3(-0.22, 1.25, -0.10)

## 状態遷移速度
const STATE_TRANSITION_SPEED := 8.0
## HeadLookAt追従速度
const HEAD_LOOK_SPEED := 10.0
## HeadLookAtターゲット距離（前方に配置）
const HEAD_LOOK_DISTANCE := 5.0

# ============================================
# References
# ============================================
var _skeleton: Skeleton3D
var _model: Node3D  ## CharacterModel
var _right_arm_ik: TwoBoneIK3D
var _right_hand_target: Marker3D
var _right_hand_pole: Marker3D
var _head_look_at: LookAtModifier3D
var _head_look_target: Marker3D
var _spine_posture: SpinePostureModifier
var _recoil_ctrl: IKRecoilController
var _left_hand_ik: LeftHandIKModifier
var _ik_action_player: Node = null  ## IKActionPlayer (set externally)

# ============================================
# State
# ============================================
var _state := IKState.READY
var _weapon_type := 0  ## CharacterAnimationController.Weapon value
var _weapon_ik_offset := Vector3.ZERO  ## WeaponPreset.right_hand_ik_offset
var _current_hand_pos := RIFLE_READY_HAND
var _current_pole_pos := RIFLE_READY_POLE
var _aim_direction := Vector3.FORWARD
var _is_setup := false

# ============================================
# Setup
# ============================================

## 初期化: Skeleton3DとCharacterModelを渡してIKノードを構築
func setup(skeleton: Skeleton3D, model: Node3D, left_hand_ik: LeftHandIKModifier) -> void:
	_skeleton = skeleton
	_model = model
	_left_hand_ik = left_hand_ik

	if not _skeleton:
		push_warning("UpperBodyIKController: Skeleton3D is null")
		return

	# --- SpinePostureModifier ---
	_spine_posture = SpinePostureModifier.new()
	_spine_posture.name = "SpinePostureModifier"
	_spine_posture.active = true
	_skeleton.add_child(_spine_posture)

	# --- Right Arm IK (TwoBoneIK3D) ---
	_right_hand_target = Marker3D.new()
	_right_hand_target.name = "RightHandIKTarget"
	_skeleton.add_child(_right_hand_target)

	_right_hand_pole = Marker3D.new()
	_right_hand_pole.name = "RightHandIKPole"
	_skeleton.add_child(_right_hand_pole)

	_right_arm_ik = TwoBoneIK3D.new()
	_right_arm_ik.name = "RightArmIK"
	_right_arm_ik.influence = 1.0
	_right_arm_ik.active = true
	_skeleton.add_child(_right_arm_ik)

	# IK chain setup (must be done after adding to tree)
	_right_arm_ik.setting_count = 1
	_right_arm_ik.set_root_bone_name(0, GameConstants.BONE_RIGHT_ARM)
	_right_arm_ik.set_middle_bone_name(0, GameConstants.BONE_RIGHT_FOREARM)
	_right_arm_ik.set_end_bone_name(0, GameConstants.BONE_RIGHT_HAND)
	_right_arm_ik.set_target_node(0, _right_arm_ik.get_path_to(_right_hand_target))
	_right_arm_ik.set_pole_node(0, _right_arm_ik.get_path_to(_right_hand_pole))

	# --- HeadLookAt (LookAtModifier3D) ---
	_head_look_target = Marker3D.new()
	_head_look_target.name = "HeadLookTarget"
	_model.add_child(_head_look_target)
	# 初期位置を前方に配置
	_head_look_target.position = Vector3(0, 1.5, HEAD_LOOK_DISTANCE)

	_head_look_at = LookAtModifier3D.new()
	_head_look_at.name = "HeadLookAt"
	_head_look_at.active = true
	_head_look_at.bone_name = GameConstants.BONE_HEAD
	_skeleton.add_child(_head_look_at)
	# target_nodeはツリーに追加後に設定（get_path_toにcommon_parentが必要）
	_head_look_at.target_node = _head_look_at.get_path_to(_head_look_target)

	# --- IKRecoilController ---
	_recoil_ctrl = IKRecoilController.new()
	_recoil_ctrl.name = "IKRecoilController"
	add_child(_recoil_ctrl)

	# Set initial hand position
	_current_hand_pos = RIFLE_READY_HAND
	_current_pole_pos = RIFLE_READY_POLE
	_update_ik_targets_immediate()

	_is_setup = true


# ============================================
# Public API
# ============================================

## IK状態を設定
func set_state(new_state: IKState) -> void:
	if _state == new_state:
		return
	_state = new_state

	match new_state:
		IKState.DISABLED:
			_set_ik_active(false)
		IKState.ACTION:
			pass  # IKActionPlayerが制御
		_:
			_set_ik_active(true)


## 武器タイプを設定（CharacterAnimationController.Weapon値）
func set_weapon(weapon_type: int) -> void:
	_weapon_type = weapon_type
	# ピストルは左手IK無効
	if _left_hand_ik:
		_left_hand_ik.set_enabled(weapon_type != 2 and _left_hand_ik.has_grip_source())  # 2 = PISTOL


## 武器固有のIKオフセットを設定
func set_weapon_ik_offset(offset: Vector3) -> void:
	_weapon_ik_offset = offset


## エイム方向を設定
func set_aim_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		_aim_direction = direction.normalized()


## リコイルを発動
func trigger_recoil(strength: float) -> void:
	if _recoil_ctrl:
		_recoil_ctrl.trigger_recoil(strength)


## 姿勢リーンを設定（SpinePostureModifierに伝播）
func set_posture_lean(roll: float) -> void:
	if _spine_posture:
		_spine_posture.set_roll(roll)


## 姿勢ピッチを設定（エイム前傾用）
func set_posture_pitch(pitch: float) -> void:
	if _spine_posture:
		_spine_posture.set_pitch(pitch)


## 左手グリップソースを設定
func set_left_hand_grip(grip_node: Node3D) -> void:
	if not _left_hand_ik:
		return
	if grip_node:
		_left_hand_ik.set_grip_source(grip_node)
		if _weapon_type != 2:  # PISTOL
			_left_hand_ik.set_enabled(true)
	else:
		_left_hand_ik.clear_grip_source()


## 左手IKの有効/無効を直接制御
func set_left_hand_ik_enabled(enabled: bool) -> void:
	if _left_hand_ik:
		_left_hand_ik.set_enabled(enabled)


## 左手IKのブレンド速度を設定
func set_left_hand_blend_speed(speed: float) -> void:
	if _left_hand_ik:
		_left_hand_ik.set_blend_speed(speed)


## 左手IKのブレンド速度をリセット
func reset_left_hand_blend_speed() -> void:
	if _left_hand_ik:
		_left_hand_ik.reset_blend_speed()


## IKActionPlayerを設定
func set_action_player(action_player: Node) -> void:
	_ik_action_player = action_player


## 右手IKターゲット位置を直接設定（IKActionPlayerから使用）
func set_right_hand_target_position(pos: Vector3) -> void:
	_current_hand_pos = pos


## 右手IKポール位置を直接設定（IKActionPlayerから使用）
func set_right_hand_pole_position(pos: Vector3) -> void:
	_current_pole_pos = pos


## 右手IKのinfluenceを取得
func get_right_arm_influence() -> float:
	if _right_arm_ik:
		return _right_arm_ik.influence
	return 0.0


## IKを即座に無効化（死亡時など）
func disable_immediate() -> void:
	_state = IKState.DISABLED
	_set_ik_active(false)
	if _left_hand_ik:
		_left_hand_ik.disable_immediate()
	if _recoil_ctrl:
		_recoil_ctrl.reset()


## LeftHandIKModifierの参照を取得
func get_left_hand_ik() -> LeftHandIKModifier:
	return _left_hand_ik


## セットアップ済みかどうか
func is_setup() -> bool:
	return _is_setup


# ============================================
# Update (called every frame from CharacterAnimationController)
# ============================================

func update(delta: float) -> void:
	if not _is_setup or _state == IKState.DISABLED:
		return

	# Update recoil
	if _recoil_ctrl:
		_recoil_ctrl.update(delta)

	# ACTION状態ではIKActionPlayerが位置を直接制御するため、
	# 通常のターゲット計算をスキップ
	if _state == IKState.ACTION:
		_update_ik_targets(delta)
		_update_head_look_target(delta)
		return

	# Calculate target hand/pole positions based on state
	var target_hand := _get_state_hand_position()
	var target_pole := _get_state_pole_position()

	# Add weapon-specific offset
	target_hand += _weapon_ik_offset

	# Add recoil offset
	if _recoil_ctrl:
		target_hand += _recoil_ctrl.get_recoil_offset()

	# Smooth transition
	_current_hand_pos = _current_hand_pos.lerp(target_hand, 1.0 - exp(-STATE_TRANSITION_SPEED * delta))
	_current_pole_pos = _current_pole_pos.lerp(target_pole, 1.0 - exp(-STATE_TRANSITION_SPEED * delta))

	# Apply to IK targets
	_update_ik_targets(delta)

	# Update head look target
	_update_head_look_target(delta)


# ============================================
# Internal
# ============================================

## 現在の状態に応じた手の目標位置を取得
func _get_state_hand_position() -> Vector3:
	match _state:
		IKState.GUN_UP:
			return GUN_UP_HAND
		_:
			# READY: 武器タイプに応じた位置
			if _weapon_type == 2:  # PISTOL
				return PISTOL_READY_HAND
			return RIFLE_READY_HAND


## 現在の状態に応じたポールの目標位置を取得
func _get_state_pole_position() -> Vector3:
	match _state:
		IKState.GUN_UP:
			return GUN_UP_POLE
		_:
			if _weapon_type == 2:  # PISTOL
				return PISTOL_READY_POLE
			return RIFLE_READY_POLE


## IKターゲットのワールド位置を更新
func _update_ik_targets(_delta: float) -> void:
	if not _model or not _right_hand_target or not _right_hand_pole:
		return

	# キャラクター原点基準 → ワールド座標変換
	var char_pos := _model.global_position
	var model_basis := _model.global_transform.basis

	_right_hand_target.global_position = char_pos + model_basis * _current_hand_pos
	_right_hand_pole.global_position = char_pos + model_basis * _current_pole_pos


## IKターゲット位置を即座に設定（初期化時）
func _update_ik_targets_immediate() -> void:
	if not _model or not _right_hand_target or not _right_hand_pole:
		return
	var char_pos := _model.global_position
	var model_basis := _model.global_transform.basis
	_right_hand_target.global_position = char_pos + model_basis * _current_hand_pos
	_right_hand_pole.global_position = char_pos + model_basis * _current_pole_pos


## HeadLookAtターゲット位置を更新
func _update_head_look_target(_delta: float) -> void:
	if not _model or not _head_look_target:
		return

	# エイム方向にターゲットを配置（モデルのローカル空間で+Z前方）
	var aim_local := _model.global_transform.basis.inverse() * _aim_direction
	aim_local.y = 0
	if aim_local.length_squared() < 0.001:
		aim_local = Vector3.FORWARD
	aim_local = aim_local.normalized()

	var target_pos := Vector3(aim_local.x, 1.5, aim_local.z) * HEAD_LOOK_DISTANCE
	_head_look_target.position = _head_look_target.position.lerp(target_pos, 1.0 - exp(-HEAD_LOOK_SPEED * _delta))


## IKノードの有効/無効を設定
func _set_ik_active(active: bool) -> void:
	if _right_arm_ik:
		_right_arm_ik.influence = 1.0 if active else 0.0
	if _head_look_at:
		_head_look_at.influence = 1.0 if active else 0.0
	if _spine_posture:
		_spine_posture.active = active


# ============================================
# Cleanup
# ============================================

func _exit_tree() -> void:
	# Marker3Dとmodifierはskeletonの子なので、skeletonが解放されれば自動的に解放される
	# ここでは参照のクリアのみ
	_right_arm_ik = null
	_right_hand_target = null
	_right_hand_pole = null
	_head_look_at = null
	_head_look_target = null
	_spine_posture = null
	_recoil_ctrl = null
	_left_hand_ik = null
