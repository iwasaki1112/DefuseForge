extends SkeletonModifier3D
## IK処理後にボーンに追加回転を適用するモディファイア

var bone_name: String = ""
var extra_rotation_deg := Vector3.ZERO

func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return
	var bone_idx := skel.find_bone(bone_name)
	if bone_idx < 0:
		return
	var current := skel.get_bone_pose_rotation(bone_idx)
	var extra_rad := Vector3(
		deg_to_rad(extra_rotation_deg.x),
		deg_to_rad(extra_rotation_deg.y),
		deg_to_rad(extra_rotation_deg.z)
	)
	var extra_quat := Quaternion.from_euler(extra_rad)
	skel.set_bone_pose_rotation(bone_idx, current * extra_quat)
