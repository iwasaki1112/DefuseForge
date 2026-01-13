@tool
class_name TwoBoneIK3D
extends SkeletonModifier3D

## シンプルな2ボーンIK（回転のみ、グローバル→ローカル変換）
## 参考: https://theorangeduck.com/page/simple-two-joint

## ルートボーン名（上腕: arm.l）
@export var root_bone: StringName = &""
## ティップボーン名（手: hand.l）
@export var tip_bone: StringName = &""
## ターゲットノード
@export var target_node: Node3D
## ポールターゲット（肘の方向を決める）- オプション
@export var pole_node: Node3D
## 曲げ方向を反転
@export var flip_bend: bool = false
## Note: influence is inherited from SkeletonModifier3D

## 内部変数
var _root_idx: int = -1
var _middle_idx: int = -1
var _tip_idx: int = -1
var _root_parent_idx: int = -1
var _upper_length: float = 0.0
var _lower_length: float = 0.0
var _initialized: bool = false
var _frame_count: int = 0  # フレームカウント（最初のフレームをスキップ）


func _process_modification() -> void:
	_frame_count += 1

	# 最初の数フレームはスキップ（アニメーションが安定するまで待つ）
	if _frame_count < 3:
		return

	if not _initialized:
		_initialize()

	if not _initialized or target_node == null:
		return

	var skeleton := get_skeleton()
	if skeleton == null:
		return

	_solve_two_bone_ik(skeleton)


## 手動でIKを実行（上半身回転後に呼び出す用）
func solve_ik_manual() -> void:
	if not _initialized:
		_initialize()

	if not _initialized or target_node == null:
		return

	var skeleton := get_skeleton()
	if skeleton == null:
		return

	_solve_two_bone_ik(skeleton)


func _initialize() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	# ボーンインデックスを取得
	_root_idx = skeleton.find_bone(root_bone)
	_tip_idx = skeleton.find_bone(tip_bone)

	if _root_idx < 0 or _tip_idx < 0:
		push_warning("[TwoBoneIK3D] Root or tip bone not found: root=%s, tip=%s" % [root_bone, tip_bone])
		return

	# ミドルボーン（ティップの親）を自動検出
	_middle_idx = skeleton.get_bone_parent(_tip_idx)
	if _middle_idx < 0:
		push_warning("[TwoBoneIK3D] Middle bone not found")
		return

	# ミドルの親がルートか確認
	var middle_parent := skeleton.get_bone_parent(_middle_idx)
	if middle_parent != _root_idx:
		push_warning("[TwoBoneIK3D] Invalid bone chain: middle parent=%d, root=%d" % [middle_parent, _root_idx])
		return

	# ルートの親を取得
	_root_parent_idx = skeleton.get_bone_parent(_root_idx)

	# ボーン長を計算（レストポーズから）
	var middle_rest := skeleton.get_bone_rest(_middle_idx)
	var tip_rest := skeleton.get_bone_rest(_tip_idx)
	_upper_length = middle_rest.origin.length()
	_lower_length = tip_rest.origin.length()

	if _upper_length < 0.001 or _lower_length < 0.001:
		push_warning("[TwoBoneIK3D] Invalid bone lengths: upper=%f, lower=%f" % [_upper_length, _lower_length])
		return

	_initialized = true


func _solve_two_bone_ik(skeleton: Skeleton3D) -> void:
	var skel_transform := skeleton.global_transform
	var skel_inverse := skel_transform.affine_inverse()

	# Get target in skeleton local space
	var target_world := target_node.global_position
	var target_local := skel_inverse * target_world

	# Get parent global pose for root
	var root_parent_global: Transform3D
	if _root_parent_idx >= 0:
		root_parent_global = skeleton.get_bone_global_pose(_root_parent_idx)
	else:
		root_parent_global = Transform3D.IDENTITY

	# Get current bone global poses (アニメーション適用後)
	var root_global := skeleton.get_bone_global_pose(_root_idx)
	var middle_global := skeleton.get_bone_global_pose(_middle_idx)
	var tip_global := skeleton.get_bone_global_pose(_tip_idx)

	var root_pos := root_global.origin
	var middle_pos := middle_global.origin
	var _tip_pos := tip_global.origin  # Used for reference calculations

	# Vector from root to target
	var to_target := target_local - root_pos
	var target_dist := to_target.length()

	if target_dist < 0.001:
		return

	var target_dir := to_target.normalized()

	# Clamp to reachable range
	var max_reach: float = _upper_length + _lower_length - 0.001
	var min_reach: float = absf(_upper_length - _lower_length) + 0.001
	var clamped_dist: float = clampf(target_dist, min_reach, max_reach)

	# Law of cosines to find shoulder angle offset
	var cos_root := (_upper_length * _upper_length + clamped_dist * clamped_dist - _lower_length * _lower_length) / (2.0 * _upper_length * clamped_dist)
	cos_root = clampf(cos_root, -1.0, 1.0)
	var root_angle_offset := acos(cos_root)

	# Calculate pole direction (determines elbow bend direction)
	var pole_dir: Vector3
	if pole_node:
		var pole_local := skel_inverse * pole_node.global_position
		var pole_rel := pole_local - root_pos
		pole_dir = pole_rel - target_dir * pole_rel.dot(target_dir)
	else:
		# Use current elbow position to infer bend direction
		var elbow_rel := middle_pos - root_pos
		pole_dir = elbow_rel - target_dir * elbow_rel.dot(target_dir)

	if pole_dir.length_squared() < 0.0001:
		pole_dir = target_dir.cross(Vector3.UP)
		if pole_dir.length_squared() < 0.0001:
			pole_dir = target_dir.cross(Vector3.FORWARD)
	pole_dir = pole_dir.normalized()

	if flip_bend:
		pole_dir = -pole_dir

	# Calculate desired upper arm direction
	var upper_dir := _rotate_toward(target_dir, pole_dir, root_angle_offset)

	# Calculate new elbow position (for reference)
	var new_elbow_pos := root_pos + upper_dir * _upper_length

	# Calculate desired lower arm direction
	var lower_dir := (target_local - new_elbow_pos)
	if lower_dir.length() < 0.001:
		lower_dir = target_dir
	else:
		lower_dir = lower_dir.normalized()

	# === Step 1: Rotate ROOT bone ===
	# Calculate rotation delta in global/skeleton space
	var root_original_dir := (middle_pos - root_pos).normalized()
	var root_rotation_delta := _quat_from_to(root_original_dir, upper_dir)

	# Apply rotation delta to global rotation, then convert to local
	var root_global_rotation := root_global.basis.get_rotation_quaternion()
	var new_root_global_rotation := root_rotation_delta * root_global_rotation

	# Convert new global rotation to local space
	var root_parent_rotation := root_parent_global.basis.get_rotation_quaternion()
	var new_root_local_rotation := root_parent_rotation.inverse() * new_root_global_rotation

	# Get current local pose for blending
	var root_local := skeleton.get_bone_pose(_root_idx)
	var root_local_rotation := root_local.basis.get_rotation_quaternion()

	# Blend with influence
	var blended_root_rotation := root_local_rotation.slerp(new_root_local_rotation, influence)

	# Apply rotation only (keep original position)
	skeleton.set_bone_pose_rotation(_root_idx, blended_root_rotation)

	# === Step 2: Get UPDATED middle bone position after root rotation ===
	var updated_middle_global := skeleton.get_bone_global_pose(_middle_idx)
	var updated_middle_pos := updated_middle_global.origin
	var updated_tip_global := skeleton.get_bone_global_pose(_tip_idx)
	var updated_tip_pos := updated_tip_global.origin

	# === Step 3: Rotate MIDDLE bone ===
	# Calculate rotation delta in global/skeleton space
	var middle_original_dir := (updated_tip_pos - updated_middle_pos).normalized()
	var middle_rotation_delta := _quat_from_to(middle_original_dir, lower_dir)

	# Apply rotation delta to global rotation, then convert to local
	var middle_global_rotation := updated_middle_global.basis.get_rotation_quaternion()
	var new_middle_global_rotation := middle_rotation_delta * middle_global_rotation

	# Get updated root global for parent transform
	var updated_root_global := skeleton.get_bone_global_pose(_root_idx)
	var updated_root_rotation := updated_root_global.basis.get_rotation_quaternion()

	# Convert new global rotation to local space (parent is root)
	var new_middle_local_rotation := updated_root_rotation.inverse() * new_middle_global_rotation

	# Get current local pose for blending
	var middle_local := skeleton.get_bone_pose(_middle_idx)
	var middle_local_rotation := middle_local.basis.get_rotation_quaternion()

	# Blend with influence
	var blended_middle_rotation := middle_local_rotation.slerp(new_middle_local_rotation, influence)

	# Apply rotation only (keep original position)
	skeleton.set_bone_pose_rotation(_middle_idx, blended_middle_rotation)


## Create quaternion that rotates from one direction to another
func _quat_from_to(from: Vector3, to: Vector3) -> Quaternion:
	from = from.normalized()
	to = to.normalized()

	var dot := from.dot(to)

	if dot > 0.9999:
		return Quaternion.IDENTITY

	if dot < -0.9999:
		var perp := Vector3.RIGHT.cross(from)
		if perp.length_squared() < 0.0001:
			perp = Vector3.UP.cross(from)
		return Quaternion(perp.normalized(), PI)

	var axis := from.cross(to).normalized()
	var angle := acos(clampf(dot, -1.0, 1.0))
	return Quaternion(axis, angle)


## Rotate direction toward another by given angle
func _rotate_toward(from_dir: Vector3, toward_dir: Vector3, angle: float) -> Vector3:
	var axis := from_dir.cross(toward_dir)
	if axis.length_squared() < 0.0001:
		axis = from_dir.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = from_dir.cross(Vector3.RIGHT)
	axis = axis.normalized()
	return Quaternion(axis, angle) * from_dir
