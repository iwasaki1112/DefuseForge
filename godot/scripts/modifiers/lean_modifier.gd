@tool
extends SkeletonModifier3D
class_name LeanModifier

## Applies procedural lean by distributing rotation across the spine chain
##
## Hips → Spine → Chest → UpperChest にリーン回転を重み付きで分配し、
## 自然な体全体の傾きを実現する。単一ボーンだと背中が曲がるだけになる。

@export var chain_bones: PackedStringArray = ["Hips", "Spine", "Chest", "UpperChest"]
@export var chain_weights: PackedFloat32Array = [0.1, 0.2, 0.3, 0.4]
@export var recovery_speed := 10.0

## Hips の微小な横方向カウンターシフト（重心補正）
@export var use_hip_counter_shift := true
@export var hip_counter_shift := 0.03  ## meters per radian

var _bone_indices := PackedInt32Array()
var _target_lean := 0.0
var _current_lean := 0.0

func _ready() -> void:
	_cache_bones()

func _cache_bones() -> void:
	_bone_indices.clear()
	var skel := get_skeleton()
	if not skel:
		return
	for bone_name in chain_bones:
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			_bone_indices.append(idx)

func set_target_lean(angle_radians: float) -> void:
	_target_lean = angle_radians

func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return
	if _bone_indices.is_empty():
		_cache_bones()
		if _bone_indices.is_empty():
			return

	var dt := get_process_delta_time()
	_current_lean = lerpf(_current_lean, _target_lean, 1.0 - exp(-recovery_speed * dt))

	# リーン軸: スケルトン空間の -Z（FORWARD）
	# 正の角度で右リーン（right-hand rule: +X→-Y = 右が下がる）
	var axis_skeleton := Vector3.FORWARD

	# 全ボーンのグローバルベースをキャッシュ（子ボーンへの影響前に取得）
	var bases: Array[Basis] = []
	bases.resize(_bone_indices.size())
	for i in range(_bone_indices.size()):
		bases[i] = skel.get_bone_global_pose(_bone_indices[i]).basis

	# チェーンに重み付きリーン回転を分配
	for i in range(_bone_indices.size()):
		var idx := _bone_indices[i]
		var w := chain_weights[i] if i < chain_weights.size() else 0.25

		# スケルトン空間の軸をボーンローカル空間に変換
		var axis_local := (bases[i].inverse() * axis_skeleton).normalized()
		var anim_rot := skel.get_bone_pose_rotation(idx)
		var lean_q := Quaternion(axis_local, _current_lean * w)

		skel.set_bone_pose_rotation(idx, anim_rot * lean_q)

	# Hips の微小カウンターシフト（リーン方向と逆に重心補正）
	if use_hip_counter_shift and not _bone_indices.is_empty():
		var hip_idx := _bone_indices[0]
		var hip_right_local := (bases[0].inverse() * Vector3.RIGHT).normalized()
		var anim_pos := skel.get_bone_pose_position(hip_idx)
		skel.set_bone_pose_position(hip_idx, anim_pos + hip_right_local * (-_current_lean * hip_counter_shift))
