extends Node
class_name SpineIKController

## Spine IK controller using Godot 4.6 CCDIK3D + BoneTwistDisperser3D
##
## 購入アセット "GODOT 4.6 - NEW IK AIM" のスパインIKアプローチを実装。
## CCDIK3Dが背骨チェーン（Spine→Head）を動的にターゲットへ追従させ、
## BoneTwistDisperser3Dがツイストを自然に分配する。
## 4方向ブレンド+スパインIKで8方向ストレイフを再現する。

# ============================================
# Constants
# ============================================

## TargetPivot高さ（キャラクター原点基準、Spine～UpperChest中間付近）
const PIVOT_HEIGHT := 1.2

## SpineIKTarget位置（TargetPivot相対: Y=Head高さ付近, Z=前方オフセット）
const TARGET_OFFSET := Vector3(0, 0.9, 0.15)

## ヨー回転のスムージング速度
const SMOOTHING_SPEED := 10.0

## CCDIK joint制限角度（rad）— 購入アセットの値を基準
## Joint 0 (Spine): ≈54°, Joint 1 (Chest): ≈29°,
## Joint 2 (UpperChest): ≈32°, Joint 3 (Neck): ≈14°
## Joint 4 (Head): 制限なし
const JOINT_LIMITS: Array[float] = [
	0.9425,  # Spine
	0.5027,  # Chest
	0.5655,  # UpperChest
	0.2513,  # Neck
	# Head: no limitation
]

# ============================================
# References
# ============================================
var _skeleton: Skeleton3D
var _model: Node3D
var _character_root: Node3D
var _target_pivot: Marker3D
var _spine_target: Marker3D
var _ccdik: CCDIK3D
var _twist_disperser: BoneTwistDisperser3D

# ============================================
# State
# ============================================
var _target_yaw := 0.0
var _current_yaw := 0.0
var _is_setup := false
var _enabled := false

# ============================================
# Setup
# ============================================

## 初期化: Skeleton3D, CharacterModel, GameCharacterを渡してIKノードを構築
func setup(skeleton: Skeleton3D, model: Node3D, character_root: Node3D) -> void:
	_skeleton = skeleton
	_model = model
	_character_root = character_root

	if not _skeleton or not _model or not _character_root:
		push_warning("SpineIKController: Required nodes are null")
		return

	_create_target_pivot()
	_create_ccdik()
	_create_twist_disperser()

	# 初期状態は無効 — FOUR_DIR_IKモード有効化時にset_enabled(true)
	set_enabled(false)
	_is_setup = true


func _create_target_pivot() -> void:
	# TargetPivot: キャラクタールートの子として配置
	_target_pivot = Marker3D.new()
	_target_pivot.name = "SpineIKTargetPivot"
	_target_pivot.visible = false
	_character_root.add_child(_target_pivot)

	# SpineIKTarget: TargetPivotの子（前方オフセット位置）
	_spine_target = Marker3D.new()
	_spine_target.name = "SpineIKTarget"
	_spine_target.position = TARGET_OFFSET
	_target_pivot.add_child(_spine_target)


func _create_ccdik() -> void:
	_ccdik = CCDIK3D.new()
	_ccdik.name = "SpineCCDIK"
	_ccdik.influence = 0.0
	_skeleton.add_child(_ccdik)

	# CCDIK settings: Spine → Head, 5 joints
	_ccdik.setting_count = 1
	_ccdik.set("settings/0/root_bone_name", GameConstants.BONE_SPINE)
	_ccdik.set("settings/0/end_bone_name", GameConstants.BONE_HEAD)
	_ccdik.set("settings/0/target_node", _ccdik.get_path_to(_spine_target))
	_ccdik.set("settings/0/extend_end_bone", false)
	_ccdik.set("settings/0/joint_count", 5)

	# Joint設定: 各ジョイントにCone制限を設定
	for i in range(5):
		_ccdik.set("settings/0/joints/%d/rotation_axis" % i, 3)  # ALL axes
		if i < JOINT_LIMITS.size():
			var cone := JointLimitationCone3D.new()
			cone.angle = JOINT_LIMITS[i]
			_ccdik.set("settings/0/joints/%d/limitation" % i, cone)
		# Joint 4 (Head): limitation = null (default, no restriction)

	# SpinePostureModifier/HeadRotationModifierの前に配置
	_skeleton.move_child(_ccdik, 0)


func _create_twist_disperser() -> void:
	_twist_disperser = BoneTwistDisperser3D.new()
	_twist_disperser.name = "SpineTwistDisperser"
	_twist_disperser.influence = 0.0
	_skeleton.add_child(_twist_disperser)

	_twist_disperser.setting_count = 1
	_twist_disperser.set("settings/0/root_bone_name", GameConstants.BONE_SPINE)
	_twist_disperser.set("settings/0/end_bone_name", "Neck")
	_twist_disperser.set("settings/0/extend_end_bone", false)
	_twist_disperser.set("settings/0/twist_from_rest", true)
	_twist_disperser.set("settings/0/disperse_mode", 0)
	_twist_disperser.set("settings/0/joint_count", 4)

	# CCDIKの直後に配置
	_skeleton.move_child(_twist_disperser, _ccdik.get_index() + 1)


# ============================================
# Public API
# ============================================

## ヨー角度を設定（残差角度: 実際の移動方向と量子化方向の差）
func set_yaw(yaw: float) -> void:
	_target_yaw = yaw


## 有効/無効を切替
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_target_yaw = 0.0
		_current_yaw = 0.0
	var inf := 1.0 if enabled else 0.0
	if _ccdik:
		_ccdik.influence = inf
	if _twist_disperser:
		_twist_disperser.influence = inf


## 毎フレーム更新（CharacterAnimationControllerから呼ばれる）
func update(delta: float) -> void:
	if not _is_setup or not _enabled:
		return

	# ヨーのスムーズ遷移
	var alpha := 1.0 - exp(-SMOOTHING_SPEED * delta)
	_current_yaw = lerpf(_current_yaw, _target_yaw, alpha)

	# TargetPivot位置: キャラクターに追従、回転: モデル向き + 残差ヨー
	if _target_pivot and _model and _character_root:
		var char_pos := _character_root.global_position
		_target_pivot.global_position = char_pos + Vector3(0, PIVOT_HEIGHT, 0)
		var model_y_rot := _model.global_rotation.y
		_target_pivot.global_rotation = Vector3(0, model_y_rot + _current_yaw, 0)


## CCDIKノードを取得（modifier order制御用）
func get_ccdik_node() -> CCDIK3D:
	return _ccdik


## TwistDisperserノードを取得（modifier order制御用）
func get_twist_disperser_node() -> BoneTwistDisperser3D:
	return _twist_disperser


## セットアップ済みかどうか
func is_setup() -> bool:
	return _is_setup


## 有効状態を取得
func is_enabled() -> bool:
	return _enabled


## 現在のヨー角度を取得（UI表示用）
func get_current_yaw() -> float:
	return _current_yaw


# ============================================
# Cleanup
# ============================================

func _exit_tree() -> void:
	if _target_pivot and is_instance_valid(_target_pivot):
		_target_pivot.queue_free()
	_ccdik = null
	_twist_disperser = null
	_target_pivot = null
	_spine_target = null
