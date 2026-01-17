extends Node3D
## 武器装着確認用テストシーン
## キャラクター1体にAK47を装着し、ドラッグでカメラを回転できる

var _character: Node = null
var _weapon: Node3D = null
var _attachment: BoneAttachment3D = null

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

	# Find skeleton and attach weapon
	var model = _character.get_node_or_null("CharacterModel")
	if not model:
		print("ERROR: No CharacterModel")
		return

	var skeleton = _find_skeleton(model)
	if not skeleton:
		print("ERROR: No Skeleton3D found")
		return

	print("Found skeleton: ", skeleton.name)

	# Find RightHand bone
	var bone_idx = skeleton.find_bone("mixamorig_RightHand")
	if bone_idx < 0:
		print("ERROR: RightHand bone not found")
		return

	print("Found RightHand bone at index ", bone_idx)

	# Create BoneAttachment3D
	_attachment = BoneAttachment3D.new()
	_attachment.name = "WeaponAttachment"
	_attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(_attachment)

	# Load and attach weapon
	var weapon_path := "res://assets/weapons/ak47/ak47.glb"
	var weapon_resource = load(weapon_path)
	if not weapon_resource:
		print("ERROR: Failed to load weapon: ", weapon_path)
		return

	_weapon = weapon_resource.instantiate()
	_weapon.name = "AK47"
	_weapon.scale = Vector3.ONE * 13
	_weapon.rotation_degrees = Vector3(-65, -103, 4)
	_weapon.position = Vector3(3, 6, 1)
	_attachment.add_child(_weapon)

	print("Weapon attached to hand")

	# Create UI
	_create_ui()


func _create_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	var panel := PanelContainer.new()
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = 300
	panel.offset_bottom = 400
	_ui.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Weapon Transform"
	vbox.add_child(title)

	# Rotation X
	vbox.add_child(_create_label("Rotation X"))
	_rot_x_slider = _create_slider(-180, 180, -65)
	_rot_x_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_rot_x_slider)

	# Rotation Y
	vbox.add_child(_create_label("Rotation Y"))
	_rot_y_slider = _create_slider(-180, 180, -103)
	_rot_y_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_rot_y_slider)

	# Rotation Z
	vbox.add_child(_create_label("Rotation Z"))
	_rot_z_slider = _create_slider(-180, 180, 4)
	_rot_z_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_rot_z_slider)

	vbox.add_child(HSeparator.new())

	# Position X
	vbox.add_child(_create_label("Position X"))
	_pos_x_slider = _create_slider(-50, 50, 3)
	_pos_x_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_pos_x_slider)

	# Position Y
	vbox.add_child(_create_label("Position Y"))
	_pos_y_slider = _create_slider(-50, 50, 6)
	_pos_y_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_pos_y_slider)

	# Position Z
	vbox.add_child(_create_label("Position Z"))
	_pos_z_slider = _create_slider(-50, 50, 1)
	_pos_z_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_pos_z_slider)

	vbox.add_child(HSeparator.new())

	# Scale
	vbox.add_child(_create_label("Scale"))
	_scale_slider = _create_slider(1, 30, 13)
	_scale_slider.value_changed.connect(_on_transform_changed)
	vbox.add_child(_scale_slider)

	vbox.add_child(HSeparator.new())

	# Info label
	_info_label = Label.new()
	_info_label.text = "..."
	vbox.add_child(_info_label)

	_update_info_label()


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
			if mouse_pos.x < 310 and mouse_pos.y < 410:
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
