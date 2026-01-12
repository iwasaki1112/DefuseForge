class_name WeaponComponent
extends Node

## 武器管理コンポーネント
## 武器装着、リコイル、左手IKを担当

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

## 左手IK（TwoBoneIK3D方式 - SkeletonModifier3Dベース）
var left_hand_target: Marker3D
var left_elbow_pole: Marker3D
var left_hand_ik: TwoBoneIK3D
var _ik_enabled: bool = false
var _left_hand_original_position: Vector3 = Vector3.ZERO


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

	# 右手ボーンを検索（Humanoid名 + ARP名）
	var right_hand_bones := ["RightHand", "c_hand_ik.r", "hand.r", "c_hand_fk.r"]
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

	# 左手IKをセットアップ
	_setup_left_hand_ik()


## リコイルを回復
func _recover_recoil() -> void:
	if _weapon_recoil_offset.length_squared() > 0.0001:
		_weapon_recoil_offset = _weapon_recoil_offset.lerp(Vector3.ZERO, RECOIL_RECOVERY_SPEED * get_process_delta_time())

		# 武器に反映
		if current_weapon and weapon_resource:
			current_weapon.position = weapon_resource.attach_position + _weapon_recoil_offset


## 武器をクリーンアップ
func _cleanup_weapon() -> void:
	_cleanup_left_hand_ik()

	if weapon_attachment:
		weapon_attachment.queue_free()
		weapon_attachment = null

	current_weapon = null


## 左手IKをセットアップ（TwoBoneIK3D - SkeletonModifier3Dベース）
func _setup_left_hand_ik() -> void:
	if skeleton == null or weapon_resource == null or current_weapon == null:
		return

	# IKが無効な武器の場合はスキップ
	if not weapon_resource.left_hand_ik_enabled:
		return

	# LeftHandGripマーカーを検索
	left_hand_target = _find_left_hand_grip()
	if left_hand_target == null:
		push_warning("[WeaponComponent] LeftHandGrip marker not found in weapon")
		return

	# 元の位置を保存
	_left_hand_original_position = left_hand_target.position

	# ティップボーン（手）を検索（Humanoid名 + ARP名）
	var tip_bone_name := ""
	var tip_bone_candidates := ["LeftHand", "hand.l", "c_hand_ik.l", "c_hand_fk.l"]
	for bone_name in tip_bone_candidates:
		if skeleton.find_bone(bone_name) >= 0:
			tip_bone_name = bone_name
			break

	if tip_bone_name.is_empty():
		push_warning("[WeaponComponent] Left hand tip bone not found")
		return

	# ルートボーン（上腕）を検索（Humanoid名 + ARP名）
	var root_bone_name := ""
	var root_bone_candidates := ["LeftUpperArm", "arm.l", "upperarm.l", "arm_stretch.l", "c_arm_ik.l", "shoulder.l"]
	for bone_name in root_bone_candidates:
		if skeleton.find_bone(bone_name) >= 0:
			root_bone_name = bone_name
			break

	if root_bone_name.is_empty():
		push_warning("[WeaponComponent] Left arm root bone not found")
		return

	# ボーンチェーンの検証（root -> middle -> tip）
	var tip_idx := skeleton.find_bone(tip_bone_name)
	var root_idx := skeleton.find_bone(root_bone_name)

	# ボーンチェーン検証
	var middle_idx := skeleton.get_bone_parent(tip_idx)

	if middle_idx < 0:
		push_warning("[WeaponComponent] Middle bone (tip parent) not found")
		return

	var middle_parent := skeleton.get_bone_parent(middle_idx)
	if middle_parent != root_idx:
		push_warning("[WeaponComponent] Invalid bone chain: middle parent=%d, root=%d" % [middle_parent, root_idx])
		return

	var middle_bone_name := skeleton.get_bone_name(middle_idx)

	# TwoBoneIK3Dノードを作成（SkeletonModifier3Dベース）
	left_hand_ik = TwoBoneIK3D.new()
	left_hand_ik.name = "LeftHandIK"

	# ボーン設定
	left_hand_ik.root_bone = root_bone_name
	left_hand_ik.tip_bone = tip_bone_name

	# Skeleton3Dの子として追加（SkeletonModifier3Dはこれで対象スケルトンを取得）
	skeleton.add_child(left_hand_ik)

	# ターゲット設定
	left_hand_ik.target_node = left_hand_target
	left_hand_ik.influence = 1.0
	left_hand_ik.active = true

	# ポールターゲット（肘の向き）を作成
	left_elbow_pole = _create_elbow_pole()
	if left_elbow_pole:
		left_hand_ik.pole_node = left_elbow_pole

	_ik_enabled = true


## 武器からLeftHandGripマーカーを検索
func _find_left_hand_grip() -> Marker3D:
	if current_weapon == null:
		return null

	# 直接の子ノードを検索
	for child in current_weapon.get_children():
		if child is Marker3D and "LeftHandGrip" in child.name:
			return child
		# Modelノード内を検索
		if child.name == "Model":
			for subchild in child.get_children():
				if subchild is Marker3D and "LeftHandGrip" in subchild.name:
					return subchild

	return null


## 肘ポールターゲットを動的に作成
func _create_elbow_pole() -> Marker3D:
	if skeleton == null or weapon_resource == null or left_hand_target == null:
		return null

	# ポールマーカーを作成（左手ターゲットからの相対位置）
	var pole = Marker3D.new()
	pole.name = "LeftElbowPole"

	# 左手ターゲットの子として追加
	left_hand_target.add_child(pole)

	# WeaponResourceの値を使用してポール位置を設定
	var pole_offset = Vector3(
		weapon_resource.left_elbow_pole_x,
		weapon_resource.left_elbow_pole_y,
		weapon_resource.left_elbow_pole_z
	)
	pole.position = pole_offset

	return pole


## ポール位置を更新（リアルタイム調整用）
func update_elbow_pole_position(x: float, y: float, z: float) -> void:
	if left_elbow_pole:
		left_elbow_pole.position = Vector3(x, y, z)
	if weapon_resource:
		weapon_resource.left_elbow_pole_x = x
		weapon_resource.left_elbow_pole_y = y
		weapon_resource.left_elbow_pole_z = z


## 左手位置を更新（リアルタイム調整用）
func update_left_hand_position(x: float, y: float, z: float) -> void:
	if weapon_resource:
		weapon_resource.left_hand_ik_position = Vector3(x, y, z)
	# LeftHandGripマーカーの位置を調整（元の位置＋オフセット）
	if left_hand_target:
		left_hand_target.position = _left_hand_original_position + Vector3(x, y, z)


## 左手IKターゲットを更新（毎フレーム呼び出し）- TwoBoneIK3Dが自動処理
func update_ik() -> void:
	pass  # TwoBoneIK3D handles this automatically


## アニメーション処理後にIKを適用 - TwoBoneIK3Dが自動処理
func apply_ik_after_animation() -> void:
	pass  # TwoBoneIK3D handles this automatically via _process_modification()


## 左手IKを有効化
func enable_ik() -> void:
	_ik_enabled = true
	if left_hand_ik:
		left_hand_ik.active = true


## 左手IKを無効化
func disable_ik() -> void:
	_ik_enabled = false
	if left_hand_ik:
		left_hand_ik.active = false


## 左手IKをクリーンアップ
func _cleanup_left_hand_ik() -> void:
	disable_ik()
	if left_elbow_pole:
		left_elbow_pole.queue_free()
		left_elbow_pole = null
	if left_hand_ik:
		left_hand_ik.queue_free()
		left_hand_ik = null
	left_hand_target = null
