extends Node3D
## Animation viewer - simple animation testing for character models
## Uses the new simplified CharacterBase API

const CharacterAPIScript = preload("res://scripts/api/character_api.gd")

@onready var camera: Camera3D = $OrbitCamera
@onready var character_body: CharacterBase = $CharacterBody
@onready var canvas_layer: CanvasLayer = $CanvasLayer

var _animations: Array[String] = []
const GRAVITY: float = 9.8
const DEFAULT_BLEND_TIME: float = 0.3
var blend_time: float = DEFAULT_BLEND_TIME
var blend_time_label: Label = null

# UI Panels
var left_panel: PanelContainer = null
var right_panel: PanelContainer = null
var bottom_panel: PanelContainer = null

# Character selection
const CHARACTERS_DIR: String = "res://assets/characters/"
var available_characters: Array[String] = []
var current_character_id: String = "vanguard"

# Animation sharing is now handled by CharacterAPIScript.ANIMATION_SOURCE
var character_model: Node3D = null
var character_option_button: OptionButton = null

# Upper body rotation
var upper_body_rotation: float = 0.0
var upper_body_rotation_label: Label = null
const UPPER_BODY_ROTATION_MIN: float = -45.0
const UPPER_BODY_ROTATION_MAX: float = 45.0

# Elbow pole adjustment
var elbow_pole_x: float = 0.3
var elbow_pole_y: float = -0.3
var elbow_pole_z: float = 0.0
var elbow_pole_x_label: Label = null
var elbow_pole_y_label: Label = null
var elbow_pole_z_label: Label = null

# Left hand position adjustment
var left_hand_x: float = 0.0
var left_hand_y: float = 0.0
var left_hand_z: float = 0.0
var left_hand_x_label: Label = null
var left_hand_y_label: Label = null
var left_hand_z_label: Label = null

# Weapon selection
const WEAPONS_DIR: String = "res://assets/weapons/"
var available_weapons: Array[String] = []
var current_weapon_id: String = "ak47"
var weapon_resource: WeaponResource = null
var weapon_option_button: OptionButton = null

# Character resource for IK offset
var character_resource: CharacterResource = null

# Shooting
var is_shooting: bool = false


func _weapon_id_string_to_int(weapon_id: String) -> int:
	match weapon_id.to_lower():
		"ak47":
			return WeaponRegistry.WeaponId.AK47
		"m4a1":
			return WeaponRegistry.WeaponId.M4A1
		_:
			return WeaponRegistry.WeaponId.NONE


func _ready() -> void:
	# Remove old UI
	var old_panel = canvas_layer.get_node_or_null("Panel")
	if old_panel:
		old_panel.queue_free()

	# Create UI layout
	_create_ui_layout()

	# Get reference to character model
	character_model = character_body.get_node_or_null("CharacterModel")

	# Scan available characters and weapons
	_scan_available_characters()
	_scan_available_weapons()
	_load_weapon_resource()
	_load_character_resource(current_character_id)

	# Wait for CharacterBase to setup
	await get_tree().process_frame

	# Equip weapon
	character_body.set_weapon(_weapon_id_string_to_int(current_weapon_id))

	# Apply character IK offset
	_apply_character_ik_offset()

	# Apply loaded IK values after weapon is equipped
	await get_tree().process_frame
	_update_elbow_pole()
	_update_left_hand_position()

	# Collect animations
	_collect_animations()

	# Populate UI
	_populate_ui()

	# Setup camera
	if camera.has_method("set_target") and character_body:
		camera.set_target(character_body)

	# Play idle animation
	if _animations.size() > 0:
		_play_animation(_animations[0])


func _scan_available_characters() -> void:
	available_characters.clear()
	var dir = DirAccess.open(CHARACTERS_DIR)
	if dir == null:
		push_warning("[AnimViewer] Cannot open characters directory: %s" % CHARACTERS_DIR)
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var glb_path = CHARACTERS_DIR + folder_name + "/" + folder_name + ".glb"
			var fbx_path = CHARACTERS_DIR + folder_name + "/" + folder_name + ".fbx"
			if ResourceLoader.exists(glb_path) or ResourceLoader.exists(fbx_path):
				available_characters.append(folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()
	available_characters.sort()


func _scan_available_weapons() -> void:
	available_weapons.clear()
	var dir = DirAccess.open(WEAPONS_DIR)
	if dir == null:
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var tres_path = WEAPONS_DIR + folder_name + "/" + folder_name + ".tres"
			if ResourceLoader.exists(tres_path):
				available_weapons.append(folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()
	available_weapons.sort()


func _load_weapon_resource() -> void:
	var resource_path = WEAPONS_DIR + current_weapon_id + "/" + current_weapon_id + ".tres"
	if ResourceLoader.exists(resource_path):
		weapon_resource = load(resource_path) as WeaponResource
		# Load elbow pole values from weapon resource
		if weapon_resource:
			elbow_pole_x = weapon_resource.left_elbow_pole_x
			elbow_pole_y = weapon_resource.left_elbow_pole_y
			elbow_pole_z = weapon_resource.left_elbow_pole_z
			left_hand_x = weapon_resource.left_hand_ik_position.x
			left_hand_y = weapon_resource.left_hand_ik_position.y
			left_hand_z = weapon_resource.left_hand_ik_position.z


func _create_ui_layout() -> void:
	# Left panel - Character/Weapon selection
	left_panel = PanelContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_panel.offset_right = 200
	left_panel.offset_bottom = 420
	left_panel.offset_left = 10
	left_panel.offset_top = 10
	canvas_layer.add_child(left_panel)

	var left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	# Right panel - Animation list
	right_panel = PanelContainer.new()
	right_panel.name = "RightPanel"
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -200
	right_panel.offset_right = -10
	right_panel.offset_top = 10
	right_panel.offset_bottom = -10
	canvas_layer.add_child(right_panel)

	var right_scroll = ScrollContainer.new()
	right_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_panel.add_child(right_scroll)

	var right_vbox = VBoxContainer.new()
	right_vbox.name = "AnimationList"
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 4)
	right_scroll.add_child(right_vbox)

	# Bottom panel - Controls
	bottom_panel = PanelContainer.new()
	bottom_panel.name = "BottomPanel"
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 10
	bottom_panel.offset_right = -220
	bottom_panel.offset_top = -120
	bottom_panel.offset_bottom = -10
	canvas_layer.add_child(bottom_panel)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 20)
	bottom_panel.add_child(bottom_hbox)


func _populate_ui() -> void:
	_populate_left_panel()
	_populate_right_panel()
	_populate_bottom_panel()


func _populate_left_panel() -> void:
	var vbox = left_panel.get_child(0) as VBoxContainer
	if not vbox:
		return

	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "Animation Viewer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Character selection
	var char_label = Label.new()
	char_label.text = "Character"
	vbox.add_child(char_label)

	character_option_button = OptionButton.new()
	for i in range(available_characters.size()):
		var char_id = available_characters[i]
		character_option_button.add_item(char_id.capitalize(), i)
		if char_id == current_character_id:
			character_option_button.select(i)
	character_option_button.item_selected.connect(_on_character_selected)
	vbox.add_child(character_option_button)

	vbox.add_child(HSeparator.new())

	# Weapon selection
	var weapon_label = Label.new()
	weapon_label.text = "Weapon"
	vbox.add_child(weapon_label)

	weapon_option_button = OptionButton.new()
	for i in range(available_weapons.size()):
		var weapon_id = available_weapons[i]
		weapon_option_button.add_item(weapon_id.to_upper(), i)
		if weapon_id == current_weapon_id:
			weapon_option_button.select(i)
	weapon_option_button.item_selected.connect(_on_weapon_selected)
	vbox.add_child(weapon_option_button)

	vbox.add_child(HSeparator.new())

	# Playback controls
	var stop_btn = Button.new()
	stop_btn.text = "Stop"
	stop_btn.pressed.connect(_on_stop_pressed)
	vbox.add_child(stop_btn)

	var pause_btn = Button.new()
	pause_btn.text = "Pause/Resume"
	pause_btn.pressed.connect(_on_pause_pressed)
	vbox.add_child(pause_btn)

	vbox.add_child(HSeparator.new())

	# Camera view buttons
	var camera_label = Label.new()
	camera_label.text = "Camera View"
	vbox.add_child(camera_label)

	var camera_hbox1 = HBoxContainer.new()
	camera_hbox1.add_theme_constant_override("separation", 4)
	vbox.add_child(camera_hbox1)

	var front_btn = Button.new()
	front_btn.text = "Front"
	front_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	front_btn.pressed.connect(_on_camera_front)
	camera_hbox1.add_child(front_btn)

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(_on_camera_back)
	camera_hbox1.add_child(back_btn)

	var camera_hbox2 = HBoxContainer.new()
	camera_hbox2.add_theme_constant_override("separation", 4)
	vbox.add_child(camera_hbox2)

	var left_btn = Button.new()
	left_btn.text = "Left"
	left_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_btn.pressed.connect(_on_camera_left)
	camera_hbox2.add_child(left_btn)

	var right_btn = Button.new()
	right_btn.text = "Right"
	right_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_btn.pressed.connect(_on_camera_right)
	camera_hbox2.add_child(right_btn)

	var top_btn = Button.new()
	top_btn.text = "Top"
	top_btn.pressed.connect(_on_camera_top)
	vbox.add_child(top_btn)


func _populate_right_panel() -> void:
	var scroll = right_panel.get_child(0) as ScrollContainer
	if not scroll:
		return
	var vbox = scroll.get_node_or_null("AnimationList") as VBoxContainer
	if not vbox:
		return

	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "Animations"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Animation buttons
	for anim_name in _animations:
		var btn = Button.new()
		btn.text = anim_name
		btn.pressed.connect(_on_animation_button_pressed.bind(anim_name))
		vbox.add_child(btn)

	# Shooting controls
	vbox.add_child(HSeparator.new())

	var shoot_label = Label.new()
	shoot_label.text = "Shooting"
	shoot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(shoot_label)

	var shoot_btn = Button.new()
	shoot_btn.text = "Shoot (Single)"
	shoot_btn.pressed.connect(_on_shoot_pressed)
	vbox.add_child(shoot_btn)

	var auto_btn = Button.new()
	auto_btn.text = "Auto-Fire (Toggle)"
	auto_btn.pressed.connect(_on_auto_fire_pressed)
	vbox.add_child(auto_btn)


func _populate_bottom_panel() -> void:
	var hbox = bottom_panel.get_child(0) as HBoxContainer
	if not hbox:
		return

	for child in hbox.get_children():
		child.queue_free()

	# Playback section
	var left_section = VBoxContainer.new()
	left_section.add_theme_constant_override("separation", 4)
	hbox.add_child(left_section)

	var blend_label = Label.new()
	blend_label.text = "Blend Time"
	left_section.add_child(blend_label)

	blend_time_label = Label.new()
	blend_time_label.text = "%.2f sec" % blend_time
	left_section.add_child(blend_time_label)

	var blend_slider = HSlider.new()
	blend_slider.min_value = 0.0
	blend_slider.max_value = 1.0
	blend_slider.step = 0.05
	blend_slider.value = blend_time
	blend_slider.custom_minimum_size.x = 150
	blend_slider.value_changed.connect(_on_blend_time_changed)
	left_section.add_child(blend_slider)

	# Upper body rotation
	var rotation_section = VBoxContainer.new()
	rotation_section.add_theme_constant_override("separation", 4)
	hbox.add_child(rotation_section)

	var rotation_label = Label.new()
	rotation_label.text = "Upper Body Twist"
	rotation_section.add_child(rotation_label)

	upper_body_rotation_label = Label.new()
	upper_body_rotation_label.text = "%.0f deg" % upper_body_rotation
	rotation_section.add_child(upper_body_rotation_label)

	var rotation_slider = HSlider.new()
	rotation_slider.min_value = UPPER_BODY_ROTATION_MIN
	rotation_slider.max_value = UPPER_BODY_ROTATION_MAX
	rotation_slider.step = 1.0
	rotation_slider.value = upper_body_rotation
	rotation_slider.custom_minimum_size.x = 150
	rotation_slider.value_changed.connect(_on_upper_body_rotation_changed)
	rotation_section.add_child(rotation_slider)

	# Elbow Pole X
	var pole_x_section = VBoxContainer.new()
	pole_x_section.add_theme_constant_override("separation", 2)
	hbox.add_child(pole_x_section)

	var pole_x_title = Label.new()
	pole_x_title.text = "Elbow X"
	pole_x_section.add_child(pole_x_title)

	elbow_pole_x_label = Label.new()
	elbow_pole_x_label.text = "%.2f" % elbow_pole_x
	pole_x_section.add_child(elbow_pole_x_label)

	var pole_x_slider = HSlider.new()
	pole_x_slider.min_value = -20.0
	pole_x_slider.max_value = 20.0
	pole_x_slider.step = 0.5
	pole_x_slider.value = elbow_pole_x
	pole_x_slider.custom_minimum_size.x = 80
	pole_x_slider.value_changed.connect(_on_elbow_pole_x_changed)
	pole_x_section.add_child(pole_x_slider)

	# Elbow Pole Y
	var pole_y_section = VBoxContainer.new()
	pole_y_section.add_theme_constant_override("separation", 2)
	hbox.add_child(pole_y_section)

	var pole_y_title = Label.new()
	pole_y_title.text = "Elbow Y"
	pole_y_section.add_child(pole_y_title)

	elbow_pole_y_label = Label.new()
	elbow_pole_y_label.text = "%.2f" % elbow_pole_y
	pole_y_section.add_child(elbow_pole_y_label)

	var pole_y_slider = HSlider.new()
	pole_y_slider.min_value = -20.0
	pole_y_slider.max_value = 20.0
	pole_y_slider.step = 0.5
	pole_y_slider.value = elbow_pole_y
	pole_y_slider.custom_minimum_size.x = 80
	pole_y_slider.value_changed.connect(_on_elbow_pole_y_changed)
	pole_y_section.add_child(pole_y_slider)

	# Elbow Pole Z
	var pole_z_section = VBoxContainer.new()
	pole_z_section.add_theme_constant_override("separation", 2)
	hbox.add_child(pole_z_section)

	var pole_z_title = Label.new()
	pole_z_title.text = "Elbow Z"
	pole_z_section.add_child(pole_z_title)

	elbow_pole_z_label = Label.new()
	elbow_pole_z_label.text = "%.2f" % elbow_pole_z
	pole_z_section.add_child(elbow_pole_z_label)

	var pole_z_slider = HSlider.new()
	pole_z_slider.min_value = -20.0
	pole_z_slider.max_value = 20.0
	pole_z_slider.step = 0.5
	pole_z_slider.value = elbow_pole_z
	pole_z_slider.custom_minimum_size.x = 80
	pole_z_slider.value_changed.connect(_on_elbow_pole_z_changed)
	pole_z_section.add_child(pole_z_slider)

	# Separator
	var sep = VSeparator.new()
	hbox.add_child(sep)

	# Left Hand X
	var hand_x_section = VBoxContainer.new()
	hand_x_section.add_theme_constant_override("separation", 2)
	hbox.add_child(hand_x_section)

	var hand_x_title = Label.new()
	hand_x_title.text = "Hand X"
	hand_x_section.add_child(hand_x_title)

	left_hand_x_label = Label.new()
	left_hand_x_label.text = "%.2f" % left_hand_x
	hand_x_section.add_child(left_hand_x_label)

	var hand_x_slider = HSlider.new()
	hand_x_slider.min_value = -0.5
	hand_x_slider.max_value = 0.5
	hand_x_slider.step = 0.01
	hand_x_slider.value = left_hand_x
	hand_x_slider.custom_minimum_size.x = 80
	hand_x_slider.value_changed.connect(_on_left_hand_x_changed)
	hand_x_section.add_child(hand_x_slider)

	# Left Hand Y
	var hand_y_section = VBoxContainer.new()
	hand_y_section.add_theme_constant_override("separation", 2)
	hbox.add_child(hand_y_section)

	var hand_y_title = Label.new()
	hand_y_title.text = "Hand Y"
	hand_y_section.add_child(hand_y_title)

	left_hand_y_label = Label.new()
	left_hand_y_label.text = "%.2f" % left_hand_y
	hand_y_section.add_child(left_hand_y_label)

	var hand_y_slider = HSlider.new()
	hand_y_slider.min_value = -0.5
	hand_y_slider.max_value = 0.5
	hand_y_slider.step = 0.01
	hand_y_slider.value = left_hand_y
	hand_y_slider.custom_minimum_size.x = 80
	hand_y_slider.value_changed.connect(_on_left_hand_y_changed)
	hand_y_section.add_child(hand_y_slider)

	# Left Hand Z
	var hand_z_section = VBoxContainer.new()
	hand_z_section.add_theme_constant_override("separation", 2)
	hbox.add_child(hand_z_section)

	var hand_z_title = Label.new()
	hand_z_title.text = "Hand Z"
	hand_z_section.add_child(hand_z_title)

	left_hand_z_label = Label.new()
	left_hand_z_label.text = "%.2f" % left_hand_z
	hand_z_section.add_child(left_hand_z_label)

	var hand_z_slider = HSlider.new()
	hand_z_slider.min_value = -0.5
	hand_z_slider.max_value = 0.5
	hand_z_slider.step = 0.01
	hand_z_slider.value = left_hand_z
	hand_z_slider.custom_minimum_size.x = 80
	hand_z_slider.value_changed.connect(_on_left_hand_z_changed)
	hand_z_section.add_child(hand_z_slider)


## Collect animations using CharacterAPI
func _collect_animations() -> void:
	_animations.clear()
	_animations = CharacterAPIScript.get_available_animations(character_body, true)
	print("[AnimViewer] Collected %d animations via CharacterAPI" % _animations.size())


func _physics_process(delta: float) -> void:
	if character_body:
		if not character_body.is_on_floor():
			character_body.velocity.y -= GRAVITY * delta
		else:
			character_body.velocity.y = 0
		character_body.move_and_slide()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_shoot()
		elif event.keycode == KEY_L:
			_toggle_laser()


func _on_character_selected(index: int) -> void:
	if index < 0 or index >= available_characters.size():
		return
	_change_character(available_characters[index])


func _on_weapon_selected(index: int) -> void:
	if index < 0 or index >= available_weapons.size():
		return
	_change_weapon(available_weapons[index])


func _change_character(character_id: String) -> void:
	if character_id == current_character_id:
		return

	print("[AnimViewer] Changing character to: %s" % character_id)

	# Clear old references
	_animations.clear()

	# Update current character ID
	current_character_id = character_id

	# Use CharacterAPI to switch model (handles model swap, components, animations, weapon)
	var weapon_id := _weapon_id_string_to_int(current_weapon_id)
	CharacterAPIScript.switch_character_model(character_body, character_id, weapon_id)

	# Update model reference
	character_model = character_body.model

	# Load CharacterResource for UI display
	_load_character_resource(character_id)

	# Collect animations
	_collect_animations()

	# Refresh UI
	_populate_ui()

	# Apply IK values after everything is set up
	await get_tree().process_frame
	_update_elbow_pole()
	_update_left_hand_position()

	# Play first animation
	if _animations.size() > 0:
		_play_animation(_animations[0])


func _change_weapon(weapon_id: String) -> void:
	if weapon_id == current_weapon_id:
		return

	print("[AnimViewer] Changing weapon to: %s" % weapon_id)

	current_weapon_id = weapon_id
	_load_weapon_resource()

	# Equip weapon using new API
	character_body.set_weapon(_weapon_id_string_to_int(weapon_id))

	# Apply character IK offset
	_apply_character_ik_offset()

	# Apply loaded IK values after weapon is equipped
	await get_tree().process_frame
	_update_elbow_pole()
	_update_left_hand_position()
	_populate_ui()  # Refresh UI sliders


func _play_animation(anim_name: String) -> void:
	CharacterAPIScript.play_animation(character_body, anim_name, blend_time)
	print("[AnimViewer] Playing: %s" % anim_name)


func _on_animation_button_pressed(anim_name: String) -> void:
	_play_animation(anim_name)


func _on_stop_pressed() -> void:
	# Animation stop is handled via the play_animation API
	pass


func _on_pause_pressed() -> void:
	# TODO: implement pause/resume via animation component
	pass


func _on_blend_time_changed(value: float) -> void:
	blend_time = value
	if blend_time_label:
		blend_time_label.text = "%.2f sec" % blend_time


func _on_upper_body_rotation_changed(value: float) -> void:
	upper_body_rotation = value
	character_body.set_upper_body_rotation(value)
	if upper_body_rotation_label:
		upper_body_rotation_label.text = "%.0f deg" % upper_body_rotation


func _on_elbow_pole_x_changed(value: float) -> void:
	elbow_pole_x = value
	if elbow_pole_x_label:
		elbow_pole_x_label.text = "%.2f" % elbow_pole_x
	_update_elbow_pole()


func _on_elbow_pole_y_changed(value: float) -> void:
	elbow_pole_y = value
	if elbow_pole_y_label:
		elbow_pole_y_label.text = "%.2f" % elbow_pole_y
	_update_elbow_pole()


func _on_elbow_pole_z_changed(value: float) -> void:
	elbow_pole_z = value
	if elbow_pole_z_label:
		elbow_pole_z_label.text = "%.2f" % elbow_pole_z
	_update_elbow_pole()


func _update_elbow_pole() -> void:
	CharacterAPIScript.update_elbow_pole_position(character_body, elbow_pole_x, elbow_pole_y, elbow_pole_z)
	print("[AnimViewer] Elbow pole: (%.2f, %.2f, %.2f)" % [elbow_pole_x, elbow_pole_y, elbow_pole_z])


func _on_left_hand_x_changed(value: float) -> void:
	left_hand_x = value
	if left_hand_x_label:
		left_hand_x_label.text = "%.2f" % left_hand_x
	_update_left_hand_position()


func _on_left_hand_y_changed(value: float) -> void:
	left_hand_y = value
	if left_hand_y_label:
		left_hand_y_label.text = "%.2f" % left_hand_y
	_update_left_hand_position()


func _on_left_hand_z_changed(value: float) -> void:
	left_hand_z = value
	if left_hand_z_label:
		left_hand_z_label.text = "%.2f" % left_hand_z
	_update_left_hand_position()


func _update_left_hand_position() -> void:
	CharacterAPIScript.update_left_hand_position(character_body, left_hand_x, left_hand_y, left_hand_z)
	print("[AnimViewer] Left hand pos: (%.2f, %.2f, %.2f)" % [left_hand_x, left_hand_y, left_hand_z])


func _on_shoot_pressed() -> void:
	_shoot()


func _shoot() -> void:
	character_body.apply_recoil(1.0)
	print("[AnimViewer] Shot fired!")


func _on_auto_fire_pressed() -> void:
	is_shooting = not is_shooting
	if is_shooting:
		_start_auto_fire()
	print("[AnimViewer] Auto-fire: %s" % ("ON" if is_shooting else "OFF"))


func _start_auto_fire() -> void:
	if not is_shooting:
		return
	_shoot()
	get_tree().create_timer(0.1).timeout.connect(_start_auto_fire)


# Character resource loading
func _load_character_resource(character_id: String) -> void:
	character_resource = CharacterRegistry.get_character(character_id)
	if character_resource:
		print("[AnimViewer] Loaded CharacterResource for: %s" % character_id)
	else:
		print("[AnimViewer] No CharacterResource found for: %s (using defaults)" % character_id)


func _apply_character_ik_offset() -> void:
	CharacterAPIScript.apply_character_ik_from_resource(character_body, current_character_id)


# Camera view callbacks
func _on_camera_front() -> void:
	if camera:
		camera.set_front_view()


func _on_camera_back() -> void:
	if camera:
		camera.set_back_view()


func _on_camera_left() -> void:
	if camera:
		camera.set_left_view()


func _on_camera_right() -> void:
	if camera:
		camera.set_right_view()


func _on_camera_top() -> void:
	if camera:
		camera.set_top_view()


func _toggle_laser() -> void:
	CharacterAPIScript.toggle_laser(character_body)
	print("[AnimViewer] Laser toggled")
