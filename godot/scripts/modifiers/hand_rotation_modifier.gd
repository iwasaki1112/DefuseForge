extends SkeletonModifier3D

## TwoBoneIK3D処理後に手首ボーンの回転をオーバーライドする。
## SkeletonModifier3Dとして TwoBoneIK3D の後に配置することで、
## IKで決まった手の位置を保ちつつ回転だけを変更する。

var _bone_idx: int = -1
var _rotation_offset := Vector3.ZERO  ## Euler degrees (bone-local offset)


func setup(bone_name: String) -> void:
	var skel := get_skeleton()
	if skel:
		_bone_idx = skel.find_bone(bone_name)


## 回転オフセットを設定（Euler degrees, bone-local）
func set_rotation_offset(rot_deg: Vector3) -> void:
	_rotation_offset = rot_deg


func _process_modification() -> void:
	if _bone_idx < 0:
		return
	var skel := get_skeleton()
	if not skel:
		return

	# TwoBoneIK3Dが設定した回転を取得
	var current_rot := skel.get_bone_pose_rotation(_bone_idx)

	# オフセットを追加（bone-local空間）
	var offset_rad := Vector3(
		deg_to_rad(_rotation_offset.x),
		deg_to_rad(_rotation_offset.y),
		deg_to_rad(_rotation_offset.z),
	)
	var offset_quat := Quaternion.from_euler(offset_rad)
	skel.set_bone_pose_rotation(_bone_idx, current_rot * offset_quat)
