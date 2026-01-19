extends Node3D
## 武器装着確認用テストシーン
## キャラクター1体に武器を装着し、ドラッグでカメラを回転できる

const AnimCtrl = preload("res://scripts/animation/character_animation_controller.gd")

var _character: Node = null
var _weapon: Node3D = null
var _attachment: BoneAttachment3D = null
var _skeleton: Skeleton3D = null

# Camera
var _camera: Camera3D = null
var _cam_dist: float = 3.0
var _cam_rot: Vector2 = Vector2(0, 0.3)
var _cam_target: Vector3 = Vector3(0, 1.2, 0)
var _dragging: bool = false

# UI
var _ui: CanvasLayer = null
var _rot_x_slider: HSlider = null
var _rot_y_slider: HSlider = null
var _rot_z_slider: HSlider = null
var _pos_x_slider: HSlider = null
var _pos_y_slider: HSlider = null
var _pos_z_slider: HSlider = null
var _scale_slider: HSlider = null
var _info_label: Label = null
var _animation_dropdown: OptionButton = null
var _weapon_dropdown: OptionButton = null

# Weapon configs - scale 100 is skeleton compensation (Mixamo skeleton is 0.01)
const WEAPON_CONFIGS = {
	"AK47": {
		"path": "res://assets/weapons/ak47/ak47.glb",
		"scale": 100.0,
		"rotation": Vector3(-71, -103, 4),
		"position": Vector3(2, 6, 1)
	},
	"Glock": {
		"path": "res://assets/weapons/glock/glock.glb",
		"scale": 100.0,
		"rotation": Vector3(-79, -66, -28),
		"position": Vector3(1, 10, 2)
	}
}

# Animation configs
const ANIMATIONS = [
	# Rifle AIM + Movement
	{"name": "[Rifle] Walk Forward", "weapon": AnimCtrl.Weapon.RIFLE, "aiming": true, "move": "forward", "run": false},
	{"name": "[Rifle] Walk Backward", "weapon": AnimCtrl.Weapon.RIFLE, "aiming": true, "move": "backward", "run": false},
	{"name": "[Rifle] Walk Left", "weapon": AnimCtrl.Weapon.RIFLE, "aiming": true, "move": "left", "run": false},
	{"name": "[Rifle] Walk Right", "weapon": AnimCtrl.Weapon.RIFLE, "aiming": true, "move": "right", "run": false},
	{"name": "[Rifle] Sprint", "weapon": AnimCtrl.Weapon.RIFLE, "aiming": false, "move": "forward", "run": true},
	{"name": "[Rifle] Aim Idle", "weapon": AnimCtrl.Weapon.RIFLE, "aiming": true, "move": "none", "run": false},
	# Pistol AIM + Movement
	{"name": "[Pistol] Walk Forward", "weapon": AnimCtrl.Weapon.PISTOL, "aiming": true, "move": "forward", "run": false},
	{"name": "[Pistol] Walk Backward", "weapon": AnimCtrl.Weapon.PISTOL, "aiming": true, "move": "backward", "run": false},
	{"name": "[Pistol] Walk Left", "weapon": AnimCtrl.Weapon.PISTOL, "aiming": true, "move": "left", "run": false},
	{"name": "[Pistol] Walk Right", "weapon": AnimCtrl.Weapon.PISTOL, "aiming": true, "move": "right", "run": false},
	{"name": "[Pistol] Sprint", "weapon": AnimCtrl.Weapon.PISTOL, "aiming": false, "move": "forward", "run": true},
	{"name": "[Pistol] Aim Idle", "weapon": AnimCtrl.Weapon.PISTOL, "aiming": true, "move": "none", "run": false},
]

# Current animation state
var _current_move: String = "none"
var _current_run: bool = false


func _ready() -> void:
	print("=== Weapon Viewer Test ===")

	_camera = $Camera3D
	_update_camera()

	# Create character
	var presets = CharacterRegistry.get_all()
	if presets.is_empty():
		print("ERROR: No character presets")
		return

	_character = CharacterRegistry.create_character(presets[0].id, Vector3.ZERO)
	add_child(_character)
	_character.rotation.y = PI  # Face camera
	print("Character created: ", presets[0].id)

	# Wait for character to be ready
	await get_tree().process_frame

	# Find skeleton
	var model = _character.get_node_or_null("CharacterModel")
	if not model:
		print("ERROR: No CharacterModel")
		return

	_skeleton = _find_skeleton(model)
	if not _skeleton:
		print("ERROR: No Skeleton3D found")
		return

	print("Found skeleton: ", _skeleton.name)

	# Find RightHand bone
	var bone_idx = _skeleton.find_bone("mixamorig_RightHand")
	if bone_idx < 0:
		print("ERROR: RightHand bone not found")
		return

	print("Found RightHand bone at index ", bone_idx)

	# Create BoneAttachment3D
	_attachment = BoneAttachment3D.new()
	_attachment.name = "WeaponAttachment"
	_attachment.bone_name = "mixamorig_RightHand"
	_skeleton.add_child(_attachment)

	# Create UI first (before loading weapon)
	_create_ui()

	# Load default weapon (Glock) and set matching Pistol animation
	_load_weapon("Glock")

	# Find first Pistol Walk Forward animation (index 6)
	for i in range(ANIMATIONS.size()):
		if ANIMATIONS[i].weapon == AnimCtrl.Weapon.PISTOL and ANIMATIONS[i].move == "forward" and not ANIMATIONS[i].run:
			_animation_dropdown.selected = i
			_set_animation(i)
			break


func _load_weapon(weapon_name: String) -> void:
	# Remove existing weapon
	if _weapon:
		_weapon.queue_free()
		_weapon = null

	var config = WEAPON_CONFIGS.get(weapon_name)
	if not config:
		print("ERROR: Unknown weapon: ", weapon_name)
		return

	var weapon_resource = load(config.path)
	if not weapon_resource:
		print("ERROR: Failed to load weapon: ", config.path)
		return

	_weapon = weapon_resource.instantiate()
	_weapon.name = weapon_name

	# Apply config
	_weapon.scale = Vector3.ONE * config.scale
	_weapon.rotation_degrees = config.rotation
	_weapon.position = config.position

	_attachment.add_child(_weapon)
	print("Weapon loaded: ", weapon_name)

	# Update sliders to match weapon config
	if _scale_slider:
		_scale_slider.value = config.scale
		_rot_x_slider.value = config.rotation.x
		_rot_y_slider.value = config.rotation.y
		_rot_z_slider.value = config.rotation.z
		_pos_x_slider.value = config.position.x
		_pos_y_slider.value = config.position.y
		_pos_z_slider.value = config.position.z
		_update_info_label()


func _set_animation(index: int) -> void:
	if index < 0 or index >= ANIMATIONS.size():
		return

	var anim_config = ANIMATIONS[index]
	var anim_ctrl = _character.get_anim_controller()
	if anim_ctrl:
		# Ensure AnimationTree is active (may have been disabled by direct play)
		if anim_ctrl._anim_tree:
			anim_ctrl._anim_tree.active = true
		anim_ctrl.set_weapon(anim_config.weapon)
		anim_ctrl.set_aiming(anim_config.aiming)

	# Store movement state
	_current_move = anim_config.get("move", "none")
	_current_run = anim_config.get("run", false)
	print("Animation set: ", anim_config.name, " (move: ", _current_move, ", run: ", _current_run, ")")


func _create_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	var panel := PanelContainer.new()
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = 300
	panel.offset_bottom = 500
	_ui.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Weapon Viewer"
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Animation dropdown
	vbox.add_child(_create_label("Animation"))
	_animation_dropdown = OptionButton.new()
	for i in range(ANIMATIONS.size()):
		_animation_dropdown.add_item(ANIMATIONS[i].name, i)
	_animation_dropdown.selected = 0  # Rifle Walk Forward
	_animation_dropdown.item_selected.connect(_on_animation_selected)
	vbox.add_child(_animation_dropdown)

	# Weapon dropdown
	vbox.add_child(_create_label("Weapon"))
	_weapon_dropdown = OptionButton.new()
	var idx := 0
	for weapon_name in WEAPON_CONFIGS.keys():
		_weapon_dropdown.add_item(weapon_name, idx)
		idx += 1
	_weapon_dropdown.selected = 1  # Glock
	_weapon_dropdown.item_selected.connect(_on_weapon_selected)
	vbox.add_child(_weapon_dropdown)

	vbox.add_child(HSeparator.new())

	# Rotation X
	vbox.add_child(_create_label("Rotation X"))
	_rot_x_slider = _create_slider(-180, 180, 0)
	_rot_x_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_rot_x_slider)

	# Rotation Y
	vbox.add_child(_create_label("Rotation Y"))
	_rot_y_slider = _create_slider(-180, 180, -90)
	_rot_y_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_rot_y_slider)

	# Rotation Z
	vbox.add_child(_create_label("Rotation Z"))
	_rot_z_slider = _create_slider(-180, 180, -90)
	_rot_z_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_rot_z_slider)

	vbox.add_child(HSeparator.new())

	# Position X
	vbox.add_child(_create_label("Position X"))
	_pos_x_slider = _create_slider(-50, 50, 0)
	_pos_x_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_pos_x_slider)

	# Position Y
	vbox.add_child(_create_label("Position Y"))
	_pos_y_slider = _create_slider(-50, 50, 0)
	_pos_y_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_pos_y_slider)

	# Position Z
	vbox.add_child(_create_label("Position Z"))
	_pos_z_slider = _create_slider(-50, 50, 0)
	_pos_z_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_pos_z_slider)

	vbox.add_child(HSeparator.new())

	# Scale
	vbox.add_child(_create_label("Scale"))
	_scale_slider = _create_slider(1, 200, 100)
	_scale_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_scale_slider)

	vbox.add_child(HSeparator.new())

	# Info label
	_info_label = Label.new()
	_info_label.text = "..."
	vbox.add_child(_info_label)

	vbox.add_child(HSeparator.new())

	# Direct animation test buttons (bypass AnimationTree)
	vbox.add_child(_create_label("Direct Play (Debug)"))
	var btn_rifle := Button.new()
	btn_rifle.text = "Play rifle_walk_forward"
	btn_rifle.pressed.connect(_play_direct.bind("rifle_walk_forward"))
	vbox.add_child(btn_rifle)

	var btn_pistol := Button.new()
	btn_pistol.text = "Play pistol_walk_forward"
	btn_pistol.pressed.connect(_play_direct.bind("pistol_walk_forward"))
	vbox.add_child(btn_pistol)


func _on_animation_selected(index: int) -> void:
	_set_animation(index)


func _on_weapon_selected(index: int) -> void:
	var weapon_name = WEAPON_CONFIGS.keys()[index]
	_load_weapon(weapon_name)

	# Auto-select matching animation type based on weapon
	var target_weapon_type: int
	if weapon_name == "Glock":
		target_weapon_type = AnimCtrl.Weapon.PISTOL
	else:
		target_weapon_type = AnimCtrl.Weapon.RIFLE

	# Find first animation matching the weapon type and current move direction
	for i in range(ANIMATIONS.size()):
		var anim = ANIMATIONS[i]
		if anim.weapon == target_weapon_type and anim.move == _current_move and anim.run == _current_run:
			_animation_dropdown.selected = i
			_set_animation(i)
			break


func _play_direct(anim_name: String) -> void:
	# Stop AnimationTree and play directly via AnimationPlayer
	var anim_ctrl = _character.get_anim_controller()
	if anim_ctrl and anim_ctrl._anim_tree:
		anim_ctrl._anim_tree.active = false

	var model = _character.get_node_or_null("CharacterModel")
	if model:
		var anim_player = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim_player:
			if anim_player.has_animation(anim_name):
				anim_player.play(anim_name)
				print("Direct play: ", anim_name)
			else:
				print("Animation not found: ", anim_name)
				print("Available: ", anim_player.get_animation_list())


func _create_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _create_slider(min_val: float, max_val: float, default_val: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = 1
	slider.custom_minimum_size = Vector2(200, 20)
	return slider


func _on_transform_changed(_value: float) -> void:
	if not _weapon:
		return

	_weapon.rotation_degrees = Vector3(
		_rot_x_slider.value,
		_rot_y_slider.value,
		_rot_z_slider.value
	)
	_weapon.position = Vector3(
		_pos_x_slider.value,
		_pos_y_slider.value,
		_pos_z_slider.value
	)
	_weapon.scale = Vector3.ONE * _scale_slider.value

	_update_info_label()


func _update_info_label() -> void:
	if not _info_label or not _weapon:
		return

	_info_label.text = "rot: (%.0f, %.0f, %.0f)\npos: (%.0f, %.0f, %.0f)\nscale: %.0f" % [
		_rot_x_slider.value, _rot_y_slider.value, _rot_z_slider.value,
		_pos_x_slider.value, _pos_y_slider.value, _pos_z_slider.value,
		_scale_slider.value
	]


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null


func _input(event: InputEvent) -> void:
	# Don't move camera if mouse is over UI
	var mouse_over_ui := false
	if _ui:
		var viewport := get_viewport()
		if viewport:
			var mouse_pos := viewport.get_mouse_position()
			# Check if mouse is in UI panel area (left side)
			if mouse_pos.x < 310 and mouse_pos.y < 510:
				mouse_over_ui = true

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not mouse_over_ui:
				_dragging = event.pressed
			else:
				_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and not mouse_over_ui:
			_cam_dist = max(1.0, _cam_dist - 0.2)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not mouse_over_ui:
			_cam_dist = min(10.0, _cam_dist + 0.2)
			_update_camera()

	if event is InputEventMouseMotion and _dragging and not mouse_over_ui:
		_cam_rot.x -= event.relative.x * 0.01
		_cam_rot.y = clamp(_cam_rot.y + event.relative.y * 0.01, -1.5, 1.5)
		_update_camera()


func _update_camera() -> void:
	if not _camera:
		return
	var offset = Vector3(
		sin(_cam_rot.x) * cos(_cam_rot.y),
		sin(_cam_rot.y),
		cos(_cam_rot.x) * cos(_cam_rot.y)
	) * _cam_dist
	_camera.position = _cam_target + offset
	_camera.look_at(_cam_target)


func _physics_process(delta: float) -> void:
	if not _character:
		return

	var anim_ctrl = _character.get_anim_controller()
	if anim_ctrl:
		# Get look direction (character faces camera)
		var look_dir = anim_ctrl.get_look_direction()

		# Calculate movement direction based on current animation
		# Note: Forward/Backward are negated due to +Z/-Z convention mismatch in CharacterAnimationController
		var move_dir := Vector3.ZERO
		match _current_move:
			"forward":
				move_dir = -look_dir
			"backward":
				move_dir = look_dir
			"left":
				move_dir = Vector3(-look_dir.z, 0, look_dir.x)
			"right":
				move_dir = Vector3(look_dir.z, 0, -look_dir.x)

		anim_ctrl.update_animation(move_dir, look_dir, _current_run, delta)
