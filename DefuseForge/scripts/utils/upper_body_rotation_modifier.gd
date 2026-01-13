@tool
class_name UpperBodyRotationModifier
extends SkeletonModifier3D

## 上半身回転モディファイア
## アニメーション処理後に複数のSpineボーンを回転させる

## 回転角度（ラジアン）
var rotation_angle: float = 0.0

## 内部
var _spine_bone_indices: Array[int] = []
var _initialized: bool = false


func _process_modification() -> void:
	if not _initialized:
		_initialize()

	if not _initialized:
		return

	if abs(rotation_angle) < 0.001:
		return

	var skeleton := get_skeleton()
	if skeleton == null:
		return

	# 各スパインボーンに回転を適用（分散させる）
	var per_bone_angle = rotation_angle / max(_spine_bone_indices.size(), 1)
	for bone_idx in _spine_bone_indices:
		var current_rotation = skeleton.get_bone_pose_rotation(bone_idx)
		var twist = Quaternion(Vector3.UP, per_bone_angle)
		var new_rotation = current_rotation * twist
		skeleton.set_bone_pose_rotation(bone_idx, new_rotation)


func _initialize() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	_spine_bone_indices.clear()

	# 複数のスパインボーンを検索
	var spine_candidates := ["Spine", "Chest", "UpperChest"]
	for bone_name in spine_candidates:
		var idx = skeleton.find_bone(bone_name)
		if idx >= 0:
			_spine_bone_indices.append(idx)

	if _spine_bone_indices.is_empty():
		push_warning("[UpperBodyRotationModifier] No spine bones found!")
		return

	_initialized = true


## 回転角度を設定（度）
func set_twist_degrees(degrees: float) -> void:
	rotation_angle = deg_to_rad(degrees)


## 回転角度を設定（ラジアン）
func set_rotation_radians(radians: float) -> void:
	rotation_angle = radians
