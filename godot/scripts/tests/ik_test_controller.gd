extends Node3D
## IK テストシーン コントローラー
##
## Godot 4.6 の新 IK システムを検証するためのテストシーン。
## - TwoBoneIK3D: 左腕・右腕
## - LookAtModifier3D: 頭（視線追従）
## - カメラ軌道回転（マウスドラッグ / スクロール）
## - 武器のposition/rotation調整スライダー

# ============================================
# Constants
# ============================================
const GROUND_SIZE := 20.0
const CHARACTER_PRESET_ID := "dummy_ct"
const DEFAULT_WEAPON_ID := "glock"
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const ANIMATION_SOURCE := "res://assets/animations/character_anims_kubold.glb"
const ANIMATION_SOURCE_MIXAMO := "res://assets/animations/character_anims_mixamo.glb"
const GRAVITY := 9.8

# IK Bone names (ARP / Unity Humanoid naming)
const BONE_LEFT_UPPER_ARM := "LeftUpperArm"
const BONE_LEFT_LOWER_ARM := "LeftLowerArm"
const BONE_LEFT_HAND := "LeftHand"
const BONE_RIGHT_UPPER_ARM := "RightUpperArm"
const BONE_RIGHT_LOWER_ARM := "RightLowerArm"
const BONE_RIGHT_HAND := "RightHand"
const BONE_HEAD := "Head"

# Slider range
const SLIDER_MIN := -2.0
const SLIDER_MAX := 2.0
const SLIDER_STEP := 0.01

# Rotation slider range (degrees)
const ROT_SLIDER_MIN := -180.0
const ROT_SLIDER_MAX := 180.0
const ROT_SLIDER_STEP := 0.5

# Default target positions - Rifle (キャラクター原点からの相対オフセット)
const DEFAULT_LEFT_POS := Vector3(-0.08, 1.43, 0.53)
const DEFAULT_RIGHT_POS := Vector3(-0.19, 1.39, 0.13)
const DEFAULT_LOOK_POS := Vector3(0.0, 1.5, 2.0)
const DEFAULT_LEFT_POLE := Vector3(0.09, 1.25, 0.51)
const DEFAULT_RIGHT_POLE := Vector3(-0.22, 1.13, -0.06)
const DEFAULT_LEFT_WRIST := Vector3(10.0, -10.5, 34.5)
const DEFAULT_RIGHT_WRIST := Vector3(-20.0, -30.0, -9.5)

# Default target positions - Pistol/Handgun
const PISTOL_LEFT_POS := Vector3(0.01, 1.35, 0.38)
const PISTOL_RIGHT_POS := Vector3(-0.15, 1.36, 0.23)
const PISTOL_LEFT_POLE := Vector3(0.09, 1.30, 0.29)
const PISTOL_RIGHT_POLE := Vector3(-0.22, 0.99, -0.06)
const PISTOL_LEFT_WRIST := Vector3(-10.0, 41.0, 31.5)
const PISTOL_RIGHT_WRIST := Vector3(-14.5, -33.5, 11.5)

# Weapon tilt range (degrees)
const TILT_MIN := -60.0
const TILT_MAX := 60.0
const TILT_STEP := 0.5

# Shoulder pivot (tilt時の回転中心、キャラ原点からの相対)
const SHOULDER_PIVOT_HEIGHT := 1.3

# Camera orbit
const CAMERA_ORBIT_SENSITIVITY := 0.005
const CAMERA_ZOOM_STEP := 0.3
const CAMERA_ZOOM_MIN := 1.5
const CAMERA_ZOOM_MAX := 15.0
const CAMERA_LOOK_HEIGHT := 0.9  # キャラ腰の高さ

# ============================================
# References
# ============================================
var _character: GameCharacter = null
var _camera: Camera3D = null
var _animation_library: AnimationLibrary = null
var _skeleton: Skeleton3D = null

# IK nodes
var _left_arm_ik: TwoBoneIK3D = null
var _right_arm_ik: TwoBoneIK3D = null
var _look_at: LookAtModifier3D = null

# Wrist rotation modifiers (SkeletonModifier3D, applied after IK)
var _left_wrist_mod: SkeletonModifier3D = null
var _right_wrist_mod: SkeletonModifier3D = null

# IK targets (Marker3D on skeleton)
var _left_ik_target: Marker3D = null
var _right_ik_target: Marker3D = null
var _left_ik_pole: Marker3D = null
var _right_ik_pole: Marker3D = null

# Visual targets (visible spheres)
var _left_target: Node3D = null
var _right_target: Node3D = null
var _look_target: Node3D = null
var _left_pole_visual: Node3D = null
var _right_pole_visual: Node3D = null

# Current offset values
var _left_offset := DEFAULT_LEFT_POS
var _right_offset := DEFAULT_RIGHT_POS
var _look_offset := DEFAULT_LOOK_POS

# Pole target offsets (キャラクター原点からの相対オフセット)
var _left_pole_offset := DEFAULT_LEFT_POLE
var _right_pole_offset := DEFAULT_RIGHT_POLE

# Wrist rotation (degrees)
var _left_wrist_rot := DEFAULT_LEFT_WRIST
var _right_wrist_rot := DEFAULT_RIGHT_WRIST

# Weapon socket adjustments
var _weapon_pos := Vector3(0.01, 0.07, 0.02)
var _weapon_rot := Vector3(-79.0, -66.0, -28.0)

# Weapon tilt (追加回転、ハイレディ/ローレディ用)
var _weapon_tilt := 0.0  # degrees
var _weapon_base_rot := Vector3.ZERO  # tilt適用前のベース回転

# Follow grips mode
var _follow_grips := false
var _left_grip_node: Node3D = null  # 武器モデル上のLeftHandGrip

# Camera orbit state
var _cam_yaw := 0.4        # 初期角度（やや右から）
var _cam_pitch := 0.25      # やや上から見下ろす
var _cam_distance := 4.5
var _cam_dragging := false

# Axis indicator
var _axis_camera: Camera3D = null

# UI labels
var _left_label: Label = null
var _right_label: Label = null
var _look_label: Label = null
var _left_wrist_label: Label = null
var _right_wrist_label: Label = null
var _left_pole_label: Label = null
var _right_pole_label: Label = null
var _tilt_label: Label = null

# Slider references for programmatic updates (weapon preset switch)
var _all_sliders: Dictionary = {}  # { "left_arm_0": HSlider, ... }

# State
var _ik_ready := false

# Undo history: Array of { callback: Callable, axis: int, old_val: float, slider: HSlider }
var _undo_stack: Array = []
const UNDO_MAX := 100

# Weapon
var _weapon_option: OptionButton = null
var _weapon_list: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_environment()
	_create_ground()
	_animation_library = _load_animation_library()
	PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	_spawn_character()
	_setup_camera()
	_setup_ui()


func _physics_process(delta: float) -> void:
	if _character and not _character.is_on_floor():
		_character.velocity.y -= GRAVITY * delta
		_character.move_and_slide()


func _process(_delta: float) -> void:
	if not _ik_ready:
		return
	_update_targets()
	_update_camera()


const UI_PANEL_WIDTH := 320.0

func _input(event: InputEvent) -> void:
	# Cmd+Z / Ctrl+Z: Undo（どこでも有効）
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_Z and key.is_command_or_control_pressed():
			_undo()
			get_viewport().set_input_as_handled()
			return

	# マウス操作: UIパネル領域外のみカメラ制御
	var mouse_pos := get_viewport().get_mouse_position()
	var vp_size := get_viewport().get_visible_rect().size
	var on_right_ui := mouse_pos.x > vp_size.x - 240.0 and mouse_pos.y < 140.0
	var on_ui := mouse_pos.x < UI_PANEL_WIDTH or on_right_ui

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 左ドラッグ or 右ドラッグでカメラ回転
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and on_ui:
				_cam_dragging = false
			else:
				_cam_dragging = mb.pressed
		if not on_ui:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cam_distance = maxf(_cam_distance - CAMERA_ZOOM_STEP, CAMERA_ZOOM_MIN)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cam_distance = minf(_cam_distance + CAMERA_ZOOM_STEP, CAMERA_ZOOM_MAX)

	if event is InputEventMouseMotion and _cam_dragging:
		var motion := event as InputEventMouseMotion
		_cam_yaw -= motion.relative.x * CAMERA_ORBIT_SENSITIVITY
		_cam_pitch = clampf(
			_cam_pitch - motion.relative.y * CAMERA_ORBIT_SENSITIVITY,
			-PI * 0.45, PI * 0.45
		)


# ============================================
# Scene Construction
# ============================================

func _setup_environment() -> void:
	var env_setup := EnvironmentSetup.new()
	env_setup.name = "EnvironmentSetup"
	if ResourceLoader.exists(DEFAULT_ENVIRONMENT_PRESET):
		var preset = load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
		if preset:
			env_setup.preset = preset
	add_child(env_setup)


func _create_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(GROUND_SIZE, 0.1, GROUND_SIZE)
	mesh_instance.mesh = box_mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.38, 0.35)
	mesh_instance.material_override = material
	ground.add_child(mesh_instance)

	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(GROUND_SIZE, 0.1, GROUND_SIZE)
	col_shape.shape = box_shape
	ground.add_child(col_shape)

	ground.position.y = -0.05
	add_child(ground)


# ============================================
# Character
# ============================================

func _spawn_character() -> void:
	var presets = CharacterRegistry.get_counter_terrorists()
	var preset: Resource = null
	for p in presets:
		if p.id == CHARACTER_PRESET_ID:
			preset = p
			break
	if not preset:
		if presets.size() > 0:
			preset = presets[0]
		else:
			printerr("IKTest: No character preset found")
			return

	_character = _create_character(preset, Vector3.ZERO)
	if _character:
		add_child(_character)


func _create_character(preset: Resource, spawn_pos: Vector3) -> GameCharacter:
	if not preset or not preset.model_scene:
		return null

	var model = preset.model_scene.instantiate()
	var character := GameCharacter.new()
	character.name = preset.id
	character.character_preset_id = preset.id
	character.position = spawn_pos
	character.team = preset.team

	model.name = "CharacterModel"
	character.add_child(model)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	character.add_child(collision)

	character.collision_mask = 7

	var anim_player := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		model.add_child(anim_player)

	if _animation_library:
		if anim_player.has_animation_library(""):
			anim_player.remove_animation_library("")
		anim_player.add_animation_library("", _animation_library)

	var anim_ctrl := CharacterAnimationController.new()
	character.add_child(anim_ctrl)
	character.set_anim_controller(anim_ctrl)

	character.ready.connect(func():
		anim_ctrl.setup(model, anim_player)
		var skel = anim_ctrl._skeleton
		if skel:
			model.position.y = -skel.position.y
			_skeleton = skel
		character.set_facing_direction_vec(Vector3(0, 0, 1))
		anim_ctrl.set_model_direction(Vector3(0, 0, 1))
		call_deferred("_deferred_character_setup")
	, CONNECT_ONE_SHOT)

	return character


func _deferred_character_setup() -> void:
	var weapon = WeaponRegistry.get_preset(DEFAULT_WEAPON_ID)
	if weapon and _character:
		_character.equip_weapon(weapon)
		_read_weapon_socket_values()
		_weapon_base_rot = _weapon_rot
		_find_left_hand_grip()
	_setup_ik()


func _load_animation_library() -> AnimationLibrary:
	if not ResourceLoader.exists(ANIMATION_SOURCE):
		return null
	var anim_scene = load(ANIMATION_SOURCE) as PackedScene
	if not anim_scene:
		return null
	var anim_instance = anim_scene.instantiate()
	var source_player = _find_animation_player(anim_instance)
	var lib: AnimationLibrary = null
	if source_player:
		lib = source_player.get_animation_library("")
	anim_instance.queue_free()

	# Merge mixamo animations (override kubold for movement anims)
	if lib and ResourceLoader.exists(ANIMATION_SOURCE_MIXAMO):
		var mixamo_scene = load(ANIMATION_SOURCE_MIXAMO) as PackedScene
		if mixamo_scene:
			var mixamo_instance = mixamo_scene.instantiate()
			var mixamo_player = _find_animation_player(mixamo_instance)
			if mixamo_player:
				var mixamo_lib = mixamo_player.get_animation_library("")
				if mixamo_lib:
					for anim_name in mixamo_lib.get_animation_list():
						if lib.has_animation(anim_name):
							lib.remove_animation(anim_name)
						lib.add_animation(anim_name, mixamo_lib.get_animation(anim_name))
			mixamo_instance.queue_free()

	return lib


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null


# ============================================
# Camera
# ============================================

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "IKTestCamera"
	_camera.fov = 40.0
	_camera.current = true
	add_child(_camera)


func _update_camera() -> void:
	var char_pos := _character.global_position if _character else Vector3.ZERO
	var target := char_pos + Vector3(0, CAMERA_LOOK_HEIGHT, 0)

	# 球面座標からカメラ位置を計算
	var offset := Vector3(
		cos(_cam_pitch) * sin(_cam_yaw),
		sin(_cam_pitch),
		cos(_cam_pitch) * cos(_cam_yaw)
	) * _cam_distance

	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)

	# 軸インジケーターカメラを同期
	if _axis_camera:
		var axis_dist := 2.5
		var axis_offset := Vector3(
			cos(_cam_pitch) * sin(_cam_yaw),
			sin(_cam_pitch),
			cos(_cam_pitch) * cos(_cam_yaw)
		) * axis_dist
		_axis_camera.position = axis_offset
		_axis_camera.look_at(Vector3.ZERO, Vector3.UP)


# ============================================
# Weapon Socket
# ============================================

func _read_weapon_socket_values() -> void:
	var socket = _character.get_weapon_socket()
	if socket:
		_weapon_pos = socket.position
		_weapon_rot = socket.rotation_degrees


func _apply_weapon_socket() -> void:
	var socket = _character.get_weapon_socket()
	if socket:
		socket.position = _weapon_pos
		socket.rotation_degrees = _weapon_rot


func _find_left_hand_grip() -> void:
	if not _character or not _character._weapon_model:
		_left_grip_node = null
		return
	_left_grip_node = _character._weapon_model.get_node_or_null(
		GameConstants.NODE_LEFT_HAND_GRIP) as Node3D


func _apply_weapon_tilt() -> void:
	var socket = _character.get_weapon_socket()
	if not socket:
		return
	# ベース回転 + tilt（ローカルX軸回転でバレルが上下に傾く）
	socket.rotation_degrees = _weapon_base_rot + Vector3(_weapon_tilt, 0, 0)


# ============================================
# IK Setup
# ============================================

func _setup_ik() -> void:
	if not _skeleton:
		printerr("IKTest: Skeleton not found, cannot setup IK")
		return

	# 既存の上半身IKを無効化（テストシーンは独自IKを使用）
	if _character.anim_ctrl._upper_body_ik:
		_character.anim_ctrl._upper_body_ik.disable_immediate()

	_create_targets()
	_setup_left_arm_ik()
	_setup_right_arm_ik()
	_setup_wrist_modifiers()
	_setup_look_at()
	_ik_ready = true
	print("IKTest: All IK modifiers ready")


func _create_targets() -> void:
	_left_target = _create_target_sphere("LeftArmTarget", Color(0.2, 0.5, 1.0))
	_right_target = _create_target_sphere("RightArmTarget", Color(1.0, 0.3, 0.2))
	_look_target = _create_target_sphere("LookTarget", Color(0.2, 1.0, 0.3))
	_left_pole_visual = _create_target_sphere("LeftPoleVisual", Color(0.4, 0.3, 0.8), 0.04)
	_right_pole_visual = _create_target_sphere("RightPoleVisual", Color(0.8, 0.4, 0.3), 0.04)
	add_child(_left_target)
	add_child(_right_target)
	add_child(_look_target)
	add_child(_left_pole_visual)
	add_child(_right_pole_visual)

	_left_ik_target = Marker3D.new()
	_left_ik_target.name = "LeftArmIKTarget"
	_skeleton.add_child(_left_ik_target)

	_right_ik_target = Marker3D.new()
	_right_ik_target.name = "RightArmIKTarget"
	_skeleton.add_child(_right_ik_target)

	_left_ik_pole = Marker3D.new()
	_left_ik_pole.name = "LeftArmIKPole"
	_skeleton.add_child(_left_ik_pole)

	_right_ik_pole = Marker3D.new()
	_right_ik_pole.name = "RightArmIKPole"
	_skeleton.add_child(_right_ik_pole)


func _create_target_sphere(node_name: String, color: Color, radius: float = 0.06) -> Node3D:
	var target := Node3D.new()
	target.name = node_name
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override = mat
	target.add_child(mesh_inst)
	return target


func _create_axis_line(parent: Node3D, direction: Vector3, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.02
	cylinder.bottom_radius = 0.02
	cylinder.height = 0.7
	mesh_inst.mesh = cylinder

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat

	# シリンダーはデフォルトでY軸方向 → 各軸に回転して配置
	if direction.is_equal_approx(Vector3.RIGHT):
		mesh_inst.rotation_degrees.z = -90.0
		mesh_inst.position.x = 0.35
	elif direction.is_equal_approx(Vector3.UP):
		mesh_inst.position.y = 0.35
	else:  # Z軸
		mesh_inst.rotation_degrees.x = 90.0
		mesh_inst.position.z = 0.35
	parent.add_child(mesh_inst)

	# 先端の円錐（矢印）
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.15
	tip.mesh = cone
	tip.material_override = mat

	if direction.is_equal_approx(Vector3.RIGHT):
		tip.rotation_degrees.z = -90.0
		tip.position.x = 0.75
	elif direction.is_equal_approx(Vector3.UP):
		tip.position.y = 0.75
	else:
		tip.rotation_degrees.x = 90.0
		tip.position.z = 0.75
	parent.add_child(tip)


func _setup_left_arm_ik() -> void:
	_left_arm_ik = TwoBoneIK3D.new()
	_left_arm_ik.name = "TestLeftArmIK"
	_left_arm_ik.active = true
	_left_arm_ik.influence = 1.0
	_skeleton.add_child(_left_arm_ik)
	_left_arm_ik.setting_count = 1
	_left_arm_ik.set_root_bone_name(0, BONE_LEFT_UPPER_ARM)
	_left_arm_ik.set_middle_bone_name(0, BONE_LEFT_LOWER_ARM)
	_left_arm_ik.set_end_bone_name(0, BONE_LEFT_HAND)
	_left_arm_ik.set_target_node(0, _left_arm_ik.get_path_to(_left_ik_target))
	_left_arm_ik.set_pole_node(0, _left_arm_ik.get_path_to(_left_ik_pole))
	if _left_arm_ik.has_method("reset"):
		_left_arm_ik.reset()


func _setup_right_arm_ik() -> void:
	_right_arm_ik = TwoBoneIK3D.new()
	_right_arm_ik.name = "TestRightArmIK"
	_right_arm_ik.active = true
	_right_arm_ik.influence = 1.0
	_skeleton.add_child(_right_arm_ik)
	_right_arm_ik.setting_count = 1
	_right_arm_ik.set_root_bone_name(0, BONE_RIGHT_UPPER_ARM)
	_right_arm_ik.set_middle_bone_name(0, BONE_RIGHT_LOWER_ARM)
	_right_arm_ik.set_end_bone_name(0, BONE_RIGHT_HAND)
	_right_arm_ik.set_target_node(0, _right_arm_ik.get_path_to(_right_ik_target))
	_right_arm_ik.set_pole_node(0, _right_arm_ik.get_path_to(_right_ik_pole))
	if _right_arm_ik.has_method("reset"):
		_right_arm_ik.reset()


func _setup_wrist_modifiers() -> void:
	var WristRotScript = load("res://scripts/tests/wrist_rotation_modifier.gd")

	_left_wrist_mod = WristRotScript.new()
	_left_wrist_mod.name = "LeftWristRotation"
	_left_wrist_mod.bone_name = BONE_LEFT_HAND
	_left_wrist_mod.extra_rotation_deg = _left_wrist_rot
	_left_wrist_mod.active = true
	_skeleton.add_child(_left_wrist_mod)

	_right_wrist_mod = WristRotScript.new()
	_right_wrist_mod.name = "RightWristRotation"
	_right_wrist_mod.bone_name = BONE_RIGHT_HAND
	_right_wrist_mod.extra_rotation_deg = _right_wrist_rot
	_right_wrist_mod.active = true
	_skeleton.add_child(_right_wrist_mod)


func _setup_look_at() -> void:
	_look_at = LookAtModifier3D.new()
	_look_at.name = "TestLookAt"
	_look_at.active = true
	_look_at.influence = 1.0
	_look_at.bone_name = BONE_HEAD
	_skeleton.add_child(_look_at)
	_look_at.target_node = _look_at.get_path_to(_look_target)


# ============================================
# Target Update
# ============================================

func _update_targets() -> void:
	var char_pos := _character.global_position if _character else Vector3.ZERO

	if _follow_grips:
		# 肩ピボットを中心にtiltで右手位置を回転
		var pivot := char_pos + Vector3(_right_offset.x, SHOULDER_PIVOT_HEIGHT, 0.0)
		var hand_base := char_pos + _right_offset
		var tilt_rad := deg_to_rad(_weapon_tilt)
		var to_hand := hand_base - pivot
		var rotated := to_hand.rotated(Vector3(1, 0, 0), tilt_rad)
		var right_pos := pivot + rotated
		_right_target.global_position = right_pos
		if _right_ik_target:
			_right_ik_target.global_position = right_pos

		# 左手: 武器上のLeftHandGripに追従（1フレーム遅延あり）
		if _left_grip_node and is_instance_valid(_left_grip_node):
			var grip_pos := _left_grip_node.global_position
			_left_target.global_position = grip_pos
			if _left_ik_target:
				_left_ik_target.global_position = grip_pos
		else:
			# LeftHandGripがない武器: 左手も肩ピボット回転
			var left_base := char_pos + _left_offset
			var to_left := left_base - pivot
			var left_rotated := to_left.rotated(Vector3(1, 0, 0), tilt_rad)
			var left_pos := pivot + left_rotated
			_left_target.global_position = left_pos
			if _left_ik_target:
				_left_ik_target.global_position = left_pos
	else:
		# マニュアルモード
		var left_pos := char_pos + _left_offset
		_left_target.global_position = left_pos
		if _left_ik_target:
			_left_ik_target.global_position = left_pos

		var right_pos := char_pos + _right_offset
		_right_target.global_position = right_pos
		if _right_ik_target:
			_right_ik_target.global_position = right_pos

	_update_pole_targets()

	_look_target.global_position = char_pos + _look_offset


func _update_pole_targets() -> void:
	var char_pos := _character.global_position if _character else Vector3.ZERO

	if _left_ik_pole:
		var pole_pos := char_pos + _left_pole_offset
		_left_ik_pole.global_position = pole_pos
		if _left_pole_visual:
			_left_pole_visual.global_position = pole_pos

	if _right_ik_pole:
		var pole_pos := char_pos + _right_pole_offset
		_right_ik_pole.global_position = pole_pos
		if _right_pole_visual:
			_right_pole_visual.global_position = pole_pos


# ============================================
# UI
# ============================================

func _setup_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	# 左パネル
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = 320
	panel.size.x = 320
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	panel.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "IK Test (Godot 4.6)"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# Camera hint
	var cam_hint := Label.new()
	cam_hint.text = "Camera: Drag rotate (right area), Scroll zoom"
	cam_hint.add_theme_font_size_override("font_size", 11)
	cam_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(cam_hint)

	# Weapon selector
	_add_weapon_selector(vbox)

	vbox.add_child(HSeparator.new())

	# === Weapon Tilt (ハイレディ/ローレディ) ===
	_add_section_label(vbox, "Weapon Tilt", Color(1.0, 0.6, 0.1))
	_tilt_label = Label.new()
	_tilt_label.add_theme_font_size_override("font_size", 13)
	_tilt_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	_tilt_label.text = "0.0"
	vbox.add_child(_tilt_label)
	_add_axis_slider(vbox, "Tilt", Color(1.0, 0.6, 0.1), 0.0, 0, _on_tilt_slider, TILT_MIN, TILT_MAX, TILT_STEP)

	# Follow Grips toggle
	var grip_toggle := CheckButton.new()
	grip_toggle.text = "Follow Grips (left hand auto)"
	grip_toggle.button_pressed = false
	grip_toggle.toggled.connect(_on_follow_grips_toggled)
	vbox.add_child(grip_toggle)

	vbox.add_child(HSeparator.new())

	# === Left Arm ===
	_left_label = _add_ik_section(vbox, "Left Arm (Blue)", Color(0.3, 0.6, 1.0),
		DEFAULT_LEFT_POS, _on_left_slider, _on_left_toggle, "left_arm")

	# Left Elbow (Pole Target)
	_add_section_label(vbox, "  Left Elbow Pole", Color(0.4, 0.3, 0.8))
	_left_pole_label = Label.new()
	_left_pole_label.add_theme_font_size_override("font_size", 13)
	_left_pole_label.add_theme_color_override("font_color", Color(0.4, 0.3, 0.8))
	vbox.add_child(_left_pole_label)
	_add_axis_slider(vbox, "X", Color(0.9, 0.3, 0.3), DEFAULT_LEFT_POLE.x, 0, _on_left_pole_slider, SLIDER_MIN, SLIDER_MAX, SLIDER_STEP, "left_pole_0")
	_add_axis_slider(vbox, "Y", Color(0.3, 0.9, 0.3), DEFAULT_LEFT_POLE.y, 1, _on_left_pole_slider, SLIDER_MIN, SLIDER_MAX, SLIDER_STEP, "left_pole_1")
	_add_axis_slider(vbox, "Z", Color(0.3, 0.3, 0.9), DEFAULT_LEFT_POLE.z, 2, _on_left_pole_slider, SLIDER_MIN, SLIDER_MAX, SLIDER_STEP, "left_pole_2")
	_update_value_label(_left_pole_label, _left_pole_offset)

	# Left Wrist Rotation
	_add_section_label(vbox, "  Left Wrist Rot", Color(0.3, 0.5, 0.8))
	_left_wrist_label = Label.new()
	_left_wrist_label.add_theme_font_size_override("font_size", 13)
	_left_wrist_label.add_theme_color_override("font_color", Color(0.3, 0.5, 0.8))
	vbox.add_child(_left_wrist_label)
	_add_axis_slider(vbox, "X", Color(0.9, 0.3, 0.3), _left_wrist_rot.x, 0, _on_left_wrist_slider, ROT_SLIDER_MIN, ROT_SLIDER_MAX, ROT_SLIDER_STEP, "left_wrist_0")
	_add_axis_slider(vbox, "Y", Color(0.3, 0.9, 0.3), _left_wrist_rot.y, 1, _on_left_wrist_slider, ROT_SLIDER_MIN, ROT_SLIDER_MAX, ROT_SLIDER_STEP, "left_wrist_1")
	_add_axis_slider(vbox, "Z", Color(0.3, 0.3, 0.9), _left_wrist_rot.z, 2, _on_left_wrist_slider, ROT_SLIDER_MIN, ROT_SLIDER_MAX, ROT_SLIDER_STEP, "left_wrist_2")
	_update_rot_label(_left_wrist_label, _left_wrist_rot)

	vbox.add_child(HSeparator.new())

	# === Right Arm ===
	_right_label = _add_ik_section(vbox, "Right Arm (Red)", Color(1.0, 0.4, 0.3),
		DEFAULT_RIGHT_POS, _on_right_slider, _on_right_toggle, "right_arm")

	# Right Elbow (Pole Target)
	_add_section_label(vbox, "  Right Elbow Pole", Color(0.8, 0.4, 0.3))
	_right_pole_label = Label.new()
	_right_pole_label.add_theme_font_size_override("font_size", 13)
	_right_pole_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.3))
	vbox.add_child(_right_pole_label)
	_add_axis_slider(vbox, "X", Color(0.9, 0.3, 0.3), DEFAULT_RIGHT_POLE.x, 0, _on_right_pole_slider, SLIDER_MIN, SLIDER_MAX, SLIDER_STEP, "right_pole_0")
	_add_axis_slider(vbox, "Y", Color(0.3, 0.9, 0.3), DEFAULT_RIGHT_POLE.y, 1, _on_right_pole_slider, SLIDER_MIN, SLIDER_MAX, SLIDER_STEP, "right_pole_1")
	_add_axis_slider(vbox, "Z", Color(0.3, 0.3, 0.9), DEFAULT_RIGHT_POLE.z, 2, _on_right_pole_slider, SLIDER_MIN, SLIDER_MAX, SLIDER_STEP, "right_pole_2")
	_update_value_label(_right_pole_label, _right_pole_offset)

	# Right Wrist Rotation
	_add_section_label(vbox, "  Right Wrist Rot", Color(0.8, 0.3, 0.3))
	_right_wrist_label = Label.new()
	_right_wrist_label.add_theme_font_size_override("font_size", 13)
	_right_wrist_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
	vbox.add_child(_right_wrist_label)
	_add_axis_slider(vbox, "X", Color(0.9, 0.3, 0.3), _right_wrist_rot.x, 0, _on_right_wrist_slider, ROT_SLIDER_MIN, ROT_SLIDER_MAX, ROT_SLIDER_STEP, "right_wrist_0")
	_add_axis_slider(vbox, "Y", Color(0.3, 0.9, 0.3), _right_wrist_rot.y, 1, _on_right_wrist_slider, ROT_SLIDER_MIN, ROT_SLIDER_MAX, ROT_SLIDER_STEP, "right_wrist_1")
	_add_axis_slider(vbox, "Z", Color(0.3, 0.3, 0.9), _right_wrist_rot.z, 2, _on_right_wrist_slider, ROT_SLIDER_MIN, ROT_SLIDER_MAX, ROT_SLIDER_STEP, "right_wrist_2")
	_update_rot_label(_right_wrist_label, _right_wrist_rot)

	vbox.add_child(HSeparator.new())

	# === Head LookAt ===
	_look_label = _add_ik_section(vbox, "Head LookAt (Green)", Color(0.3, 1.0, 0.4),
		DEFAULT_LOOK_POS, _on_look_slider, _on_look_toggle)

	# ============================================
	# 右上エリア: カメラビューボタン + 軸インジケーター
	# ============================================
	var right_vbox := VBoxContainer.new()
	right_vbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_vbox.anchor_left = 1.0
	right_vbox.anchor_right = 1.0
	right_vbox.anchor_top = 0.0
	right_vbox.anchor_bottom = 0.0
	right_vbox.offset_left = -230
	right_vbox.offset_top = 8
	right_vbox.offset_right = -8
	right_vbox.add_theme_constant_override("separation", 8)
	right_vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui_layer.add_child(right_vbox)

	# カメラビューボタン
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 4)
	right_vbox.add_child(btn_hbox)

	var view_presets := [
		{ "label": "Front", "yaw": 0.0, "pitch": 0.0 },
		{ "label": "Back", "yaw": PI, "pitch": 0.0 },
		{ "label": "Left", "yaw": PI / 2.0, "pitch": 0.0 },
		{ "label": "Right", "yaw": -PI / 2.0, "pitch": 0.0 },
	]
	for vd in view_presets:
		var btn := Button.new()
		btn.text = vd["label"]
		btn.custom_minimum_size = Vector2(52, 28)
		var yaw_val: float = vd["yaw"]
		var pitch_val: float = vd["pitch"]
		btn.pressed.connect(func(): _cam_yaw = yaw_val; _cam_pitch = pitch_val)
		btn_hbox.add_child(btn)

	# 軸インジケーター（SubViewport方式）
	var axis_container := SubViewportContainer.new()
	axis_container.custom_minimum_size = Vector2(80, 80)
	axis_container.stretch = true
	axis_container.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_vbox.add_child(axis_container)

	var axis_viewport := SubViewport.new()
	axis_viewport.size = Vector2i(80, 80)
	axis_viewport.transparent_bg = true
	axis_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	axis_container.add_child(axis_viewport)

	_axis_camera = Camera3D.new()
	_axis_camera.fov = 40.0
	axis_viewport.add_child(_axis_camera)

	var axis_origin := Node3D.new()
	axis_origin.name = "AxisOrigin"
	axis_viewport.add_child(axis_origin)

	# X軸（赤）
	_create_axis_line(axis_origin, Vector3.RIGHT, Color(0.9, 0.2, 0.2))
	# Y軸（緑）
	_create_axis_line(axis_origin, Vector3.UP, Color(0.2, 0.9, 0.2))
	# Z軸（青）
	_create_axis_line(axis_origin, Vector3(0, 0, 1), Color(0.2, 0.4, 0.9))


func _add_section_label(parent: Control, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _add_weapon_selector(parent: Control) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var label := Label.new()
	label.text = "Weapon:"
	hbox.add_child(label)

	_weapon_option = OptionButton.new()
	_weapon_option.custom_minimum_size.x = 140
	_weapon_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_weapon_option)

	_weapon_list = WeaponRegistry.get_all()
	var default_idx := 0
	for i in range(_weapon_list.size()):
		var w: WeaponPreset = _weapon_list[i]
		_weapon_option.add_item(w.display_name, i)
		if w.id == DEFAULT_WEAPON_ID:
			default_idx = i
	_weapon_option.selected = default_idx
	_weapon_option.item_selected.connect(_on_weapon_selected)


func _on_weapon_selected(idx: int) -> void:
	if not _character or idx < 0 or idx >= _weapon_list.size():
		return
	var weapon: WeaponPreset = _weapon_list[idx]
	_character.equip_weapon(weapon)
	_read_weapon_socket_values()
	_weapon_base_rot = _weapon_rot
	_find_left_hand_grip()
	# tiltを再適用
	if _weapon_tilt != 0.0:
		_apply_weapon_tilt()
	# 武器カテゴリに応じてIKプリセットを切替
	_apply_ik_preset_for_weapon(weapon)


## 武器カテゴリに応じてIKスライダーをプリセット値に切替
func _apply_ik_preset_for_weapon(weapon: WeaponPreset) -> void:
	var is_pistol := weapon.category == WeaponPreset.WeaponCategory.PISTOL
	var left_pos := PISTOL_LEFT_POS if is_pistol else DEFAULT_LEFT_POS
	var right_pos := PISTOL_RIGHT_POS if is_pistol else DEFAULT_RIGHT_POS
	var left_pole := PISTOL_LEFT_POLE if is_pistol else DEFAULT_LEFT_POLE
	var right_pole := PISTOL_RIGHT_POLE if is_pistol else DEFAULT_RIGHT_POLE
	var left_wrist := PISTOL_LEFT_WRIST if is_pistol else DEFAULT_LEFT_WRIST
	var right_wrist := PISTOL_RIGHT_WRIST if is_pistol else DEFAULT_RIGHT_WRIST

	# スライダー値を更新（value_changed コールバックが自動で状態更新）
	var presets := {
		"left_arm": left_pos, "right_arm": right_pos,
		"left_pole": left_pole, "right_pole": right_pole,
		"left_wrist": left_wrist, "right_wrist": right_wrist,
	}
	for prefix in presets:
		var vec: Vector3 = presets[prefix]
		for i in range(3):
			var key := "%s_%d" % [prefix, i]
			if _all_sliders.has(key):
				_all_sliders[key].value = vec[i]


func _add_ik_section(parent: Control, title_text: String, color: Color,
		default_pos: Vector3, on_slider_changed: Callable,
		on_toggle: Callable, key_prefix: String = "") -> Label:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	parent.add_child(header)

	var toggle := CheckButton.new()
	toggle.button_pressed = true
	toggle.text = title_text
	toggle.toggled.connect(on_toggle)
	header.add_child(toggle)

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", color)
	_update_value_label(value_label, default_pos)
	parent.add_child(value_label)

	var axes := ["X", "Y", "Z"]
	var colors := [Color(0.9, 0.3, 0.3), Color(0.3, 0.9, 0.3), Color(0.3, 0.3, 0.9)]
	for i in range(3):
		var key := "%s_%d" % [key_prefix, i] if key_prefix != "" else ""
		_add_axis_slider(parent, axes[i], colors[i], default_pos[i], i, on_slider_changed, SLIDER_MIN, SLIDER_MAX, SLIDER_STEP, key)

	return value_label


func _add_axis_slider(parent: Control, axis_name: String, color: Color,
		default_val: float, axis_idx: int, callback: Callable,
		min_val: float = SLIDER_MIN, max_val: float = SLIDER_MAX,
		step_val: float = SLIDER_STEP, slider_key: String = "") -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	parent.add_child(hbox)

	var label := Label.new()
	label.text = axis_name
	label.custom_minimum_size.x = 16
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 160
	hbox.add_child(slider)

	var val_label := Label.new()
	val_label.text = _format_val(default_val, step_val)
	val_label.custom_minimum_size.x = 55
	val_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(val_label)

	# Undo用: 前の値を保持
	var prev_val := [default_val]  # Arrayで参照渡し
	slider.value_changed.connect(func(val: float):
		_push_undo(callback, axis_idx, prev_val[0], slider)
		prev_val[0] = val
		val_label.text = _format_val(val, step_val)
		callback.call(axis_idx, val)
	)

	# スライダー参照を保存（武器切替時のプログラム更新用）
	if slider_key != "":
		_all_sliders[slider_key] = slider


func _format_val(val: float, step: float) -> String:
	if step >= 0.5:
		return "%.1f" % val
	return "%.2f" % val


# ============================================
# Undo
# ============================================

var _undo_in_progress := false

func _push_undo(callback: Callable, axis: int, old_val: float, slider: HSlider) -> void:
	if _undo_in_progress:
		return
	_undo_stack.append({ "callback": callback, "axis": axis, "old_val": old_val, "slider": slider })
	if _undo_stack.size() > UNDO_MAX:
		_undo_stack.pop_front()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	_undo_in_progress = true
	# スライダーのvalueを戻す → value_changedが発火してcallbackも呼ばれる
	entry["slider"].value = entry["old_val"]
	_undo_in_progress = false


# ============================================
# Slider Callbacks
# ============================================

func _on_tilt_slider(_axis: int, val: float) -> void:
	_weapon_tilt = val
	_apply_weapon_tilt()
	if _tilt_label:
		_tilt_label.text = "%.1f deg" % val

func _on_follow_grips_toggled(enabled: bool) -> void:
	_follow_grips = enabled

func _on_left_wrist_slider(axis: int, val: float) -> void:
	_left_wrist_rot[axis] = val
	if _left_wrist_mod:
		_left_wrist_mod.extra_rotation_deg = _left_wrist_rot
	_update_rot_label(_left_wrist_label, _left_wrist_rot)

func _on_right_wrist_slider(axis: int, val: float) -> void:
	_right_wrist_rot[axis] = val
	if _right_wrist_mod:
		_right_wrist_mod.extra_rotation_deg = _right_wrist_rot
	_update_rot_label(_right_wrist_label, _right_wrist_rot)

func _on_left_slider(axis: int, val: float) -> void:
	_left_offset[axis] = val
	_update_value_label(_left_label, _left_offset)

func _on_left_pole_slider(axis: int, val: float) -> void:
	_left_pole_offset[axis] = val
	_update_value_label(_left_pole_label, _left_pole_offset)

func _on_left_toggle(enabled: bool) -> void:
	if _left_arm_ik: _left_arm_ik.influence = 1.0 if enabled else 0.0
	if _left_target: _left_target.visible = enabled
	if _left_pole_visual: _left_pole_visual.visible = enabled

func _on_right_slider(axis: int, val: float) -> void:
	_right_offset[axis] = val
	_update_value_label(_right_label, _right_offset)

func _on_right_pole_slider(axis: int, val: float) -> void:
	_right_pole_offset[axis] = val
	_update_value_label(_right_pole_label, _right_pole_offset)

func _on_right_toggle(enabled: bool) -> void:
	if _right_arm_ik: _right_arm_ik.influence = 1.0 if enabled else 0.0
	if _right_target: _right_target.visible = enabled
	if _right_pole_visual: _right_pole_visual.visible = enabled

func _on_look_slider(axis: int, val: float) -> void:
	_look_offset[axis] = val
	_update_value_label(_look_label, _look_offset)

func _on_look_toggle(enabled: bool) -> void:
	if _look_at: _look_at.influence = 1.0 if enabled else 0.0
	if _look_target: _look_target.visible = enabled

func _update_value_label(label: Label, pos: Vector3) -> void:
	if label:
		label.text = "Vector3(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z]

func _update_rot_label(label: Label, rot: Vector3) -> void:
	if label:
		label.text = "Vector3(%.1f, %.1f, %.1f)" % [rot.x, rot.y, rot.z]
