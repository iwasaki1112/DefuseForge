extends Node3D
## Animation viewer - simple animation testing for character models
## Uses the new simplified CharacterBase API

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
var current_character_id: String = "shade"
var character_model: Node3D = null
var character_option_button: OptionButton = null

# Upper body rotation
var upper_body_rotation: float = 0.0
var upper_body_rotation_label: Label = null
const UPPER_BODY_ROTATION_MIN: float = -45.0
const UPPER_BODY_ROTATION_MAX: float = 45.0

# Weapon selection
const WEAPONS_DIR: String = "res://resources/weapons/"
var available_weapons: Array[String] = []
var current_weapon_id: String = "ak47"
var weapon_resource: WeaponResource = null
var weapon_option_button: OptionButton = null

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

	# Wait for CharacterBase to setup
	await get_tree().process_frame

	# Equip weapon
	character_body.set_weapon(_weapon_id_string_to_int(current_weapon_id))

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


func _create_ui_layout() -> void:
	# Left panel - Character/Weapon selection
	left_panel = PanelContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_panel.offset_right = 200
	left_panel.offset_bottom = 280
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


## 表示するアニメーション名（完全一致、優先順）
const PREFERRED_ANIMATIONS: Array[String] = [
	"idle",
	"walk",  # Simple name from NLA track
	"run",   # Simple name from NLA track
	"e01-walk-f-loop_remap",  # Legacy walk
	"c12-run-f-loop_remap",   # Legacy run/sprint
]

## フォールバック用キーワード
const FALLBACK_KEYWORDS: Dictionary = {
	"idle": ["idle"],
	"walk": ["walk"],
	"run": ["run", "sprint"],
}

## Allow non-_remap animations too
const ALLOW_SIMPLE_NAMES: bool = true


func _collect_animations() -> void:
	_animations.clear()

	# Get all animations from AnimationPlayer
	var all_anims: PackedStringArray = PackedStringArray()
	if character_body.animation and character_body.animation.has_method("get_animation_list"):
		all_anims = character_body.animation.get_animation_list()
		print("[AnimViewer] Got %d animations from animation component" % all_anims.size())
	elif character_body.model:
		var anim_player = _find_animation_player(character_body.model)
		if anim_player:
			all_anims = anim_player.get_animation_list()
			print("[AnimViewer] Got %d animations from AnimationPlayer" % all_anims.size())

	print("[AnimViewer] All animations: %s" % str(all_anims))

	# First try preferred animations (exact match)
	for pref_anim in PREFERRED_ANIMATIONS:
		for anim_name in all_anims:
			if anim_name == pref_anim:
				_animations.append(anim_name)
				break

	# If no preferred found, use fallback keywords
	if _animations.is_empty():
		for category in FALLBACK_KEYWORDS:
			var keywords: Array = FALLBACK_KEYWORDS[category]
			for anim_name in all_anims:
				if anim_name == "RESET":
					continue
				var anim_lower = anim_name.to_lower()
				var found = false
				for keyword in keywords:
					# Match with _remap suffix or simple names
					if keyword in anim_lower:
						if "_remap" in anim_lower or ALLOW_SIMPLE_NAMES:
							_animations.append(anim_name)
							found = true
							break
				if found:
					break


func _find_animation_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found = _find_animation_player(child)
		if found:
			return found
	return null


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
		elif event.keycode == KEY_T:
			upper_body_rotation = 30.0 if upper_body_rotation < 1.0 else 0.0
			character_body.set_upper_body_rotation(upper_body_rotation)


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

	# Remove old model
	if character_model:
		character_body.remove_child(character_model)
		character_model.queue_free()
		character_model = null

	# Reset CharacterBase internal state
	character_body.skeleton = null
	character_body.model = null
	character_body.set_weapon(WeaponRegistry.WeaponId.NONE)

	# Update current character ID
	current_character_id = character_id

	# Load new character
	var glb_path = CHARACTERS_DIR + character_id + "/" + character_id + ".glb"
	var fbx_path = CHARACTERS_DIR + character_id + "/" + character_id + ".fbx"
	var character_path = glb_path if ResourceLoader.exists(glb_path) else fbx_path
	var character_scene = load(character_path)
	if not character_scene:
		push_warning("[AnimViewer] Failed to load character: %s" % character_path)
		return

	character_model = character_scene.instantiate()
	character_model.name = "CharacterModel"
	character_body.add_child(character_model)

	# Re-setup CharacterBase
	character_body._find_model_and_skeleton()
	character_body._setup_components()
	character_body._connect_signals()

	# Equip weapon
	character_body.set_weapon(_weapon_id_string_to_int(current_weapon_id))

	# Collect animations
	_collect_animations()

	# Refresh UI
	_populate_ui()

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


func _play_animation(anim_name: String) -> void:
	character_body.play_animation(anim_name, blend_time)
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
