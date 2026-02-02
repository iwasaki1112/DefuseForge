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

const GameCharacterScript = preload("res://scripts/characters/game_character.gd")
const CharacterPresetScript = preload("res://scripts/resources/character_preset.gd")
const WeaponPresetScript = preload("res://scripts/resources/weapon_preset.gd")
const CharacterAnimationControllerScript = preload("res://scripts/animation/character_animation_controller.gd")

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
@onready var camera: Camera3D = $Camera3D

# Data
var character: GameCharacter
var characters: Array[CharacterPresetScript] = []
var weapons: Array[WeaponPresetScript] = []
var current_character_idx: int = -1
var current_weapon_idx: int = -1
var _environment_setup: Node = null
var _animation_library: AnimationLibrary = null

const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"

func _ready() -> void:
	_setup_environment()
	_animation_library = _load_animation_library()
	_load_data()
	_setup_ui()
	_setup_camera_buttons()

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

func _setup_scene(preset: CharacterPresetScript) -> void:
	if not preset:
		printerr("Failed to load character preset")
		return

	# Remove existing character if any
	if character:
		character.queue_free()
		character = null

	var model = preset.model_scene.instantiate()
	character = GameCharacterScript.new()
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
		if anim_player.has_animation_library(""):
			anim_player.remove_animation_library("")
		anim_player.add_animation_library("", _animation_library)

	var anim_ctrl = CharacterAnimationControllerScript.new()
	character.add_child(anim_ctrl)
	character.set_anim_controller(anim_ctrl)
	anim_ctrl.setup(model, anim_player)
	character.set_muzzle_flash_preview(muzzle_preview_toggle.button_pressed)

	character.position = Vector3(0, 0, 0)


## Load shared animation library from GLB file
func _load_animation_library() -> AnimationLibrary:
	const ANIMATION_SOURCE := "res://assets/animations/character_anims.glb"
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
				var c = load(path) as CharacterPresetScript
				if c:
					characters.append(c)
			file_name = char_dir.get_next()
		char_dir.list_dir_end()

	# Load weapon presets
	var weapon_paths = [
		"res://data/weapons/ak47.tres",
		"res://data/weapons/glock.tres"
	]

	for path in weapon_paths:
		if ResourceLoader.exists(path):
			var w = load(path) as WeaponPresetScript
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
	if character:
		character.update_muzzle_flash_preview()

func _set_ui_values(pos: Vector3, rot: Vector3) -> void:
	pos_x_spin.set_value_no_signal(pos.x)
	pos_x_slider.set_value_no_signal(pos.x)
	pos_y_spin.set_value_no_signal(pos.y)
	pos_y_slider.set_value_no_signal(pos.y)
	pos_z_spin.set_value_no_signal(pos.z)
	pos_z_slider.set_value_no_signal(pos.z)
	
	rot_x_spin.set_value_no_signal(rot.x)
	rot_x_slider.set_value_no_signal(rot.x)
	rot_y_spin.set_value_no_signal(rot.y)
	rot_y_slider.set_value_no_signal(rot.y)
	rot_z_spin.set_value_no_signal(rot.z)
	rot_z_slider.set_value_no_signal(rot.z)


func _set_muzzle_ui_values(pos: Vector3, scale: float, rot: Vector3) -> void:
	muzzle_pos_x_spin.set_value_no_signal(pos.x)
	muzzle_pos_x_slider.set_value_no_signal(pos.x)
	muzzle_pos_y_spin.set_value_no_signal(pos.y)
	muzzle_pos_y_slider.set_value_no_signal(pos.y)
	muzzle_pos_z_spin.set_value_no_signal(pos.z)
	muzzle_pos_z_slider.set_value_no_signal(pos.z)
	muzzle_scale_spin.set_value_no_signal(scale)
	muzzle_scale_slider.set_value_no_signal(scale)
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
		
	var pos = Vector3(pos_x_spin.value, pos_y_spin.value, pos_z_spin.value)
	var rot = Vector3(rot_x_spin.value, rot_y_spin.value, rot_z_spin.value)
	
	socket.position = pos
	socket.rotation_degrees = rot

func _update_muzzle_flash() -> void:
	var weapon = _get_current_weapon()
	if not weapon:
		return
	weapon.muzzle_flash_offset = _get_muzzle_offset()
	weapon.muzzle_flash_scale = _get_muzzle_scale()
	weapon.muzzle_flash_rotation = _get_muzzle_rotation()
	if character:
		character.update_muzzle_flash_preview()


func _get_current_weapon() -> WeaponPresetScript:
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
