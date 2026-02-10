@tool
extends SkeletonModifier3D
class_name LeanModifier

## Applies procedural lean (roll) to upper body bones

@export var spine_bone_name := "UpperChest"
@export var recovery_speed := 10.0

var _spine_bone_idx := -1
var _target_lean := 0.0
var _current_lean := 0.0

func _ready() -> void:
	_find_bone()

func _find_bone() -> void:
	var skeleton := get_skeleton()
	if skeleton:
		_spine_bone_idx = skeleton.find_bone(spine_bone_name)

func set_target_lean(angle_radians: float) -> void:
	_target_lean = angle_radians

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not skeleton or _spine_bone_idx < 0:
		return

	_current_lean = lerpf(_current_lean, _target_lean, recovery_speed * get_process_delta_time())

	if absf(_current_lean) > 0.0001:
		var current_pose := skeleton.get_bone_pose_rotation(_spine_bone_idx)
		var lean_rotation := Quaternion(Vector3.FORWARD, _current_lean)
		skeleton.set_bone_pose_rotation(_spine_bone_idx, current_pose * lean_rotation)
