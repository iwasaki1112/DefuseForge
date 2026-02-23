extends SkeletonModifier3D

## Syncs a BoneAttachment3D transform during modifier pipeline.
##
## BoneAttachment3D normally updates AFTER all skeleton modifiers.
## This modifier forces an early update so that nodes under the attachment
## (e.g., weapon grip targets for left hand IK) have correct positions
## when subsequent modifiers read them.
## Place after the IK that moves the bone, before the IK that targets
## nodes under the attachment.

var _attachment: BoneAttachment3D
var _bone_idx: int = -1


func setup_attachment(attachment: BoneAttachment3D) -> void:
	_attachment = attachment
	var skel := get_skeleton()
	if skel and attachment:
		_bone_idx = skel.find_bone(attachment.bone_name)


func _process_modification() -> void:
	if _bone_idx < 0 or not _attachment or not is_instance_valid(_attachment):
		return
	var skel := get_skeleton()
	if not skel:
		return
	_attachment.global_transform = skel.global_transform * skel.get_bone_global_pose(_bone_idx)
