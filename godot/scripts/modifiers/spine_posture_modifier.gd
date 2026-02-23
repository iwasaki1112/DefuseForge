@tool
extends SkeletonModifier3D
class_name SpinePostureModifier

## Spine posture control via weighted rotation distribution
##
## Hips -> Spine -> Chest -> UpperChest にピッチ（前傾/後傾）とロール（リーン）を
## 重み付き分配で適用する。rest pose基準の軸変換を使用。

# ============================================
# Configuration
# ============================================
@export var chain_bones: PackedStringArray = ["Hips", "Spine", "Chest", "UpperChest"]
@export var chain_weights: PackedFloat32Array = [0.0, 0.35, 0.35, 0.3]
@export var smoothing_speed := 10.0

## Hips の微小な横方向カウンターシフト（重心補正）
@export var use_hip_counter_shift := true
@export var hip_counter_shift := 0.03  ## meters per radian

# ============================================
# State
# ============================================
var _bone_indices := PackedInt32Array()
var _target_pitch := 0.0  ## 前傾/後傾（ラジアン、正=前傾）
var _target_roll := 0.0   ## リーン（ラジアン、正=右傾）
var _current_pitch := 0.0
var _current_roll := 0.0

# ============================================
# Public API
# ============================================

## ピッチとロールを設定
func set_posture(pitch: float, roll: float) -> void:
	_target_pitch = pitch
	_target_roll = roll


## ピッチのみ設定（エイム前傾用）
func set_pitch(pitch: float) -> void:
	_target_pitch = pitch


## ロールのみ設定（リーン用）
func set_roll(roll: float) -> void:
	_target_roll = roll


# ============================================
# Internal
# ============================================

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


func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return
	if _bone_indices.is_empty():
		_cache_bones()
		if _bone_indices.is_empty():
			return

	var dt := get_process_delta_time()

	# Smooth towards target
	_current_pitch = lerpf(_current_pitch, _target_pitch, 1.0 - exp(-smoothing_speed * dt))
	_current_roll = lerpf(_current_roll, _target_roll, 1.0 - exp(-smoothing_speed * dt))
	# Skip if negligible
	if absf(_current_pitch) < 0.001 and absf(_current_roll) < 0.001:
		return

	# Cache rest-pose bases for axis conversion
	var rest_bases: Array[Basis] = []
	rest_bases.resize(_bone_indices.size())
	for i in range(_bone_indices.size()):
		rest_bases[i] = skel.get_bone_global_rest(_bone_indices[i]).basis

	# Apply weighted rotation to each bone in chain
	for i in range(_bone_indices.size()):
		var idx := _bone_indices[i]
		var w := chain_weights[i] if i < chain_weights.size() else 0.25
		var anim_rot := skel.get_bone_pose_rotation(idx)

		var inv_basis := rest_bases[i].inverse()

		# Pitch: rotate around local X axis (forward tilt)
		if absf(_current_pitch) > 0.001:
			var pitch_axis_local := (inv_basis * Vector3.RIGHT).normalized()
			var pitch_q := Quaternion(pitch_axis_local, _current_pitch * w)
			anim_rot = anim_rot * pitch_q

		# Roll: rotate around local -Z axis (lean)
		if absf(_current_roll) > 0.001:
			var roll_axis_local := (inv_basis * Vector3.FORWARD).normalized()
			var roll_q := Quaternion(roll_axis_local, _current_roll * w)
			anim_rot = anim_rot * roll_q

		skel.set_bone_pose_rotation(idx, anim_rot)

	# Hips counter shift for lean (weight balance)
	if use_hip_counter_shift and not _bone_indices.is_empty() and absf(_current_roll) > 0.001:
		var hip_idx := _bone_indices[0]
		var hip_right_local := (rest_bases[0].inverse() * Vector3.RIGHT).normalized()
		var anim_pos := skel.get_bone_pose_position(hip_idx)
		skel.set_bone_pose_position(hip_idx, anim_pos + hip_right_local * (-_current_roll * hip_counter_shift))
