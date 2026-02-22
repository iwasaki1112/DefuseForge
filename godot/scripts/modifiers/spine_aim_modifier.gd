@tool
extends SkeletonModifier3D
class_name SpineAimModifier
## 上半身プロシージャル回転モディファイア
##
## Spine/Chest/UpperChest にポーズリーン（前傾/後傾）を重み付き分配する。

# ============================================
# Export
# ============================================
@export var chain_bones: PackedStringArray = ["Hips", "Spine", "Chest", "UpperChest"]
@export var chain_weights: PackedFloat32Array = [0.1, 0.2, 0.3, 0.4]
@export var pose_lean_speed := 10.0

# ============================================
# State
# ============================================
## ポーズリーン（ピッチ角、ラジアン: 正=前傾、負=後傾）
var _pose_lean := 0.0
var _current_pose_lean := 0.0

var _bone_indices := PackedInt32Array()

# ============================================
# Setup
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

# ============================================
# Control
# ============================================

## ポーズリーン（前傾/後傾）を設定（ラジアン: 正=前傾、負=後傾）
func set_pose_lean(angle_radians: float) -> void:
	_pose_lean = angle_radians

# ============================================
# Modification
# ============================================

func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return
	if _bone_indices.is_empty():
		_cache_bones()
		if _bone_indices.is_empty():
			return

	var dt := get_process_delta_time()
	_current_pose_lean = lerpf(_current_pose_lean, _pose_lean, 1.0 - exp(-pose_lean_speed * dt))

	if absf(_current_pose_lean) < 0.0001:
		return

	# チェーンに重み付きポーズリーン（ピッチ）を分配
	for i in range(_bone_indices.size()):
		var idx := _bone_indices[i]
		var w := chain_weights[i] if i < chain_weights.size() else 0.25
		var anim_rot := skel.get_bone_pose_rotation(idx)

		# ボーンのグローバルレスト回転でスケルトン空間軸をローカルに変換
		var rest_global_basis := skel.get_bone_global_rest(idx).basis

		# ポーズリーン（ピッチ）: スケルトン空間 +X 軸（キャラクター右方向）回転
		var local_pose_axis := (rest_global_basis.inverse() * Vector3(1, 0, 0)).normalized()
		var pose_q := Quaternion(local_pose_axis, _current_pose_lean * w)

		skel.set_bone_pose_rotation(idx, pose_q * anim_rot)
