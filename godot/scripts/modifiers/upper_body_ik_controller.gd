extends Node
class_name UpperBodyIKController
## 上半身IK統合コントローラー
##
## 右腕IK（TwoBoneIK3D）、左腕IK（LeftHandIKModifier）、SpineAimModifier を一元管理。
## 下半身（脚）は既存の AnimationTree 駆動を維持し、上半身のみ IK で制御する。
##
## 武器は RightHand BoneAttachment に追従。右腕 IK ターゲットはゲームステートから計算。
## 左手は武器の LeftHandGrip に IK 追従。循環参照なし。

# ============================================
# Constants
# ============================================
const DEFAULT_BLEND_SPEED := 15.0  ## デフォルト influence 遷移速度
const ACTION_BLEND_SPEED := 5.0    ## アクション復帰時のゆっくりブレンド速度
const RIGHT_POLE_OFFSET := 0.3     ## 右肘ポール外側オフセット

## 右手 IK ターゲット位置（スケルトンローカル座標）
const READY_RIGHT_HAND_POS := Vector3(0.2, 0.7, 0.25)
const GUN_DOWN_RIGHT_HAND_POS := Vector3(0.2, 0.4, 0.1)

## GunDown 時のポーズリーン（やや前傾、ラジアン）
const GUN_DOWN_POSE_LEAN := 0.15

# ============================================
# State
# ============================================
var _skeleton: Skeleton3D
var _right_arm_ik: TwoBoneIK3D
var _right_ik_target: Marker3D
var _right_ik_pole: Marker3D
var _left_hand_ik: LeftHandIKModifier
var _spine_modifier: SpineAimModifier

var _target_right_influence := 1.0
var _right_blend_speed := DEFAULT_BLEND_SPEED
var _right_hand_target_pos := READY_RIGHT_HAND_POS  ## 現在のターゲット位置
var _right_hand_lerp_pos := READY_RIGHT_HAND_POS    ## 補間中の位置
var _weapon_ik_offset := Vector3.ZERO  ## 武器固有のオフセット
var _is_gun_down := false
var _is_pistol := false
var _is_setup := false

# ============================================
# Setup
# ============================================

## IK ノードを生成しスケルトンに追加
## skeleton: キャラクターの Skeleton3D
func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	if not _skeleton:
		return

	# 順序重要: SpineAimModifier → RightArmIK → LeftHandIK → (RecoilModifier は外部で追加)
	_setup_spine_modifier()
	_setup_right_arm_ik()
	_setup_left_hand_ik()

	_is_setup = true
	_target_right_influence = 1.0


func _setup_spine_modifier() -> void:
	_spine_modifier = SpineAimModifier.new()
	_spine_modifier.name = "SpineAimModifier"
	_spine_modifier.active = true
	_skeleton.add_child(_spine_modifier)


func _setup_right_arm_ik() -> void:
	# ターゲット Marker3D
	_right_ik_target = Marker3D.new()
	_right_ik_target.name = "RightHandIKTarget"
	_skeleton.add_child(_right_ik_target)

	# ポール Marker3D（肘方向制御）
	_right_ik_pole = Marker3D.new()
	_right_ik_pole.name = "RightHandIKPole"
	_skeleton.add_child(_right_ik_pole)

	# TwoBoneIK3D
	_right_arm_ik = TwoBoneIK3D.new()
	_right_arm_ik.name = "RightArmIK"
	_right_arm_ik.influence = 0.0  # _process で段階的にブレンドイン
	_right_arm_ik.active = true
	_skeleton.add_child(_right_arm_ik)

	# IK チェーン設定（ツリーに追加後に行う）
	_right_arm_ik.setting_count = 1
	_right_arm_ik.set_root_bone_name(0, GameConstants.BONE_RIGHT_ARM)
	_right_arm_ik.set_middle_bone_name(0, GameConstants.BONE_RIGHT_FOREARM)
	_right_arm_ik.set_end_bone_name(0, GameConstants.BONE_RIGHT_HAND)
	_right_arm_ik.set_target_node(0, _right_arm_ik.get_path_to(_right_ik_target))
	_right_arm_ik.set_pole_node(0, _right_arm_ik.get_path_to(_right_ik_pole))

	if _right_arm_ik.has_method("reset"):
		_right_arm_ik.reset()


func _setup_left_hand_ik() -> void:
	_left_hand_ik = LeftHandIKModifier.new()
	_left_hand_ik.name = "LeftHandIKModifier"
	add_child(_left_hand_ik)  # UpperBodyIKController の子として追加（_process 用）
	_left_hand_ik.setup(_skeleton)

# ============================================
# Control API
# ============================================

## 左手グリップ設定（武器の LeftHandGrip ノード）
func set_left_grip(grip_node: Node3D) -> void:
	if not _left_hand_ik:
		return
	if grip_node:
		_left_hand_ik.set_grip_source(grip_node)
		if not _is_pistol:
			_left_hand_ik.set_enabled(true)
	else:
		_left_hand_ik.clear_grip_source()


## 左手グリップが設定されているか
func has_left_grip() -> bool:
	return _left_hand_ik and _left_hand_ik.has_grip_source()


## 武器タイプ変更（ピストル切替）
func set_is_pistol(pistol: bool) -> void:
	_is_pistol = pistol
	if _left_hand_ik:
		if pistol:
			_left_hand_ik.set_enabled(false)
		elif _left_hand_ik.has_grip_source():
			_left_hand_ik.set_enabled(true)


## Gun down 状態の設定
func set_gun_down(value: bool) -> void:
	_is_gun_down = value
	if value:
		_right_hand_target_pos = GUN_DOWN_RIGHT_HAND_POS
		if _left_hand_ik:
			_left_hand_ik.set_enabled(false)
		if _spine_modifier:
			_spine_modifier.set_pose_lean(GUN_DOWN_POSE_LEAN)
	else:
		_right_hand_target_pos = READY_RIGHT_HAND_POS + _weapon_ik_offset
		if _left_hand_ik and not _is_pistol and _left_hand_ik.has_grip_source():
			_left_hand_ik.set_enabled(true)
		if _spine_modifier:
			_spine_modifier.set_pose_lean(0.0)


## Gun down 状態か
func is_gun_down() -> bool:
	return _is_gun_down


## 武器固有の右手 IK オフセット設定
func set_weapon_ik_offset(offset: Vector3) -> void:
	_weapon_ik_offset = offset
	if not _is_gun_down:
		_right_hand_target_pos = READY_RIGHT_HAND_POS + offset


## アクションアニメーション前に全 IK を無効化
func disable_for_action() -> void:
	_target_right_influence = 0.0
	if _left_hand_ik:
		_left_hand_ik.set_enabled(false)


## アクション後に IK を段階的に復帰（ゆっくりブレンドイン）
func resume_after_action() -> void:
	_right_blend_speed = ACTION_BLEND_SPEED
	_target_right_influence = 1.0
	if _left_hand_ik:
		_left_hand_ik.set_blend_speed(ACTION_BLEND_SPEED)
		if not _is_pistol and _left_hand_ik.has_grip_source():
			_left_hand_ik.set_enabled(true)


## ブレンド速度をデフォルトに戻す
func reset_blend_speed() -> void:
	_right_blend_speed = DEFAULT_BLEND_SPEED
	if _left_hand_ik:
		_left_hand_ik.reset_blend_speed()


## 死亡時の即座無効化
func disable_immediate() -> void:
	_target_right_influence = 0.0
	if _right_arm_ik:
		_right_arm_ik.influence = 0.0
	if _left_hand_ik:
		_left_hand_ik.disable_immediate()

# ============================================
# Process
# ============================================

func _process(delta: float) -> void:
	if not _is_setup or not _right_arm_ik:
		return

	_update_right_arm_influence(delta)
	_update_right_arm_target(delta)
	_update_right_arm_pole()


func _update_right_arm_influence(delta: float) -> void:
	var current := _right_arm_ik.influence
	if absf(current - _target_right_influence) > 0.001:
		_right_arm_ik.influence = lerpf(current, _target_right_influence, 1.0 - exp(-_right_blend_speed * delta))
	elif current != _target_right_influence:
		_right_arm_ik.influence = _target_right_influence

	# ブレンド完了後にデフォルト速度に戻す
	if absf(_right_arm_ik.influence - _target_right_influence) < 0.01:
		_right_blend_speed = DEFAULT_BLEND_SPEED


func _update_right_arm_target(delta: float) -> void:
	if _right_arm_ik.influence < 0.001:
		return

	# ターゲット位置を滑らかに補間
	_right_hand_lerp_pos = _right_hand_lerp_pos.lerp(
		_right_hand_target_pos, 1.0 - exp(-DEFAULT_BLEND_SPEED * delta)
	)

	# スケルトンローカル座標をグローバル座標に変換
	var target_global := _skeleton.global_transform * Transform3D(Basis.IDENTITY, _right_hand_lerp_pos)
	_right_ik_target.global_position = target_global.origin


func _update_right_arm_pole() -> void:
	if _right_arm_ik.influence < 0.001 or not _right_ik_pole:
		return

	var root_bone_idx := _skeleton.find_bone(GameConstants.BONE_RIGHT_ARM)
	if root_bone_idx < 0:
		return

	var root_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(root_bone_idx)
	var target_pos := _right_ik_target.global_position
	var mid := (root_global.origin + target_pos) * 0.5

	# 右肘は外側（キャラの右方向）後方を向く
	var char_right := _skeleton.global_transform.basis.x.normalized()
	var char_back := -_skeleton.global_transform.basis.z.normalized()
	_right_ik_pole.global_position = mid + (char_right + char_back * 0.5).normalized() * RIGHT_POLE_OFFSET

# ============================================
# Cleanup
# ============================================

func _exit_tree() -> void:
	# スケルトン上のノードをクリーンアップ
	for node in [_right_arm_ik, _right_ik_target, _right_ik_pole, _spine_modifier]:
		if node and is_instance_valid(node):
			node.queue_free()
	# LeftHandIKModifier は子ノードとして自動的に解放される（_exit_tree でスケルトン上のノードも解放）
