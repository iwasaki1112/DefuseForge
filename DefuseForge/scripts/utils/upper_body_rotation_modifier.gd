@tool
class_name UpperBodyRotationModifier
extends SkeletonModifier3D

## 上半身回転モディファイア
## アニメーション処理後に複数のSpineボーンを回転させる

## 回転角度（ラジアン）- 左右（ヨー）
var rotation_angle: float = 0.0

## ピッチ角度（ラジアン）- 上下照準
var pitch_angle: float = 0.0

## リコイル角度（ラジアン）- 後ろへの傾き
var recoil_angle: float = 0.0

## 内部
var _spine_bone_indices: Array[int] = []
var _initialized: bool = false


func _process_modification() -> void:
	if not _initialized:
		_initialize()

	if not _initialized:
		return

	# 回転もピッチもリコイルも無ければスキップ
	if abs(rotation_angle) < 0.001 and abs(pitch_angle) < 0.001 and abs(recoil_angle) < 0.001:
		return

	var skeleton := get_skeleton()
	if skeleton == null:
		return

	# 各スパインボーンに回転を適用（分散させる）
	var bone_count = max(_spine_bone_indices.size(), 1)
	var per_bone_yaw = rotation_angle / bone_count
	var per_bone_pitch = pitch_angle / bone_count
	var per_bone_recoil = recoil_angle / bone_count

	for bone_idx in _spine_bone_indices:
		var current_rotation = skeleton.get_bone_pose_rotation(bone_idx)
		var twist = Quaternion(Vector3.UP, per_bone_yaw)  # 左右回転（ヨー）
		var pitch = Quaternion(Vector3.RIGHT, per_bone_pitch)  # 上下照準（ピッチ）
		var kick = Quaternion(Vector3.RIGHT, -per_bone_recoil)  # 後ろへ傾く（リコイル）
		skeleton.set_bone_pose_rotation(bone_idx, current_rotation * twist * pitch * kick)


func _initialize() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	_spine_bone_indices.clear()

	# スケルトンの全ボーンからspine/chest系を検索（大文字小文字無視）
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)
		var lower_name = bone_name.to_lower()

		# spine, chest を含むボーンを追加（ただし武器系は除外）
		if ("spine" in lower_name or "chest" in lower_name) \
			and "ik" not in lower_name and "ctrl" not in lower_name:
			_spine_bone_indices.append(i)

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


## ピッチ角度を設定（度）
func set_pitch_degrees(degrees: float) -> void:
	pitch_angle = deg_to_rad(degrees)


## ピッチ角度を設定（ラジアン）
func set_pitch_radians(radians: float) -> void:
	pitch_angle = radians
