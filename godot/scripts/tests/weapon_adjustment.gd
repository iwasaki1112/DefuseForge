extends Node3D

const GameCharacterScript = preload("res://scripts/characters/game_character.gd")
const CharacterPresetScript = preload("res://scripts/resources/character_preset.gd")
const WeaponPresetScript = preload("res://scripts/resources/weapon_preset.gd")
const CharacterAnimationController = preload("res://scripts/animation/character_animation_controller.gd")

# UI References
@onready var weapon_option: OptionButton = $UI/Panel/VBox/WeaponOption
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

@onready var copy_button: Button = $UI/Panel/VBox/CopyButton
@onready var output_text: TextEdit = $UI/Panel/VBox/OutputText
@onready var camera: Camera3D = $Camera3D

# Data
var character: GameCharacter
var weapons: Array[WeaponPresetScript] = []
var current_weapon_idx: int = -1
var _environment_setup: Node = null

const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"

func _ready() -> void:
	_setup_environment()
	_setup_scene()
	_load_data()
	_setup_ui()
	_setup_camera_buttons()

	# Set initial camera position (front view, closer)
	if camera:
		camera.set_distance(3.0)
		camera.set_yaw(0)  # Front view

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

func _setup_scene() -> void:
	# Load Dummy CT Character
	var preset_path = "res://data/characters/dummy_ct.tres"
	var preset = load(preset_path) as CharacterPresetScript
	if not preset:
		printerr("Failed to load character preset")
		return

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

	# Load shared animation library
	var anim_lib = _load_animation_library()
	if anim_lib:
		if anim_player.has_animation_library(""):
			anim_player.remove_animation_library("")
		anim_player.add_animation_library("", anim_lib)

	var anim_ctrl = CharacterAnimationController.new()
	character.add_child(anim_ctrl)
	character.set_anim_controller(anim_ctrl)
	anim_ctrl.setup(model, anim_player)

	character.position = Vector3(0, 0, 0)

	# Initial pose - weapon type will be set by _select_weapon via equip_weapon
	anim_ctrl.set_stance(CharacterAnimationController.Stance.STAND)


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
	weapon_option.clear()
	for w in weapons:
		weapon_option.add_item(w.display_name)
	
	weapon_option.item_selected.connect(_select_weapon)
	
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
	
	copy_button.pressed.connect(_copy_values)

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
	
	_update_text(pos, rot)

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
	
	_update_text(pos, rot)

func _update_text(pos: Vector3, rot: Vector3) -> void:
	var text = "attach_offset = Vector3(%.3f, %.3f, %.3f)\n" % [pos.x, pos.y, pos.z]
	text += "attach_rotation = Vector3(%.3f, %.3f, %.3f)" % [rot.x, rot.y, rot.z]
	output_text.text = text

func _copy_values() -> void:
	DisplayServer.clipboard_set(output_text.text)


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
