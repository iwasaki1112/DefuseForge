extends Node
class_name LeftHandIKModifier
## Left Hand IK Controller
## TwoBoneIK3Dのセットアップと制御を管理
## LeftHandTargetSync (SkeletonModifier3D) がパイプライン内でグリップ位置を計算

# ============================================
# Constants
# ============================================
const DEFAULT_BLEND_SPEED := 15.0  ## デフォルトinfluence遷移速度（高い=素早い追従）
const DEFAULT_POLE_OFFSET := 0.3  ## ポールターゲットのデフォルトオフセット（肘方向制御）

# ============================================
# State
# ============================================
var _ik_node: TwoBoneIK3D
var _ik_target: Marker3D  ## IKターゲット（LeftHandTargetSyncが更新）
var _ik_pole: Marker3D  ## 肘方向制御用ポールターゲット
var _target_sync: Node  ## LeftHandTargetSync (SkeletonModifier3D)
var _grip_source: Node3D  ## 武器モデル内のLeftHandGripノード
var _skeleton: Skeleton3D
var _model: Node3D  ## キャラクターモデル参照
var _target_influence := 0.0  ## 目標influence（0.0 or 1.0）
var _blend_speed := DEFAULT_BLEND_SPEED  ## 現在のブレンド速度
var _pole_offset := Vector3(DEFAULT_POLE_OFFSET, 0.0, 0.0)  ## 肘方向オフセット（キャラクター空間XYZ）
var _grip_offset := Vector3.ZERO  ## グリップ位置オフセット（武器ローカル空間）
var _is_setup := false

# ============================================
# Setup
# ============================================

## IKノードとターゲットを作成してスケルトンに追加
func setup(skeleton: Skeleton3D, model: Node3D) -> void:
	_skeleton = skeleton
	_model = model
	if not _skeleton:
		return

	# IKターゲット用Marker3D（LeftHandTargetSyncがpipeline内で位置を更新）
	_ik_target = Marker3D.new()
	_ik_target.name = GameConstants.NODE_LEFT_HAND_IK_TARGET
	_skeleton.add_child(_ik_target)

	# ポールターゲット用Marker3D（肘方向制御）をスケルトンの子として作成
	_ik_pole = Marker3D.new()
	_ik_pole.name = "LeftHandIKPole"
	_skeleton.add_child(_ik_pole)

	# LeftHandTargetSync: modifier pipeline内でMarker3D位置を更新するSkeletonModifier3D
	var sync_script = load("res://scripts/modifiers/left_hand_target_sync.gd")
	if sync_script:
		_target_sync = sync_script.new()
		_target_sync.name = "LeftHandTargetSync"
		_target_sync.active = false
		_target_sync._target = _ik_target
		_target_sync._bone_idx = _skeleton.find_bone(GameConstants.BONE_RIGHT_HAND)
		_skeleton.add_child(_target_sync)

	# TwoBoneIK3Dをスケルトンの子として作成 → LeftHandTargetSyncの後に追加
	_ik_node = TwoBoneIK3D.new()
	_ik_node.name = "LeftHandIK"
	_ik_node.influence = 0.0
	_ik_node.active = true
	_skeleton.add_child(_ik_node)

	# IKチェーン設定（ツリーに追加後に行う）
	_ik_node.setting_count = 1
	_ik_node.set_root_bone_name(0, GameConstants.BONE_LEFT_ARM)
	_ik_node.set_middle_bone_name(0, GameConstants.BONE_LEFT_FOREARM)
	_ik_node.set_end_bone_name(0, GameConstants.BONE_LEFT_HAND)

	# ターゲットは常にMarker3D（LeftHandTargetSyncが位置を管理）
	_ik_node.set_target_node(0, _ik_node.get_path_to(_ik_target))
	_ik_node.set_pole_node(0, _ik_node.get_path_to(_ik_pole))

	# 設定完了後にリセットして内部状態を初期化（メソッドが存在する場合のみ）
	if _ik_node.has_method("reset"):
		_ik_node.reset()

	_is_setup = true

# ============================================
# Control
# ============================================

## IKの有効/無効を設定（influenceのlerp遷移）
func set_enabled(enabled: bool) -> void:
	_target_influence = 1.0 if enabled else 0.0

## ブレンド速度を変更（アニメーション復帰時のゆっくりブレンド等）
func set_blend_speed(speed: float) -> void:
	_blend_speed = speed

## ブレンド速度をデフォルトに戻す
func reset_blend_speed() -> void:
	_blend_speed = DEFAULT_BLEND_SPEED

## IKを即座に無効化（死亡時など）
func disable_immediate() -> void:
	_target_influence = 0.0
	if _ik_node:
		_ik_node.influence = 0.0

## 武器モデル内のグリップソースノードを設定
## ボーン→グリップのオフセットをキャプチャし、LeftHandTargetSyncに渡す
func set_grip_source(grip_node: Node3D) -> void:
	_grip_source = grip_node
	if _target_sync and _skeleton and grip_node and is_instance_valid(grip_node):
		_capture_grip_offset()

## グリップソースをクリア
func clear_grip_source() -> void:
	_grip_source = null
	_target_influence = 0.0
	if _target_sync:
		_target_sync._is_captured = false
		_target_sync.active = false

## グリップソースが有効に設定されているかどうか
func has_grip_source() -> bool:
	return _grip_source != null and is_instance_valid(_grip_source)

## IKが有効かどうか
func is_enabled() -> bool:
	return _target_influence > 0.5


## TwoBoneIK3Dノードを取得（処理順序の修正用）
func get_ik_node() -> TwoBoneIK3D:
	return _ik_node

## LeftHandTargetSyncノードを取得（処理順序の修正用）
func get_target_sync_node() -> Node:
	return _target_sync

## ポールオフセットを設定（キャラクター空間XYZ）
func set_pole_offset(offset: Vector3) -> void:
	_pole_offset = offset

## 現在のポールオフセットを取得
func get_pole_offset() -> Vector3:
	return _pole_offset

## グリップ位置オフセットを設定（武器ローカル空間）
func set_grip_offset(offset: Vector3) -> void:
	_grip_offset = offset
	if _target_sync:
		_target_sync._grip_offset = offset

## 現在のグリップオフセットを取得
func get_grip_offset() -> Vector3:
	return _grip_offset

# ============================================
# Process
# ============================================

func _process(delta: float) -> void:
	if not _is_setup or not _ik_node:
		return

	# influence遷移
	var current := _ik_node.influence
	if absf(current - _target_influence) > 0.001:
		_ik_node.influence = lerpf(current, _target_influence, 1.0 - exp(-_blend_speed * delta))
	elif current != _target_influence:
		_ik_node.influence = _target_influence

	# ポール位置更新（肩と手の中点 + キャラクター空間オフセット）
	# _ik_targetの位置はLeftHandTargetSyncがpipeline内で更新するため、
	# ここでは前フレームの位置を使用（ポール方向は高精度不要）
	if _ik_pole and _ik_node.influence > 0.001 and _grip_source and is_instance_valid(_grip_source):
		var grip_pos := _grip_source.global_position
		var root_bone_idx := _skeleton.find_bone(GameConstants.BONE_LEFT_ARM)
		if root_bone_idx >= 0:
			var root_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(root_bone_idx)
			var mid := (root_global.origin + grip_pos) * 0.5
			var char_basis := _skeleton.global_transform.basis
			_ik_pole.global_position = mid + char_basis * _pole_offset

# ============================================
# Internal
# ============================================

## ボーン→グリップのオフセットをキャプチャしてLeftHandTargetSyncに設定
## 同時に左手ボーン（手首）→グリップのオフセットもキャプチャ
## TwoBoneIK3DはLeftHandボーン原点（手首）をターゲットに配置するため、
## このオフセットを適用して手のひらがグリップに来るように補正する
func _capture_grip_offset() -> void:
	if not _target_sync or not _grip_source or not is_instance_valid(_grip_source):
		return
	var bone_idx: int = _target_sync._bone_idx
	if bone_idx < 0:
		return
	var bone_world := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx)
	_target_sync._grip_in_bone_space = bone_world.affine_inverse() * _grip_source.global_transform
	_target_sync._grip_offset = _grip_offset

	# 手首オフセットの遅延キャプチャを設定
	# 武器装備直後はアニメーションが安定していないため、
	# 10フレーム待ってからpipeline内でキャプチャする
	var left_hand_idx := _skeleton.find_bone(GameConstants.BONE_LEFT_HAND)
	if left_hand_idx >= 0:
		_target_sync._left_hand_bone_idx = left_hand_idx
		_target_sync._wrist_captured = false
		_target_sync._wrist_in_grip_space = Vector3.ZERO
		_target_sync._wrist_capture_countdown = 10

	_target_sync._is_captured = true
	_target_sync.active = true

# ============================================
# Cleanup
# ============================================

func _exit_tree() -> void:
	if _ik_node and is_instance_valid(_ik_node):
		_ik_node.queue_free()
	if _ik_target and is_instance_valid(_ik_target):
		_ik_target.queue_free()
	if _ik_pole and is_instance_valid(_ik_pole):
		_ik_pole.queue_free()
	if _target_sync and is_instance_valid(_target_sync):
		_target_sync.queue_free()
