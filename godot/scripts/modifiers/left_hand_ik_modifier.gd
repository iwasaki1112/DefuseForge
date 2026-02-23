extends Node
class_name LeftHandIKModifier
## Left Hand IK Controller
## TwoBoneIK3Dのセットアップと制御を管理
## 右手IKからのデルタ方式: char_pos + model_basis * (rh_pos + delta + offset)

# ============================================
# Constants
# ============================================
const DEFAULT_BLEND_SPEED := 15.0  ## デフォルトinfluence遷移速度（高い=素早い追従）
const DEFAULT_POLE_OFFSET := 0.3  ## ポールターゲットのデフォルトオフセット（肘方向制御）

# ============================================
# State
# ============================================
var _ik_node: TwoBoneIK3D
var _ik_target: Marker3D  ## IKターゲット（常にMarker3D経由）
var _ik_pole: Marker3D  ## 肘方向制御用ポールターゲット
var _grip_source: Node3D  ## 武器モデル内のLeftHandGripノード
var _skeleton: Skeleton3D
var _model: Node3D  ## キャラクターモデル参照
var _target_influence := 0.0  ## 目標influence（0.0 or 1.0）
var _blend_speed := DEFAULT_BLEND_SPEED  ## 現在のブレンド速度
var _pole_offset := Vector3(DEFAULT_POLE_OFFSET, 0.0, 0.0)  ## 肘方向オフセット（キャラクター空間XYZ）
var _grip_offset := Vector3.ZERO  ## グリップ位置オフセット（キャラ相対空間）
var _lh_rh_delta := Vector3.ZERO  ## 右手からの左手オフセット（キャラ相対）
var _rh_position_getter: Callable  ## 右手キャラ相対位置を返すCallable
var _capture_countdown := -1  ## キャプチャ待機フレーム数（-1=待機なし）
var _delta_captured := false  ## デルタキャプチャ完了フラグ
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

	# IKターゲット用Marker3D（常にこれを使用）
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

	# ターゲットは常にMarker3D
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
## 常にMarker3D経由でキャラ相対座標追従（デルタ方式）
func set_grip_source(grip_node: Node3D) -> void:
	_grip_source = grip_node
	_delta_captured = false
	_lh_rh_delta = Vector3.ZERO
	if _ik_node and _is_setup and grip_node and is_instance_valid(grip_node):
		# 常にMarker3Dをターゲットに使用
		_ik_node.set_target_node(0, _ik_node.get_path_to(_ik_target))
		# キャプチャカウントダウン開始（2フレーム待機でIKパイプライン安定化）
		_capture_countdown = 2

## グリップソースをクリア
func clear_grip_source() -> void:
	_grip_source = null
	_delta_captured = false
	_lh_rh_delta = Vector3.ZERO
	_capture_countdown = -1
	_target_influence = 0.0
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

## グリップ位置オフセットを設定（キャラ相対空間）
func set_grip_offset(offset: Vector3) -> void:
	_grip_offset = offset

## 現在のグリップオフセットを取得
func get_grip_offset() -> Vector3:
	return _grip_offset

## 右手位置取得用Callableを設定
func set_rh_position_getter(getter: Callable) -> void:
	_rh_position_getter = getter

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

	# キャプチャカウントダウン
	if _capture_countdown > 0:
		_capture_countdown -= 1
	elif _capture_countdown == 0:
		_capture_delta()
		_capture_countdown = -1

	if not _grip_source or not is_instance_valid(_grip_source):
		return

	# IKターゲット位置更新
	if _delta_captured and _rh_position_getter.is_valid() and _model:
		# デルタ方式: 右手IK位置からの相対位置で計算
		var char_pos := _model.global_position
		var model_basis := _model.global_transform.basis
		var rh_pos: Vector3 = _rh_position_getter.call()
		_ik_target.global_position = char_pos + model_basis * (rh_pos + _lh_rh_delta + _grip_offset)
	else:
		# フォールバック: グリップノード直接追跡（キャプチャ待機中）
		_ik_target.global_transform = _grip_source.global_transform
		if _grip_offset.length_squared() > 0.0001:
			_ik_target.global_position += _grip_source.global_transform.basis * _grip_offset

	# ポール位置更新（肩と手の中点 + キャラクター空間オフセット）
	if _ik_pole and _ik_node.influence > 0.001:
		var root_bone_idx := _skeleton.find_bone(GameConstants.BONE_LEFT_ARM)
		if root_bone_idx >= 0:
			var root_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(root_bone_idx)
			var mid := (root_global.origin + _ik_target.global_position) * 0.5
			var char_basis := _skeleton.global_transform.basis
			_ik_pole.global_position = mid + char_basis * _pole_offset

# ============================================
# Capture
# ============================================

## グリップ位置をキャラ相対デルタとしてキャプチャ
func _capture_delta() -> void:
	if not _grip_source or not is_instance_valid(_grip_source):
		return
	if not _rh_position_getter.is_valid() or not _model:
		return

	var char_pos := _model.global_position
	var inv_basis := _model.global_transform.basis.inverse()

	# グリップノードのキャラ相対位置
	var grip_char_relative := inv_basis * (_grip_source.global_position - char_pos)

	# 右手のキャラ相対位置
	var rh_pos: Vector3 = _rh_position_getter.call()

	# デルタ = グリップのキャラ相対位置 − 右手のキャラ相対位置
	_lh_rh_delta = grip_char_relative - rh_pos
	_delta_captured = true

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
