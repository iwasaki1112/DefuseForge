@tool
class_name UpperBodyRotationModifier
extends SkeletonModifier3D

## 上半身回転モディファイア
## アニメーション処理後に複数のSpineボーンを回転させる

## 回転角度（ラジアン）- 左右
var rotation_angle: float = 0.0

## リコイル角度（ラジアン）- 後ろへの傾き
var recoil_angle: float = 0.0

## 内部
var _spine_bone_indices: Array[int] = []
var _initialized: bool = false


var _log_counter: int = 0

func _process(_delta: float) -> void:
	_log_counter += 1
	if _log_counter <= 5:
		print("[UpperBodyMod:%d] _process: active=%s, influence=%.2f, rotation_angle=%.3f" % [get_instance_id(), active, influence, rotation_angle])

func _process_modification() -> void:
	if _log_counter <= 10:
		print("[UpperBodyMod:%d] _process_modification() called, rotation_angle=%.3f, initialized=%s" % [get_instance_id(), rotation_angle, _initialized])

	if not _initialized:
		_initialize()
		if _initialized:
			print("[UpperBodyMod] Initialized with %d spine bones" % _spine_bone_indices.size())

	if not _initialized:
		return

	# 回転もリコイルも無ければスキップ
	if abs(rotation_angle) < 0.001 and abs(recoil_angle) < 0.001:
		if _log_counter <= 5:
			print("[UpperBodyMod] Skipping - rotation_angle too small: %.4f" % rotation_angle)
		return

	var skeleton := get_skeleton()
	if skeleton == null:
		return

	# 各スパインボーンに回転を適用（分散させる）
	var per_bone_angle = rotation_angle / max(_spine_bone_indices.size(), 1)
	var per_bone_recoil = recoil_angle / max(_spine_bone_indices.size(), 1)

	# デバッグ：60フレームごと + 最初の5回
	if Engine.get_process_frames() % 60 == 0 or _log_counter <= 10:
		print("[UpperBodyMod:%d] Applying rotation: %.2f rad (%.1f deg) to %d bones" % [get_instance_id(), rotation_angle, rad_to_deg(rotation_angle), _spine_bone_indices.size()])

	for bone_idx in _spine_bone_indices:
		var current_rotation = skeleton.get_bone_pose_rotation(bone_idx)
		var twist = Quaternion(Vector3.UP, per_bone_angle)  # 左右回転
		var kick = Quaternion(Vector3.RIGHT, -per_bone_recoil)  # 後ろへ傾く
		skeleton.set_bone_pose_rotation(bone_idx, current_rotation * twist * kick)


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
