extends SkeletonModifier3D

## 上半身ボーンの回転/位置をアイドルポーズで上書きするModifier。
##
## Hipsの歩行回転をSpineで補償し、Hipsをロックせずに上半身を安定させる。
## 補償式: Spine_pose = inv(Spine_rest) * inv(Hips_pose_current) * Hips_pose_idle * Spine_rest * Spine_pose_idle
## → Spine以上のグローバル回転がアイドルと同一になる。
## SpinePostureModifierより前（Skeleton3Dの最初の子）に配置すること。

var _locked_rotations: Dictionary = {}  # bone_idx (int) -> Quaternion
var _locked_positions: Dictionary = {}  # bone_idx (int) -> Vector3

# Hips→Spine 補償
var _hips_idx: int = -1
var _hips_idle_rot := Quaternion.IDENTITY
var _spine_idx: int = -1
var _spine_idle_rot := Quaternion.IDENTITY
var _spine_rest_rot := Quaternion.IDENTITY
var _spine_rest_rot_inv := Quaternion.IDENTITY


## ロックする回転を設定（アイドルアニメーションからサンプリングした値）
func lock_rotation(bone_idx: int, rot: Quaternion) -> void:
	_locked_rotations[bone_idx] = rot


## ロックする位置を設定（Hipsの垂直バウンス防止用）
func lock_position(bone_idx: int, pos: Vector3) -> void:
	_locked_positions[bone_idx] = pos


## Hips→Spine間の回転補償を設定
## Hipsの歩行回転をSpineのローカル回転で相殺し、
## Spine以上のグローバル回転をアイドルと同一にする
func set_hips_compensation(hips_idx: int, hips_idle_rot: Quaternion,
		spine_idx: int, spine_idle_rot: Quaternion,
		spine_rest_rot: Quaternion = Quaternion.IDENTITY) -> void:
	_hips_idx = hips_idx
	_hips_idle_rot = hips_idle_rot
	_spine_idx = spine_idx
	_spine_idle_rot = spine_idle_rot
	_spine_rest_rot = spine_rest_rot
	_spine_rest_rot_inv = spine_rest_rot.inverse()


func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return

	# Hips compensation: Spineのローカル回転を調整して
	# Hipsの歩行回転変動を相殺する
	# 正しい式: Spine_pose = inv(R_spine) * inv(P_hips_cur) * P_hips_idle * R_spine * P_spine_idle
	# （R_spine = Spineのrest rotation, P = pose rotation）
	# これにより Spine_global = Hips_global * (R_spine * Spine_pose) = idle時と同一になる
	var compensation_active := _hips_idx >= 0 and _spine_idx >= 0
	if compensation_active:
		var hips_current := skel.get_bone_pose_rotation(_hips_idx)
		var hips_correction := hips_current.inverse() * _hips_idle_rot
		# Rest rotation でコンジュゲーション: inv(R) * correction * R * idle_pose
		var compensated := _spine_rest_rot_inv * hips_correction * _spine_rest_rot * _spine_idle_rot
		skel.set_bone_pose_rotation(_spine_idx, compensated)

	# Lock other bones to idle rotation
	for bone_idx in _locked_rotations:
		if compensation_active and bone_idx == _spine_idx:
			continue  # Spine is handled by compensation above
		skel.set_bone_pose_rotation(bone_idx, _locked_rotations[bone_idx])

	for bone_idx in _locked_positions:
		skel.set_bone_pose_position(bone_idx, _locked_positions[bone_idx])
