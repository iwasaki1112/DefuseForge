extends Node
class_name LeftHandIKModifier
## Left Hand IK Controller
## TwoBoneIK3Dのセットアップと制御を管理
## TwoBoneIK3Dのtarget_nodeを直接LeftHandGripに向けることで遅延ゼロの追従を実現

# ============================================
# Constants
# ============================================
const DEFAULT_BLEND_SPEED := 15.0  ## デフォルトinfluence遷移速度（高い=素早い追従）
const DEFAULT_POLE_OFFSET := 0.3  ## ポールターゲットのデフォルトオフセット（肘方向制御）

# ============================================
# State
# ============================================
var _ik_node: TwoBoneIK3D
var _ik_target: Marker3D  ## フォールバック用（grip未設定時）
var _ik_pole: Marker3D  ## 肘方向制御用ポールターゲット
var _grip_source: Node3D  ## 武器モデル内のLeftHandGripノード
var _skeleton: Skeleton3D
var _target_influence := 0.0  ## 目標influence（0.0 or 1.0）
var _blend_speed := DEFAULT_BLEND_SPEED  ## 現在のブレンド速度
var _pole_offset := Vector3(DEFAULT_POLE_OFFSET, 0.0, 0.0)  ## 肘方向オフセット（キャラクター空間XYZ）
var _grip_offset := Vector3.ZERO  ## グリップ位置オフセット（ローカル空間）
var _use_offset_target := false  ## オフセット使用時はMarker3D経由
var _is_setup := false

# ============================================
# Setup
# ============================================

## IKノードとターゲットを作成してスケルトンに追加
func setup(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	if not _skeleton:
		return

	# フォールバック用Marker3D（gripノード未設定時のデフォルトターゲット）
	_ik_target = Marker3D.new()
	_ik_target.name = GameConstants.NODE_LEFT_HAND_IK_TARGET
	_skeleton.add_child(_ik_target)

	# ポールターゲット用Marker3D（肘方向制御）をスケルトンの子として作成
	_ik_pole = Marker3D.new()
	_ik_pole.name = "LeftHandIKPole"
	_skeleton.add_child(_ik_pole)

	# TwoBoneIK3Dをスケルトンの子として作成 → 先にツリーに追加
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

	# 初期ターゲットはフォールバック用Marker3D
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
## TwoBoneIK3Dのtarget_nodeを直接gripノードに向けることで遅延なし追従
func set_grip_source(grip_node: Node3D) -> void:
	_grip_source = grip_node
	_use_offset_target = false  # ターゲット切替によりoffsetモードをリセット
	if _ik_node and _is_setup and grip_node and is_instance_valid(grip_node):
		# TwoBoneIK3Dのターゲットを直接gripノードに向ける（コピー不要、遅延ゼロ）
		_ik_node.set_target_node(0, _ik_node.get_path_to(grip_node))

## グリップソースをクリア
func clear_grip_source() -> void:
	_grip_source = null
	_target_influence = 0.0
	# ターゲットをフォールバック用Marker3Dに戻す
	if _ik_node and _is_setup and _ik_target:
		_ik_node.set_target_node(0, _ik_node.get_path_to(_ik_target))

## グリップソースが有効に設定されているかどうか
func has_grip_source() -> bool:
	return _grip_source != null and is_instance_valid(_grip_source)

## IKが有効かどうか
func is_enabled() -> bool:
	return _target_influence > 0.5


## TwoBoneIK3Dノードを取得（処理順序の修正用）
func get_ik_node() -> TwoBoneIK3D:
	return _ik_node

## ポールオフセットを設定（キャラクター空間XYZ）
func set_pole_offset(offset: Vector3) -> void:
	_pole_offset = offset

## 現在のポールオフセットを取得
func get_pole_offset() -> Vector3:
	return _pole_offset

## グリップ位置オフセットを設定（武器ローカル空間）
func set_grip_offset(offset: Vector3) -> void:
	_grip_offset = offset
	_update_offset_target_mode()

## 現在のグリップオフセットを取得
func get_grip_offset() -> Vector3:
	return _grip_offset

## オフセットモードの切替（オフセットあり→Marker3D経由、なし→直接）
func _update_offset_target_mode() -> void:
	if not _is_setup or not _ik_node:
		return
	var needs_offset := _grip_offset.length_squared() > 0.0001
	if needs_offset and not _use_offset_target:
		# オフセット使用開始 → ターゲットをMarker3Dに切替
		_use_offset_target = true
		_ik_node.set_target_node(0, _ik_node.get_path_to(_ik_target))
	elif not needs_offset and _use_offset_target:
		# オフセット不要 → 直接gripノードに戻す
		_use_offset_target = false
		if _grip_source and is_instance_valid(_grip_source):
			_ik_node.set_target_node(0, _ik_node.get_path_to(_grip_source))

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

	# グリップオフセット適用（Marker3D経由モード時）
	if _use_offset_target and _grip_source and is_instance_valid(_grip_source) and _ik_target:
		_ik_target.global_transform = _grip_source.global_transform
		_ik_target.global_position += _grip_source.global_transform.basis * _grip_offset

	# ポール位置を更新（肩と手の中点 + キャラクター空間オフセット）
	if _grip_source and is_instance_valid(_grip_source) and _ik_pole and _ik_node.influence > 0.001:
		var grip_pos := _grip_source.global_position
		var root_bone_idx := _skeleton.find_bone(GameConstants.BONE_LEFT_ARM)
		if root_bone_idx >= 0:
			var root_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(root_bone_idx)
			var mid := (root_global.origin + grip_pos) * 0.5
			var char_basis := _skeleton.global_transform.basis
			_ik_pole.global_position = mid + char_basis * _pole_offset

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
