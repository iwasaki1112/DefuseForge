extends SkeletonModifier3D
class_name SpinePostureModifier

## 背骨姿勢制御 — ピッチ（前傾/後傾）+ヨー（左右回転）を重み付き分配で適用

@export var chain_bones: PackedStringArray = ["Hips", "Spine", "Chest", "UpperChest"]
@export var chain_weights: PackedFloat32Array = [0.0, 0.35, 0.35, 0.3]
@export var yaw_chain_weights: PackedFloat32Array = [0.0, 0.2, 0.3, 0.5]
@export var smoothing_speed := 10.0

var _bone_indices := PackedInt32Array()
var _target_pitch := 0.0
var _target_yaw := 0.0
var _current_pitch := 0.0
var _current_yaw := 0.0

func set_posture(pitch: float, _roll: float) -> void:
	_target_pitch = pitch

func set_pitch(pitch: float) -> void:
	_target_pitch = pitch

func set_yaw(yaw: float) -> void:
	_target_yaw = yaw

func set_yaw_chain_weights(weights: PackedFloat32Array) -> void:
	yaw_chain_weights = weights

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
	var alpha := 1.0 - exp(-smoothing_speed * dt)
	_current_pitch = lerpf(_current_pitch, _target_pitch, alpha)
	_current_yaw = lerpf(_current_yaw, _target_yaw, alpha)

	if absf(_current_pitch) < 0.001 and absf(_current_yaw) < 0.001:
		return

	for i in range(_bone_indices.size()):
		var bone_idx := _bone_indices[i]
		var pitch_w := chain_weights[i] if i < chain_weights.size() else 0.0
		var yaw_w := yaw_chain_weights[i] if i < yaw_chain_weights.size() else 0.0

		var pitch_amount := _current_pitch * pitch_w
		var yaw_amount := _current_yaw * yaw_w

		if absf(pitch_amount) < 0.001 and absf(yaw_amount) < 0.001:
			continue

		var anim_rot := skel.get_bone_pose_rotation(bone_idx)
		var rest_basis := skel.get_bone_global_rest(bone_idx).basis
		var inv_basis := rest_basis.inverse()

		# ピッチ→ヨーの順で前乗算（結果: yaw * pitch * anim）
		# ピッチ(内側): rest空間で常に同じ前傾
		# ヨー(外側): ピッチに依存せず純粋な水平回転
		if absf(pitch_amount) > 0.001:
			var pitch_axis := (inv_basis * Vector3.RIGHT).normalized()
			anim_rot = Quaternion(pitch_axis, pitch_amount) * anim_rot

		if absf(yaw_amount) > 0.001:
			var yaw_axis := (inv_basis * Vector3.UP).normalized()
			anim_rot = Quaternion(yaw_axis, yaw_amount) * anim_rot

		skel.set_bone_pose_rotation(bone_idx, anim_rot)
