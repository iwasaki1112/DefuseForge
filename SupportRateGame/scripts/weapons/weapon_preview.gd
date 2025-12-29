extends Node3D

## 武器プレビュー用シーンのスクリプト
## エディタ上で武器の位置・角度を確認・調整するためのシーン
##
## 操作方法:
## - 左クリック + ドラッグ: カメラ回転
## - マウスホイール: ズームイン/アウト

@export var weapon_scene: PackedScene
@export var character_model: PackedScene

## カメラ設定
@export var camera_distance: float = 2.5
@export var camera_height: float = 1.2
@export var rotation_speed: float = 0.005
@export var zoom_speed: float = 0.2
@export var min_distance: float = 1.0
@export var max_distance: float = 5.0

var character_instance: Node3D
var weapon_attachment: BoneAttachment3D
var weapon_instance: Node3D

var camera: Camera3D
var camera_pivot: Node3D
var camera_angle: float = 0.0
var camera_pitch: float = 0.3  # 初期の上下角度
var is_dragging: bool = false

func _ready() -> void:
	_setup_camera()
	_setup_preview()
	_show_instructions()


func _setup_camera() -> void:
	# カメラピボット（回転の中心）を作成
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0, camera_height, 0)
	add_child(camera_pivot)

	# カメラを作成
	camera = Camera3D.new()
	camera.name = "OrbitCamera"
	camera_pivot.add_child(camera)

	_update_camera_position()


func _update_camera_position() -> void:
	# 球面座標でカメラ位置を計算
	var x = camera_distance * cos(camera_pitch) * sin(camera_angle)
	var y = camera_distance * sin(camera_pitch)
	var z = camera_distance * cos(camera_pitch) * cos(camera_angle)

	camera.position = Vector3(x, y, z)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _show_instructions() -> void:
	print("")
	print("=== 武器プレビュー ===")
	print("操作方法:")
	print("  左クリック + ドラッグ: カメラ回転")
	print("  マウスホイール: ズームイン/アウト")
	print("======================")
	print("")


func _input(event: InputEvent) -> void:
	# マウスボタン
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		# 左クリック
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = mouse_event.pressed

		# マウスホイール（ズーム）
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(min_distance, camera_distance - zoom_speed)
			_update_camera_position()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(max_distance, camera_distance + zoom_speed)
			_update_camera_position()

	# マウス移動（ドラッグ中）
	if event is InputEventMouseMotion and is_dragging:
		var motion = event as InputEventMouseMotion
		camera_angle -= motion.relative.x * rotation_speed
		camera_pitch += motion.relative.y * rotation_speed
		# ピッチ角度を制限（-80度〜80度）
		camera_pitch = clamp(camera_pitch, -1.4, 1.4)
		_update_camera_position()


func _setup_preview() -> void:
	# キャラクターモデルをインスタンス化
	if character_model:
		character_instance = character_model.instantiate()
		character_instance.transform = Transform3D(
			Basis.IDENTITY.scaled(Vector3(2, 2, 2)),
			Vector3.ZERO
		)
		add_child(character_instance)

		# マテリアルをセットアップ
		CharacterSetup.setup_materials(character_instance, "WeaponPreview")

		# スケルトンを探す
		var skeleton = CharacterSetup.find_skeleton(character_instance)
		if skeleton:
			print("[WeaponPreview] Found skeleton: %s" % skeleton.name)
			_attach_weapon(skeleton)
		else:
			push_error("[WeaponPreview] Could not find skeleton in character model")


func _attach_weapon(skeleton: Skeleton3D) -> void:
	if weapon_scene == null:
		push_error("[WeaponPreview] No weapon scene assigned")
		return

	# 右手のボーンを探す
	var bone_name = "mixamorig_RightHand"
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx == -1:
		bone_name = "mixamorig1_RightHand"
		bone_idx = skeleton.find_bone(bone_name)

	if bone_idx == -1:
		push_error("[WeaponPreview] Could not find hand bone")
		return

	print("[WeaponPreview] Found bone: %s (index: %d)" % [bone_name, bone_idx])

	# BoneAttachment3Dを作成
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "WeaponAttachment"
	weapon_attachment.bone_name = bone_name
	skeleton.add_child(weapon_attachment)

	# 武器シーンをインスタンス化
	weapon_instance = weapon_scene.instantiate()
	weapon_attachment.add_child(weapon_instance)

	print("[WeaponPreview] Weapon attached successfully!")
	print("[WeaponPreview] Adjust the weapon position in: %s" % weapon_scene.resource_path)
