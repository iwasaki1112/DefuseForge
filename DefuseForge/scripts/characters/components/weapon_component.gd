class_name WeaponComponent
extends Node

## 武器管理コンポーネント
## 武器装着、リコイルを担当

signal weapon_changed(weapon_id: int)

## 内部参照
var skeleton: Skeleton3D
var weapon_attachment: BoneAttachment3D
var current_weapon: Node3D
var weapon_resource: WeaponResource

## 武器状態
var current_weapon_id: int = 0  # WeaponRegistry.WeaponId.NONE

## リコイル
var _weapon_recoil_offset: Vector3 = Vector3.ZERO
const RECOIL_RECOVERY_SPEED: float = 8.0


func _ready() -> void:
	pass


## 初期化
## @param skel: Skeleton3D
func setup(skel: Skeleton3D) -> void:
	skeleton = skel


## 武器を設定
## @param weapon_id: WeaponRegistry.WeaponId
func set_weapon(weapon_id: int) -> void:
	if current_weapon_id == weapon_id:
		return

	# 既存の武器を削除
	_cleanup_weapon()

	current_weapon_id = weapon_id

	# 武器なしの場合
	if weapon_id == WeaponRegistry.WeaponId.NONE:
		weapon_resource = null
		weapon_changed.emit(weapon_id)
		return

	# WeaponResourceをロード
	weapon_resource = WeaponRegistry.get_weapon(weapon_id)
	if weapon_resource == null:
		push_error("[WeaponComponent] Failed to load weapon resource for id: %d" % weapon_id)
		return

	# 武器を装着
	_attach_weapon()

	weapon_changed.emit(weapon_id)


## 現在の武器IDを取得
func get_weapon_id() -> int:
	return current_weapon_id


## 武器リソースを取得
func get_weapon_resource() -> WeaponResource:
	return weapon_resource


## リコイルを適用
## @param intensity: リコイル強度（0.0 - 1.0）
func apply_recoil(intensity: float) -> void:
	# 武器を後ろに跳ねさせる
	_weapon_recoil_offset = Vector3(0, 0.02, 0.05) * intensity


## 毎フレーム更新（リコイル回復）
func update() -> void:
	_recover_recoil()


## 武器を装着
func _attach_weapon() -> void:
	if skeleton == null or weapon_resource == null:
		return

	# 右手ボーンを検索
	var right_hand_bones := ["c_hand_ik.r", "hand.r", "c_hand_fk.r"]
	var bone_idx := -1
	for bone_name in right_hand_bones:
		bone_idx = skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			break

	if bone_idx < 0:
		push_warning("[WeaponComponent] Right hand bone not found")
		return

	# BoneAttachment3Dを作成
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "WeaponAttachment"
	weapon_attachment.bone_idx = bone_idx
	skeleton.add_child(weapon_attachment)

	# 武器シーンをロード
	if not ResourceLoader.exists(weapon_resource.scene_path):
		push_error("[WeaponComponent] Weapon scene not found: %s" % weapon_resource.scene_path)
		return

	var weapon_scene = load(weapon_resource.scene_path)
	if weapon_scene == null:
		push_error("[WeaponComponent] Failed to load weapon scene: %s" % weapon_resource.scene_path)
		return

	current_weapon = weapon_scene.instantiate()
	weapon_attachment.add_child(current_weapon)

	# スケルトンのスケール補正
	var skeleton_scale = skeleton.global_transform.basis.get_scale()
	if skeleton_scale.x < 0.5:
		var compensation = 1.0 / skeleton_scale.x
		current_weapon.scale = Vector3(compensation, compensation, compensation)

	# 装着位置を適用
	current_weapon.position = weapon_resource.attach_position
	current_weapon.rotation_degrees = weapon_resource.attach_rotation


## リコイルを回復
func _recover_recoil() -> void:
	if _weapon_recoil_offset.length_squared() > 0.0001:
		_weapon_recoil_offset = _weapon_recoil_offset.lerp(Vector3.ZERO, RECOIL_RECOVERY_SPEED * get_process_delta_time())

		# 武器に反映
		if current_weapon and weapon_resource:
			current_weapon.position = weapon_resource.attach_position + _weapon_recoil_offset


## 武器をクリーンアップ
func _cleanup_weapon() -> void:
	if weapon_attachment:
		weapon_attachment.queue_free()
		weapon_attachment = null

	current_weapon = null
