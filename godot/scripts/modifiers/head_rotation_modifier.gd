@tool
extends SkeletonModifier3D
class_name HeadRotationModifier

## Head bone rotation modifier (pitch + yaw)
##
## SkeletonModifier3Dパイプライン内でHeadボーンにピッチ（うなずき）と
## ヨー（首振り）を適用する。rest pose基準の軸変換を使用。

@export var bone_name := "Head"
@export var smoothing_speed := 10.0

var _bone_idx := -1
var _target_pitch := 0.0  ## 正=下向き（うなずき）
var _target_yaw := 0.0    ## 正=右向き
var _current_pitch := 0.0
var _current_yaw := 0.0

# ============================================
# Public API
# ============================================

func set_pitch(pitch: float) -> void:
	_target_pitch = pitch


func set_yaw(yaw: float) -> void:
	_target_yaw = yaw


# ============================================
# Internal
# ============================================

func _ready() -> void:
	_cache_bone()


func _cache_bone() -> void:
	var skel := get_skeleton()
	if skel:
		_bone_idx = skel.find_bone(bone_name)


func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return
	if _bone_idx < 0:
		_cache_bone()
		if _bone_idx < 0:
			return

	var dt := get_process_delta_time()
	_current_pitch = lerpf(_current_pitch, _target_pitch, 1.0 - exp(-smoothing_speed * dt))
	_current_yaw = lerpf(_current_yaw, _target_yaw, 1.0 - exp(-smoothing_speed * dt))

	if absf(_current_pitch) < 0.001 and absf(_current_yaw) < 0.001:
		return

	var anim_rot := skel.get_bone_pose_rotation(_bone_idx)
	var rest_basis := skel.get_bone_global_rest(_bone_idx).basis
	var inv_basis := rest_basis.inverse()

	if absf(_current_pitch) > 0.001:
		var pitch_axis := (inv_basis * Vector3.RIGHT).normalized()
		anim_rot = anim_rot * Quaternion(pitch_axis, _current_pitch)

	if absf(_current_yaw) > 0.001:
		var yaw_axis := (inv_basis * Vector3.UP).normalized()
		anim_rot = anim_rot * Quaternion(yaw_axis, _current_yaw)

	skel.set_bone_pose_rotation(_bone_idx, anim_rot)
