extends Node3D
## 武器位置調整用ツールシーン
##
## キャラクターに武器を持たせ、位置・回転オフセットをリアルタイムに調整する機能を提供する。
## マズルフラッシュの位置/回転/スケール調整も可能。
## 
## 主な機能:
## - キャラクターの切り替え
## - 武器の切り替え
## - 武器のアタッチ位置(Offset)・回転(Rotation)の調整
## - カメラアングル操作
## - マズルフラッシュ調整

# UI References
@onready var character_option: OptionButton = $UI/Panel/VBox/CharacterOption
@onready var weapon_option: OptionButton = $UI/Panel/VBox/WeaponOption
@onready var fire_button: Button = $UI/Panel/VBox/FireButton
@onready var pos_x_spin: SpinBox = $UI/Panel/VBox/PosX/SpinBox
@onready var pos_x_slider: HSlider = $UI/Panel/VBox/PosX/HSlider
@onready var pos_y_spin: SpinBox = $UI/Panel/VBox/PosY/SpinBox
@onready var pos_y_slider: HSlider = $UI/Panel/VBox/PosY/HSlider
@onready var pos_z_spin: SpinBox = $UI/Panel/VBox/PosZ/SpinBox
@onready var pos_z_slider: HSlider = $UI/Panel/VBox/PosZ/HSlider

@onready var rot_x_spin: SpinBox = $UI/Panel/VBox/RotX/SpinBox
@onready var rot_x_slider: HSlider = $UI/Panel/VBox/RotX/HSlider
@onready var rot_y_spin: SpinBox = $UI/Panel/VBox/RotY/SpinBox
@onready var rot_y_slider: HSlider = $UI/Panel/VBox/RotY/HSlider
@onready var rot_z_spin: SpinBox = $UI/Panel/VBox/RotZ/SpinBox
@onready var rot_z_slider: HSlider = $UI/Panel/VBox/RotZ/HSlider
@onready var muzzle_pos_x_spin: SpinBox = $UI/PanelLeft/VBoxLeft/MuzzlePosX/SpinBox
@onready var muzzle_pos_x_slider: HSlider = $UI/PanelLeft/VBoxLeft/MuzzlePosX/HSlider
@onready var muzzle_pos_y_spin: SpinBox = $UI/PanelLeft/VBoxLeft/MuzzlePosY/SpinBox
@onready var muzzle_pos_y_slider: HSlider = $UI/PanelLeft/VBoxLeft/MuzzlePosY/HSlider
@onready var muzzle_pos_z_spin: SpinBox = $UI/PanelLeft/VBoxLeft/MuzzlePosZ/SpinBox
@onready var muzzle_pos_z_slider: HSlider = $UI/PanelLeft/VBoxLeft/MuzzlePosZ/HSlider
@onready var muzzle_scale_spin: SpinBox = $UI/PanelLeft/VBoxLeft/MuzzleScale/SpinBox
@onready var muzzle_scale_slider: HSlider = $UI/PanelLeft/VBoxLeft/MuzzleScale/HSlider
@onready var muzzle_rot_x_spin: SpinBox = $UI/PanelLeft/VBoxLeft/MuzzleRotX/SpinBox
@onready var muzzle_rot_x_slider: HSlider = $UI/PanelLeft/VBoxLeft/MuzzleRotX/HSlider
@onready var muzzle_rot_y_spin: SpinBox = $UI/PanelLeft/VBoxLeft/MuzzleRotY/SpinBox
@onready var muzzle_rot_y_slider: HSlider = $UI/PanelLeft/VBoxLeft/MuzzleRotY/HSlider
@onready var muzzle_rot_z_spin: SpinBox = $UI/PanelLeft/VBoxLeft/MuzzleRotZ/SpinBox
@onready var muzzle_rot_z_slider: HSlider = $UI/PanelLeft/VBoxLeft/MuzzleRotZ/HSlider
@onready var quad1_x_spin: SpinBox = $UI/PanelLeft/VBoxLeft/Quad1X/SpinBox
@onready var quad1_x_slider: HSlider = $UI/PanelLeft/VBoxLeft/Quad1X/HSlider
@onready var quad1_z_spin: SpinBox = $UI/PanelLeft/VBoxLeft/Quad1Z/SpinBox
@onready var quad1_z_slider: HSlider = $UI/PanelLeft/VBoxLeft/Quad1Z/HSlider
@onready var muzzle_preview_toggle: CheckBox = $UI/PanelLeft/VBoxLeft/MuzzlePreviewToggle
@onready var grip_toggle: CheckBox = $UI/PanelLeft/VBoxLeft/GripToggle
@onready var grip_x_spin: SpinBox = $UI/PanelLeft/VBoxLeft/GripX/SpinBox
@onready var grip_x_slider: HSlider = $UI/PanelLeft/VBoxLeft/GripX/HSlider
@onready var grip_y_spin: SpinBox = $UI/PanelLeft/VBoxLeft/GripY/SpinBox
@onready var grip_y_slider: HSlider = $UI/PanelLeft/VBoxLeft/GripY/HSlider
@onready var grip_z_spin: SpinBox = $UI/PanelLeft/VBoxLeft/GripZ/SpinBox
@onready var grip_z_slider: HSlider = $UI/PanelLeft/VBoxLeft/GripZ/HSlider
@onready var grip_preset_label: Label = $UI/PanelLeft/VBoxLeft/GripPresetLabel
@onready var lean_angle_spin: SpinBox = $UI/Panel/VBox/LeanAngle/SpinBox
@onready var lean_angle_slider: HSlider = $UI/Panel/VBox/LeanAngle/HSlider
@onready var lean_speed_spin: SpinBox = $UI/Panel/VBox/LeanSpeed/SpinBox
@onready var lean_speed_slider: HSlider = $UI/Panel/VBox/LeanSpeed/HSlider
@onready var camera: Camera3D = $Camera3D

# Preset value display (bone-local values for copying to .tres)
var _preset_label: Label = null

# Data
var character: GameCharacter
var characters: Array[CharacterPreset] = []
var weapons: Array[WeaponPreset] = []
var current_character_idx: int = -1
var current_weapon_idx: int = -1
var _environment_setup: Node = null
var _animation_library: AnimationLibrary = null
var _grip_node: Node3D = null  # 武器モデル内のLeftHandGripノード
var _lean_modifier_ref: LeanModifier = null  # リーン手動制御用

const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"

func _ready() -> void:
	_setup_environment()
	_animation_library = _load_animation_library()
	_load_data()
	_setup_ui()
	_setup_camera_buttons()
	_wrap_panels_in_scroll()

	# Set initial camera position (front view, closer)
	if camera:
		camera.set_distance(3.0)
		camera.set_yaw(0)  # Front view

	# Select first character if available
	if not characters.is_empty():
		_select_character(0)

	# Select first weapon if available
	if not weapons.is_empty():
		_select_weapon(0)


func _setup_environment() -> void:
	_environment_setup = EnvironmentSetup.new()
	_environment_setup.name = "EnvironmentSetup"
	if ResourceLoader.exists(DEFAULT_ENVIRONMENT_PRESET):
		var preset = load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
		if preset:
			_environment_setup.preset = preset
	add_child(_environment_setup)

func _process(delta: float) -> void:
	if character:
		var anim_ctrl = character.get_anim_controller()
		if anim_ctrl:
			# Look towards -Z (facing the camera at front view)
			anim_ctrl.update_animation(Vector3.ZERO, Vector3.BACK, false, delta)
		# リーンスライダーの値で手動オーバーライド（update_animation後に上書き）
		if _lean_modifier_ref:
			_lean_modifier_ref.recovery_speed = lean_speed_spin.value
			_lean_modifier_ref.set_target_lean(deg_to_rad(lean_angle_spin.value))

func _setup_scene(preset: CharacterPreset) -> void:
	if not preset:
		printerr("Failed to load character preset")
		return

	# Remove existing character if any
	if character:
		character.queue_free()
		character = null

	var model = preset.model_scene.instantiate()
	character = GameCharacter.new()
	character.name = "TestCharacter"
	add_child(character)

	model.name = "CharacterModel"
	character.add_child(model)

	# Setup AnimationPlayer (same pattern as CharacterRegistry)
	var anim_player = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		model.add_child(anim_player)

	# Apply shared animation library
	if _animation_library:
		print("[DEBUG] Animation library has %d animations: %s" % [_animation_library.get_animation_list().size(), str(_animation_library.get_animation_list())])
		if anim_player.has_animation_library(""):
			anim_player.remove_animation_library("")
		anim_player.add_animation_library("", _animation_library)
	else:
		print("[DEBUG] WARNING: _animation_library is null!")

	print("[DEBUG] AnimationPlayer has_animation('Rifle_Idle'): %s" % anim_player.has_animation("game_rifle_idle"))
	print("[DEBUG] AnimationPlayer animation list: %s" % str(anim_player.get_animation_list()))

	var anim_ctrl = CharacterAnimationController.new()
	character.add_child(anim_ctrl)
	character.set_anim_controller(anim_ctrl)
	anim_ctrl.setup(model, anim_player)

	# Debug: check AnimationTree state after setup
	var anim_tree = character.get_node_or_null("AnimationTree") as AnimationTree
	if anim_tree:
		print("[DEBUG] AnimationTree active: %s, anim_player path: %s" % [anim_tree.active, anim_tree.anim_player])
		# Check blend parameters
		for param in ["parameters/IdleBlend/blend_amount", "parameters/SpeedBlend/blend_amount", "parameters/TimeScale/scale"]:
			print("[DEBUG] %s = %s" % [param, anim_tree.get(param)])
		# Check if Idle animation node is valid
		var tree_root = anim_tree.tree_root as AnimationNodeBlendTree
		if tree_root:
			var idle_node = tree_root.get_node("Idle") as AnimationNodeAnimation
			if idle_node:
				print("[DEBUG] Idle node animation: '%s'" % idle_node.animation)
			var walk_node = tree_root.get_node("WalkBlend")
			print("[DEBUG] WalkBlend node: %s" % (walk_node != null))
		# Try direct AnimationPlayer play
		print("[DEBUG] Trying direct anim_player.play('Rifle_Idle')...")
		anim_player.play("game_rifle_idle")
	else:
		print("[DEBUG] WARNING: AnimationTree not found!")
	character.set_muzzle_flash_preview(muzzle_preview_toggle.button_pressed)

	character.position = Vector3(0, 0, 0)

	# LeanModifier参照を取得
	_lean_modifier_ref = null
	var skel := _find_skeleton(model)
	if skel:
		for child in skel.get_children():
			if child is LeanModifier:
				_lean_modifier_ref = child
				break

	# アニメーション適用後にSkeleton3Dオフセットを補正
	await get_tree().process_frame
	var skeleton := _find_skeleton(model)
	if skeleton:
		model.position.y = -skeleton.position.y
		print("[DEBUG-FLOAT] Skeleton offset compensated: model.y = %s" % model.position.y)


## Load shared animation library from GLB file
func _load_animation_library() -> AnimationLibrary:
	const ANIMATION_SOURCE := "res://assets/animations/character_anims_kubold.glb"
	if not ResourceLoader.exists(ANIMATION_SOURCE):
		printerr("Animation source not found: %s" % ANIMATION_SOURCE)
		return null

	var anim_scene = load(ANIMATION_SOURCE) as PackedScene
	if not anim_scene:
		printerr("Could not load animation source")
		return null

	var anim_instance = anim_scene.instantiate()
	var source_player = _find_animation_player(anim_instance)
	var lib: AnimationLibrary = null
	if source_player:
		lib = source_player.get_animation_library("")
	anim_instance.queue_free()
	return lib

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null

func _load_data() -> void:
	# Load character presets from directory
	var char_dir = DirAccess.open("res://data/characters/")
	if char_dir:
		char_dir.list_dir_begin()
		var file_name = char_dir.get_next()
		while file_name != "":
			if not char_dir.current_is_dir() and file_name.ends_with(".tres"):
				var path = "res://data/characters/" + file_name
				var c = load(path) as CharacterPreset
				if c:
					characters.append(c)
			file_name = char_dir.get_next()
		char_dir.list_dir_end()

	# Load weapon presets
	var weapon_paths = [
		"res://data/weapons/ak47.tres",
		"res://data/weapons/glock.tres",
		"res://data/weapons/mark18.tres",
	]

	for path in weapon_paths:
		if ResourceLoader.exists(path):
			var w = load(path) as WeaponPreset
			if w:
				weapons.append(w)

func _setup_ui() -> void:
	# Setup character dropdown
	character_option.clear()
	for c in characters:
		character_option.add_item(c.display_name)
	character_option.item_selected.connect(_select_character)

	# Setup weapon dropdown
	weapon_option.clear()
	for w in weapons:
		weapon_option.add_item(w.display_name)
	weapon_option.item_selected.connect(_select_weapon)
	fire_button.pressed.connect(_on_fire_pressed)
	
	# Connect signals for Position
	pos_x_slider.value_changed.connect(func(v): pos_x_spin.value = v; _update_transform())
	pos_x_spin.value_changed.connect(func(v): pos_x_slider.value = v; _update_transform())
	pos_y_slider.value_changed.connect(func(v): pos_y_spin.value = v; _update_transform())
	pos_y_spin.value_changed.connect(func(v): pos_y_slider.value = v; _update_transform())
	pos_z_slider.value_changed.connect(func(v): pos_z_spin.value = v; _update_transform())
	pos_z_spin.value_changed.connect(func(v): pos_z_slider.value = v; _update_transform())

	# Connect signals for Rotation
	rot_x_slider.value_changed.connect(func(v): rot_x_spin.value = v; _update_transform())
	rot_x_spin.value_changed.connect(func(v): rot_x_slider.value = v; _update_transform())
	rot_y_slider.value_changed.connect(func(v): rot_y_spin.value = v; _update_transform())
	rot_y_spin.value_changed.connect(func(v): rot_y_slider.value = v; _update_transform())
	rot_z_slider.value_changed.connect(func(v): rot_z_spin.value = v; _update_transform())
	rot_z_spin.value_changed.connect(func(v): rot_z_slider.value = v; _update_transform())

	# Connect signals for Muzzle Flash
	muzzle_pos_x_slider.value_changed.connect(func(v): muzzle_pos_x_spin.value = v; _update_muzzle_flash())
	muzzle_pos_x_spin.value_changed.connect(func(v): muzzle_pos_x_slider.value = v; _update_muzzle_flash())
	muzzle_pos_y_slider.value_changed.connect(func(v): muzzle_pos_y_spin.value = v; _update_muzzle_flash())
	muzzle_pos_y_spin.value_changed.connect(func(v): muzzle_pos_y_slider.value = v; _update_muzzle_flash())
	muzzle_pos_z_slider.value_changed.connect(func(v): muzzle_pos_z_spin.value = v; _update_muzzle_flash())
	muzzle_pos_z_spin.value_changed.connect(func(v): muzzle_pos_z_slider.value = v; _update_muzzle_flash())
	muzzle_scale_slider.value_changed.connect(func(v): muzzle_scale_spin.value = v; _update_muzzle_flash())
	muzzle_scale_spin.value_changed.connect(func(v): muzzle_scale_slider.value = v; _update_muzzle_flash())
	muzzle_rot_x_slider.value_changed.connect(func(v): muzzle_rot_x_spin.value = v; _update_muzzle_flash())
	muzzle_rot_x_spin.value_changed.connect(func(v): muzzle_rot_x_slider.value = v; _update_muzzle_flash())
	muzzle_rot_y_slider.value_changed.connect(func(v): muzzle_rot_y_spin.value = v; _update_muzzle_flash())
	muzzle_rot_y_spin.value_changed.connect(func(v): muzzle_rot_y_slider.value = v; _update_muzzle_flash())
	muzzle_rot_z_slider.value_changed.connect(func(v): muzzle_rot_z_spin.value = v; _update_muzzle_flash())
	muzzle_rot_z_spin.value_changed.connect(func(v): muzzle_rot_z_slider.value = v; _update_muzzle_flash())
	quad1_x_slider.value_changed.connect(func(v): quad1_x_spin.value = v; _update_quad1_x())
	quad1_x_spin.value_changed.connect(func(v): quad1_x_slider.value = v; _update_quad1_x())
	quad1_z_slider.value_changed.connect(func(v): quad1_z_spin.value = v; _update_quad1_z())
	quad1_z_spin.value_changed.connect(func(v): quad1_z_slider.value = v; _update_quad1_z())
	muzzle_preview_toggle.toggled.connect(_on_muzzle_preview_toggled)

	# Connect signals for Left Hand Grip
	grip_x_slider.value_changed.connect(func(v): grip_x_spin.value = v; _update_grip_position())
	grip_x_spin.value_changed.connect(func(v): grip_x_slider.value = v; _update_grip_position())
	grip_y_slider.value_changed.connect(func(v): grip_y_spin.value = v; _update_grip_position())
	grip_y_spin.value_changed.connect(func(v): grip_y_slider.value = v; _update_grip_position())
	grip_z_slider.value_changed.connect(func(v): grip_z_spin.value = v; _update_grip_position())
	grip_z_spin.value_changed.connect(func(v): grip_z_slider.value = v; _update_grip_position())
	grip_toggle.toggled.connect(_on_grip_toggle)

	# Connect signals for Lean
	lean_angle_slider.value_changed.connect(func(v): lean_angle_spin.value = v)
	lean_angle_spin.value_changed.connect(func(v): lean_angle_slider.value = v)
	lean_speed_slider.value_changed.connect(func(v): lean_speed_spin.value = v)
	lean_speed_spin.value_changed.connect(func(v): lean_speed_slider.value = v)

func _select_character(idx: int) -> void:
	if idx < 0 or idx >= characters.size():
		return

	current_character_idx = idx
	var preset = characters[idx]

	_setup_scene(preset)

	# Re-equip current weapon if any
	if current_weapon_idx >= 0 and current_weapon_idx < weapons.size():
		_select_weapon(current_weapon_idx)


func _select_weapon(idx: int) -> void:
	if idx < 0 or idx >= weapons.size():
		return

	current_weapon_idx = idx
	var weapon = weapons[idx]

	# Equip weapon (sets animation controller weapon type internally)
	if character:
		character.equip_weapon(weapon)

		# Force immediate animation update to switch to appropriate idle pose
		var anim_ctrl = character.get_anim_controller()
		if anim_ctrl:
			anim_ctrl.update_animation(Vector3.ZERO, Vector3.BACK, false, 0.0)

	_set_ui_values(weapon.attach_offset, weapon.attach_rotation)
	_set_muzzle_ui_values(weapon.muzzle_flash_offset, weapon.muzzle_flash_scale, weapon.muzzle_flash_rotation)
	_setup_grip_ui(weapon)
	if character:
		character.update_muzzle_flash_preview()

func _set_ui_values(pos: Vector3, rot_bone_local: Vector3) -> void:
	pos_x_spin.set_value_no_signal(pos.x)
	pos_x_slider.set_value_no_signal(pos.x)
	pos_y_spin.set_value_no_signal(pos.y)
	pos_y_slider.set_value_no_signal(pos.y)
	pos_z_spin.set_value_no_signal(pos.z)
	pos_z_slider.set_value_no_signal(pos.z)

	# Convert bone-local rotation to model space for intuitive display
	var rot_model := _bone_local_to_model_space(rot_bone_local)
	rot_x_spin.set_value_no_signal(rot_model.x)
	rot_x_slider.set_value_no_signal(rot_model.x)
	rot_y_spin.set_value_no_signal(rot_model.y)
	rot_y_slider.set_value_no_signal(rot_model.y)
	rot_z_spin.set_value_no_signal(rot_model.z)
	rot_z_slider.set_value_no_signal(rot_model.z)

	_update_preset_display()


func _set_muzzle_ui_values(pos: Vector3, muzzle_scale: float, rot: Vector3) -> void:
	muzzle_pos_x_spin.set_value_no_signal(pos.x)
	muzzle_pos_x_slider.set_value_no_signal(pos.x)
	muzzle_pos_y_spin.set_value_no_signal(pos.y)
	muzzle_pos_y_slider.set_value_no_signal(pos.y)
	muzzle_pos_z_spin.set_value_no_signal(pos.z)
	muzzle_pos_z_slider.set_value_no_signal(pos.z)
	muzzle_scale_spin.set_value_no_signal(muzzle_scale)
	muzzle_scale_slider.set_value_no_signal(muzzle_scale)
	muzzle_rot_x_spin.set_value_no_signal(rot.x)
	muzzle_rot_x_slider.set_value_no_signal(rot.x)
	muzzle_rot_y_spin.set_value_no_signal(rot.y)
	muzzle_rot_y_slider.set_value_no_signal(rot.y)
	muzzle_rot_z_spin.set_value_no_signal(rot.z)
	muzzle_rot_z_slider.set_value_no_signal(rot.z)

func _update_transform() -> void:
	if not character:
		return

	var socket = character.get_weapon_socket()
	if not socket:
		return

	socket.position = Vector3(pos_x_spin.value, pos_y_spin.value, pos_z_spin.value)

	# UI values are in model space (intuitive: X=pitch, Y=yaw, Z=roll)
	# Use ZYX Euler order so gimbal lock occurs at Y=±90° (not X=±90°)
	# Weapons typically have large X rotation (~-90°) but moderate Y, so ZYX avoids the singularity
	var rot_rad := Vector3(
		deg_to_rad(rot_x_spin.value),
		deg_to_rad(rot_y_spin.value),
		deg_to_rad(rot_z_spin.value)
	)
	var model_space_basis := Basis.from_euler(rot_rad, EULER_ORDER_ZYX)

	var bone_attachment := socket.get_parent() as Node3D
	var model := character.find_child("CharacterModel") as Node3D
	if bone_attachment and model:
		socket.basis = bone_attachment.global_transform.basis.inverse() * model.global_transform.basis * model_space_basis
	else:
		socket.rotation_degrees = Vector3(rot_x_spin.value, rot_y_spin.value, rot_z_spin.value)

	_update_preset_display()

func _update_muzzle_flash() -> void:
	var weapon = _get_current_weapon()
	if not weapon:
		return
	weapon.muzzle_flash_offset = _get_muzzle_offset()
	weapon.muzzle_flash_scale = _get_muzzle_scale()
	weapon.muzzle_flash_rotation = _get_muzzle_rotation()
	if character:
		character.update_muzzle_flash_preview()


func _get_current_weapon() -> WeaponPreset:
	if current_weapon_idx < 0 or current_weapon_idx >= weapons.size():
		return null
	return weapons[current_weapon_idx]


func _get_attach_offset() -> Vector3:
	return Vector3(pos_x_spin.value, pos_y_spin.value, pos_z_spin.value)


func _get_attach_rotation() -> Vector3:
	return Vector3(rot_x_spin.value, rot_y_spin.value, rot_z_spin.value)


func _get_muzzle_offset() -> Vector3:
	return Vector3(muzzle_pos_x_spin.value, muzzle_pos_y_spin.value, muzzle_pos_z_spin.value)


func _get_muzzle_scale() -> float:
	return muzzle_scale_spin.value


func _get_muzzle_rotation() -> Vector3:
	return Vector3(muzzle_rot_x_spin.value, muzzle_rot_y_spin.value, muzzle_rot_z_spin.value)


func _on_fire_pressed() -> void:
	if not character:
		return
	var anim_ctrl = character.get_anim_controller()
	if anim_ctrl:
		anim_ctrl.fire()


func _on_muzzle_preview_toggled(enabled: bool) -> void:
	if character:
		character.set_muzzle_flash_preview(enabled)


func _update_quad1_x() -> void:
	if character:
		character.set_muzzle_flash_quad1_x(quad1_x_spin.value)


func _update_quad1_z() -> void:
	if character:
		character.set_muzzle_flash_quad1_z(quad1_z_spin.value)


## Setup camera position buttons (created dynamically)
func _setup_camera_buttons() -> void:
	var vbox = $UI/Panel/VBox

	# Preset value display (bone-local values for .tres)
	var preset_sep = HSeparator.new()
	vbox.add_child(preset_sep)
	_preset_label = Label.new()
	_preset_label.text = "Preset: -"
	_preset_label.add_theme_font_size_override("font_size", 9)
	_preset_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_preset_label)

	# Add separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Add label
	var label = Label.new()
	label.text = "Camera Position"
	vbox.add_child(label)

	# Add button container
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	# Create buttons
	var btn_front = Button.new()
	btn_front.text = "Front"
	btn_front.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_front.pressed.connect(func(): _set_camera_yaw(0))
	hbox.add_child(btn_front)

	var btn_left = Button.new()
	btn_left.text = "Left"
	btn_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_left.pressed.connect(func(): _set_camera_yaw(-PI / 2))
	hbox.add_child(btn_left)

	var btn_right = Button.new()
	btn_right.text = "Right"
	btn_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_right.pressed.connect(func(): _set_camera_yaw(PI / 2))
	hbox.add_child(btn_right)

	var btn_back = Button.new()
	btn_back.text = "Back"
	btn_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_back.pressed.connect(func(): _set_camera_yaw(PI))
	hbox.add_child(btn_back)


func _set_camera_yaw(yaw: float) -> void:
	if camera:
		camera.set_yaw(yaw)


## Convert bone-local rotation (degrees) to model-space ZYX Euler (degrees)
func _bone_local_to_model_space(rot_bone_deg: Vector3) -> Vector3:
	if not character:
		return rot_bone_deg
	var socket := character.get_weapon_socket()
	if not socket:
		return rot_bone_deg
	var bone_attachment := socket.get_parent() as Node3D
	var model := character.find_child("CharacterModel") as Node3D
	if not bone_attachment or not model:
		return rot_bone_deg

	# Preset stores bone-local Euler (default YXZ order)
	var bone_local_basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_bone_deg.x), deg_to_rad(rot_bone_deg.y), deg_to_rad(rot_bone_deg.z)
	))
	# Convert to model space: desired = model_inv * bone_global * bone_local
	var model_space_basis := model.global_transform.basis.inverse() * bone_attachment.global_transform.basis * bone_local_basis
	# Decompose as ZYX (matching the composition order in _update_transform)
	var euler := model_space_basis.get_euler(EULER_ORDER_ZYX)
	return Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))


## Get current bone-local rotation (for preset) from the socket
func _get_current_bone_local_rotation() -> Vector3:
	if not character:
		return Vector3.ZERO
	var socket := character.get_weapon_socket()
	if not socket:
		return Vector3.ZERO
	var euler := socket.basis.get_euler()
	return Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))


## Update preset value display label
func _update_preset_display() -> void:
	if not _preset_label:
		return
	var pos := Vector3(pos_x_spin.value, pos_y_spin.value, pos_z_spin.value)
	var rot := _get_current_bone_local_rotation()
	_preset_label.text = "Preset: offset=(%s, %s, %s) rotation=(%s, %s, %s)" % [
		snapped(pos.x, 0.001), snapped(pos.y, 0.001), snapped(pos.z, 0.001),
		snapped(rot.x, 0.01), snapped(rot.y, 0.01), snapped(rot.z, 0.01),
	]


# ============================================
# Left Hand Grip
# ============================================

## 武器切替時にグリップUI初期化
func _setup_grip_ui(weapon: WeaponPreset) -> void:
	_grip_node = null
	if character and character._weapon_model:
		_grip_node = character._weapon_model.get_node_or_null(GameConstants.NODE_LEFT_HAND_GRIP) as Node3D

	if _grip_node and weapon.left_hand_grip_enabled:
		grip_toggle.set_pressed_no_signal(true)
		# Read from grip node (already applied by game_character.equip_weapon)
		var pos := _grip_node.position
		grip_x_spin.set_value_no_signal(pos.x)
		grip_x_slider.set_value_no_signal(pos.x)
		grip_y_spin.set_value_no_signal(pos.y)
		grip_y_slider.set_value_no_signal(pos.y)
		grip_z_spin.set_value_no_signal(pos.z)
		grip_z_slider.set_value_no_signal(pos.z)
	else:
		grip_toggle.set_pressed_no_signal(false)
		grip_x_spin.set_value_no_signal(0)
		grip_x_slider.set_value_no_signal(0)
		grip_y_spin.set_value_no_signal(0)
		grip_y_slider.set_value_no_signal(0)
		grip_z_spin.set_value_no_signal(0)
		grip_z_slider.set_value_no_signal(0)

	_update_grip_preset_display()


## グリップ位置スライダー変更時
func _update_grip_position() -> void:
	if not _grip_node:
		return
	_grip_node.position = Vector3(grip_x_spin.value, grip_y_spin.value, grip_z_spin.value)
	_update_grip_preset_display()


## グリップIK有効/無効トグル
func _on_grip_toggle(enabled: bool) -> void:
	if not character:
		return
	var anim_ctrl := character.get_anim_controller()
	if not anim_ctrl:
		return
	if enabled and _grip_node:
		anim_ctrl.set_left_hand_grip(_grip_node)
	else:
		anim_ctrl.set_left_hand_grip(null)


## グリップ位置のプリセット表示更新
func _update_grip_preset_display() -> void:
	if not grip_preset_label:
		return
	if _grip_node:
		var pos := _grip_node.position
		grip_preset_label.text = "Grip: (%s, %s, %s)" % [
			snapped(pos.x, 0.001), snapped(pos.y, 0.001), snapped(pos.z, 0.001),
		]
	else:
		grip_preset_label.text = "Grip: (no LeftHandGrip node)"


func _debug_print_tree_positions(node: Node, depth: int) -> void:
	if node is Node3D:
		var n3d := node as Node3D
		var info := "  ".repeat(depth) + "%s (%s) pos=%s" % [n3d.name, n3d.get_class(), n3d.position]
		if n3d is Skeleton3D:
			var skel := n3d as Skeleton3D
			var hips_idx := skel.find_bone("Hips")
			if hips_idx >= 0:
				var hips_pose := skel.get_bone_global_pose(hips_idx)
				info += " | Hips_global_y=%.4f" % hips_pose.origin.y
		if n3d is MeshInstance3D:
			var mi := n3d as MeshInstance3D
			var aabb := mi.get_aabb()
			info += " | AABB_min_y=%.4f max_y=%.4f" % [aabb.position.y, aabb.position.y + aabb.size.y]
		print("[DEBUG-FLOAT] %s" % info)
	for child in node.get_children():
		if depth < 3:
			_debug_print_tree_positions(child, depth + 1)


## 両パネルをScrollContainerで包んでスクロール可能にする
func _wrap_panels_in_scroll() -> void:
	for panel: PanelContainer in [$UI/PanelLeft, $UI/Panel]:
		var vbox := panel.get_child(0)
		panel.remove_child(vbox)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroll)
		scroll.add_child(vbox)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null
