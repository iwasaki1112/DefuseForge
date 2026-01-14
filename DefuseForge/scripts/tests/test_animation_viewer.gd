extends Node3D
## Animation viewer - simple animation testing for character models
## Uses the new simplified CharacterBase API

const CharacterAPIScript = preload("res://scripts/api/character_api.gd")
const FogOfWarSystemScript = preload("res://scripts/systems/fog_of_war_system.gd")
const SelectionManagerScript = preload("res://scripts/managers/selection_manager.gd")
const CharacterInteractionManagerScript = preload("res://scripts/managers/character_interaction_manager.gd")
const ContextMenuComponentScript = preload("res://scripts/ui/context_menu_component.gd")
const ContextMenuItemScript = preload("res://scripts/resources/context_menu_item.gd")

@onready var camera: Camera3D = $OrbitCamera
@onready var canvas_layer: CanvasLayer = $CanvasLayer

# 複数キャラクター管理
var characters: Array[CharacterBase] = []
var controlled_character: CharacterBase = null  # WASD操作対象
var character_body: CharacterBase = null  # 後方互換性のため保持

var _animations: Array[String] = []
const GRAVITY: float = 9.8
const MOVE_SPEED: float = 5.0  # 移動速度

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

# Fog of War
var fog_of_war_system: Node3D = null
var test_walls: Array[StaticBody3D] = []
var wall_shader_material: ShaderMaterial = null

# Input rotation component (click on character + drag)
const InputRotationComponentScript = preload("res://scripts/characters/components/input_rotation_component.gd")
var _input_rotations: Array[Node] = []  # 各キャラクター用

# Selection management
var _selection_manager: Node
var _highlight_checkbox: CheckButton

# Context menu and interaction
var _interaction_manager: Node
var _context_menu: Control


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

	# 複数キャラクターを配列に追加
	var char1 = get_node_or_null("CharacterBody") as CharacterBase
	var char2 = get_node_or_null("CharacterBody2") as CharacterBase
	if char1:
		characters.append(char1)
	if char2:
		characters.append(char2)

	# デフォルトは1体目を操作
	if characters.size() > 0:
		controlled_character = characters[0]
		character_body = characters[0]  # 後方互換性

	# Get reference to character model
	character_model = character_body.get_node_or_null("CharacterModel") if character_body else null

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

	# Setup outline camera for all characters (SubViewport方式に必要)
	for character in characters:
		character.setup_outline_camera(camera)

	# 2体目にも武器を装備してIKオフセットを適用
	for i in range(1, characters.size()):
		characters[i].set_weapon(_weapon_id_string_to_int(current_weapon_id))
		CharacterAPIScript.apply_character_ik_from_resource(characters[i], current_character_id)

	# 2体目のIK値も更新（1フレーム待ってから）
	await get_tree().process_frame
	for i in range(1, characters.size()):
		CharacterAPIScript.update_elbow_pole_position(characters[i], elbow_pole_x, elbow_pole_y, elbow_pole_z)
		CharacterAPIScript.update_left_hand_position(characters[i], left_hand_x, left_hand_y, left_hand_z)

	# Setup selection manager
	_selection_manager = SelectionManagerScript.new()
	_selection_manager.name = "SelectionManager"
	add_child(_selection_manager)
	_selection_manager.selection_changed.connect(_on_selection_changed)

	# Setup input rotation component
	_setup_input_rotation()

	# Setup context menu
	_setup_context_menu()

	# Setup interaction manager (coordinates selection, menu, and rotation)
	_setup_interaction_manager()

	# Play idle animation
	if _animations.size() > 0:
		_play_animation(_animations[0])

	# Setup Fog of War test environment
	_setup_fog_of_war()
	_create_test_walls()


func _setup_input_rotation() -> void:
	# 各キャラクターにInputRotationComponentを追加
	for character in characters:
		var input_rotation = InputRotationComponentScript.new()
		input_rotation.name = "InputRotationComponent"
		character.add_child(input_rotation)
		input_rotation.setup(camera)
		# Enable menu-based activation (disable long-press auto-rotation)
		input_rotation.require_menu_activation = true
		_input_rotations.append(input_rotation)


func _setup_context_menu() -> void:
	# Create context menu UI
	_context_menu = ContextMenuComponentScript.new()
	_context_menu.name = "ContextMenu"
	canvas_layer.add_child(_context_menu)

	# Add menu items
	var rotate_item = ContextMenuItemScript.create("rotate", "回転", 0)
	var control_item = ContextMenuItemScript.create("control", "操作", 1)
	_context_menu.add_item(rotate_item)
	_context_menu.add_item(control_item)


func _setup_interaction_manager() -> void:
	_interaction_manager = CharacterInteractionManagerScript.new()
	_interaction_manager.name = "CharacterInteractionManager"
	add_child(_interaction_manager)

	# Setup with base components (最初のInputRotationを渡す)
	var first_input_rotation = _input_rotations[0] if _input_rotations.size() > 0 else null
	_interaction_manager.setup(
		_selection_manager,
		_context_menu,
		first_input_rotation,
		camera
	)

	# 追加のInputRotationを登録（2体目以降）
	for i in range(1, _input_rotations.size()):
		_interaction_manager.register_input_rotation(_input_rotations[i], characters[i])

	# action_startedシグナルを接続（操作切替用）
	_interaction_manager.action_started.connect(_on_action_started)

	# Connect state changes for UI updates
	_interaction_manager.state_changed.connect(_on_interaction_state_changed)


func _setup_fog_of_war() -> void:
	# FogOfWarSystemを作成
	fog_of_war_system = Node3D.new()
	fog_of_war_system.set_script(FogOfWarSystemScript)
	fog_of_war_system.name = "FogOfWarSystem"
	add_child(fog_of_war_system)

	# すべてのキャラクターの視界を登録
	await get_tree().process_frame
	for character in characters:
		if character and character.vision:
			fog_of_war_system.register_vision(character.vision)


func _create_test_walls() -> void:
	# 壁用シェーダーマテリアルを作成
	_create_wall_shader_material()

	# テスト用の壁を配置（Layer 2に設定）
	var wall_configs = [
		{"pos": Vector3(5, 0, 0), "size": Vector3(0.3, 3, 4), "rot": 0},
		{"pos": Vector3(-4, 0, 3), "size": Vector3(0.3, 3, 3), "rot": 45},
		{"pos": Vector3(0, 0, -6), "size": Vector3(6, 3, 0.3), "rot": 0},
		{"pos": Vector3(-6, 0, -2), "size": Vector3(0.3, 3, 5), "rot": 0},
	]

	for config in wall_configs:
		var wall = _create_wall(config.size, config.pos, config.rot)
		test_walls.append(wall)
		add_child(wall)


func _create_wall_shader_material() -> void:
	var shader_code = """
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.4, 0.4, 0.45, 1.0);
uniform vec4 lit_color : source_color = vec4(0.8, 0.75, 0.6, 1.0);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);
uniform float light_intensity = 0.6;

void fragment() {
	// ワールド座標を取得
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world_xz = world_pos.xz;

	// ワールド座標をUV座標に変換
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	// テクスチャから可視性を取得
	float visibility = texture(visibility_texture, uv).r;

	// 視界内は明るく、視界外は暗く
	vec3 final_color = mix(base_color.rgb, lit_color.rgb, visibility * light_intensity);

	ALBEDO = final_color;
}
"""
	var shader = Shader.new()
	shader.code = shader_code

	wall_shader_material = ShaderMaterial.new()
	wall_shader_material.shader = shader
	wall_shader_material.set_shader_parameter("base_color", Color(0.25, 0.25, 0.3))
	wall_shader_material.set_shader_parameter("lit_color", Color(0.7, 0.65, 0.5))
	wall_shader_material.set_shader_parameter("map_min", Vector2(-20, -20))
	wall_shader_material.set_shader_parameter("map_max", Vector2(20, 20))


func _create_wall(size: Vector3, pos: Vector3, rot_degrees: float) -> StaticBody3D:
	var wall = StaticBody3D.new()
	wall.collision_layer = 3  # Layer 1（物理衝突）+ Layer 2（視界検出）
	wall.collision_mask = 0   # 壁自体は他の物体を検出しない
	wall.add_to_group("walls")  # シャドウキャスト用のグループ

	# メッシュ
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = size.y / 2

	# シェーダーマテリアルを適用（視界に応じて明るさが変わる）
	if wall_shader_material:
		mesh_instance.material_override = wall_shader_material

	# コリジョン
	var collision = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	collision.position.y = size.y / 2

	wall.add_child(mesh_instance)
	wall.add_child(collision)

	wall.position = pos
	wall.rotation_degrees.y = rot_degrees

	return wall


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

	# Selection highlight
	var select_label = Label.new()
	select_label.text = "Selection"
	vbox.add_child(select_label)

	_highlight_checkbox = CheckButton.new()
	_highlight_checkbox.text = "Highlight"
	_highlight_checkbox.toggled.connect(_on_selection_toggled)
	vbox.add_child(_highlight_checkbox)


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


func _physics_process(_delta: float) -> void:
	# 操作対象キャラクターにWASD入力を送信
	if controlled_character and controlled_character.movement:
		# WASD移動入力
		var input_dir = Vector3.ZERO
		if Input.is_key_pressed(KEY_W):
			input_dir.z -= 1
		if Input.is_key_pressed(KEY_S):
			input_dir.z += 1
		if Input.is_key_pressed(KEY_A):
			input_dir.x -= 1
		if Input.is_key_pressed(KEY_D):
			input_dir.x += 1

		# 正規化してMovementComponentに渡す
		if input_dir.length_squared() > 0:
			input_dir = input_dir.normalized()

		# Shiftで走る
		var is_running = Input.is_key_pressed(KEY_SHIFT)
		controlled_character.movement.set_input_direction(input_dir, is_running)
		# CharacterBase._physics_process()がmove_and_slide()を呼ぶ


func _process(_delta: float) -> void:
	# 壁シェーダーに可視性テクスチャを渡す
	if wall_shader_material and fog_of_war_system:
		var visibility_tex = fog_of_war_system.get_visibility_texture()
		if visibility_tex:
			wall_shader_material.set_shader_parameter("visibility_texture", visibility_tex)


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
	CharacterAPIScript.play_animation(character_body, anim_name, 0.3)
	print("[AnimViewer] Playing: %s" % anim_name)


func _on_animation_button_pressed(anim_name: String) -> void:
	_play_animation(anim_name)


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
	if controlled_character:
		controlled_character.apply_recoil(1.0)
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


func _on_selection_toggled(toggled_on: bool) -> void:
	if toggled_on:
		_selection_manager.select(character_body)
	else:
		_selection_manager.deselect()


func _on_selection_changed(character: CharacterBody3D) -> void:
	if _highlight_checkbox:
		_highlight_checkbox.set_pressed_no_signal(character != null)


func _on_interaction_state_changed(_old_state: int, new_state: int) -> void:
	# CharacterInteractionManager.InteractionState enum values:
	# 0 = IDLE, 1 = MENU_OPEN, 2 = ROTATING
	match new_state:
		0:  # IDLE
			pass
		1:  # MENU_OPEN
			print("[AnimViewer] Context menu opened")
		2:  # ROTATING
			print("[AnimViewer] Rotation mode started")


func _toggle_laser() -> void:
	CharacterAPIScript.toggle_laser(character_body)
	print("[AnimViewer] Laser toggled")


## 操作切替処理
func _on_action_started(action_id: String, character: CharacterBody3D) -> void:
	if action_id == "control" and character:
		controlled_character = character as CharacterBase
		print("[AnimViewer] Control switched to: %s" % character.name)
