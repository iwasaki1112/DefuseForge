@tool
extends SkeletonModifier3D
class_name RecoilModifier

## Applies procedural recoil to upper body bones

@export var spine_bone_name := "mixamorig_Spine2"
@export var recoil_strength := 0.1
@export var recovery_speed := 10.0

var _spine_bone_idx := -1
var _current_recoil := 0.0

func _ready() -> void:
	_find_bone()

func _find_bone() -> void:
	var skeleton := get_skeleton()
	if skeleton:
		_spine_bone_idx = skeleton.find_bone(spine_bone_name)

func trigger_recoil(strength: float = -1.0) -> void:
	_current_recoil = strength if strength > 0 else recoil_strength

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not skeleton or _spine_bone_idx < 0:
		return

	# Apply recoil rotation (tilt upward/backward around local X axis)
	if _current_recoil > 0.001:
		var current_pose := skeleton.get_bone_pose_rotation(_spine_bone_idx)
		var recoil_rotation := Quaternion(Vector3.RIGHT, -_current_recoil)
		skeleton.set_bone_pose_rotation(_spine_bone_idx, current_pose * recoil_rotation)

	# Recover
	_current_recoil = lerpf(_current_recoil, 0.0, recovery_speed * get_process_delta_time())
