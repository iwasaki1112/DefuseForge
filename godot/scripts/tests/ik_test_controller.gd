extends Node3D
## IK Animation System テストコントローラー
##
## 右腕/左手IKシステム（UpperBodyIKController）の動作確認用テストシーン。
## 右側パネルのスライダーでIK位置パラメータをリアルタイム調整できる。
##
## テスト項目:
## - 基本動作: 移動/スプリント/アイドルの下半身アニメーション
## - 腕IK: 右手武器位置固定、左手グリップ追従
## - IKパラメータ調整: Hand/Pole位置のリアルタイム変更

# ============================================
# Constants
# ============================================
const GROUND_SIZE := 50.0
const CHARACTER_PRESET_ID := "dummy_ct"
const ENEMY_PRESET_ID := "ares"
const DEFAULT_WEAPON_ID := "ak47"
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const ANIMATION_SOURCE := "res://assets/animations/character_anims_kubold.glb"
const ANIMATION_SOURCE_UNIFIED := "res://assets/animations/animations.glb"
const VISION_FOV := 75.0
const VISION_RANGE := 7.0
const MAP_SIZE := Vector2(50.0, 50.0)

const PANEL_WIDTH := 280

# ============================================
# References
# ============================================
var _character: GameCharacter = null
var _enemies: Array[GameCharacter] = []
var _camera: Camera3D = null
var _tps_controller: TPSPlayerController = null
var _animation_library: AnimationLibrary = null
var _vision_service: VisionService = null
var _ui_layer: CanvasLayer = null

# IK Panel references
var _state_option: OptionButton = null
var _lh_offset_sliders: Array[HSlider] = []  # Left hand grip offset [X, Y, Z]
var _lh_offset_spins: Array[SpinBox] = []
var _lh_pole_sliders: Array[HSlider] = []  # Left elbow pole [X, Y, Z]
var _lh_pole_spins: Array[SpinBox] = []
var _weapon_option: OptionButton = null
var _weapon_list: Array = []
var _slider_drag_count: int = 0
var _ik_panel: PanelContainer = null
var _axis_gizmo: Node3D = null
var _sprint_check: CheckBox = null
var _speed_label: Label = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_environment()
	_create_ground()
	_animation_library = _load_animation_library()
	PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	_spawn_character()
	_create_axis_gizmo()
	_setup_camera()
	_setup_ui()
	_setup_tps_controller()


func _physics_process(delta: float) -> void:
	if _tps_controller:
		_update_mouse_aim()
		_tps_controller.process(delta)
	if _axis_gizmo and _character:
		_axis_gizmo.global_position = _character.global_position + Vector3(0, 0.02, 0)
		var facing := _character.get_facing_direction()
		if facing.length_squared() > 0.001:
			_axis_gizmo.rotation.y = atan2(facing.x, facing.z)
	_update_speed_label()


func _input(event: InputEvent) -> void:
	if not _tps_controller:
		return
	if _is_event_on_panel(event):
		return
	# マウスイベントはTPSコントローラーに渡さない（カーソル位置エイムを使用）
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return
	_tps_controller.handle_input(event)


func _is_event_on_panel(event: InputEvent) -> bool:
	if not _ik_panel:
		return false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
	elif event is InputEventMouseButton:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion:
		pos = (event as InputEventMouseMotion).position
	else:
		return false
	return _ik_panel.get_global_rect().has_point(pos)


# ============================================
# TPS Controller Setup
# ============================================

func _setup_tps_controller() -> void:
	if not _character:
		return
	_tps_controller = TPSPlayerController.new()
	_tps_controller.name = "TPSPlayerController"
	add_child(_tps_controller)
	_tps_controller.setup(_character, _camera, _ui_layer, {
		"camera_height": 8.0,
		"camera_pitch_deg": -50.0,
		"enable_aim_stick": true,
	})


## マウスカーソル位置をグラウンド平面に投影し、キャラクターがその方向を向くようにする
func _update_mouse_aim() -> void:
	if not _character or not _camera:
		return
	var mouse_pos := _character.get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var normal := _camera.project_ray_normal(mouse_pos)
	# グラウンド平面（Y=0）との交差
	if absf(normal.y) < 0.001:
		return
	var t := -from.y / normal.y
	if t < 0.0:
		return
	var ground_pos := from + normal * t
	var dir := ground_pos - _character.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	# TPSコントローラーのエイムスティック入力として設定
	_tps_controller._aim_stick_input = Vector2(dir.x, dir.z)


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
	# Kenney Prototype Textures (CC0) のグリッドテクスチャ
	var tex = load("res://assets/textures/kenney_dark_grid.png") as Texture2D
	if tex:
		material.albedo_texture = tex
		material.uv1_scale = Vector3(GROUND_SIZE / 2.0, GROUND_SIZE / 2.0, 1.0)
	else:
		material.albedo_color = Color(0.4, 0.45, 0.4)
	mesh_instance.material_override = material
	ground.add_child(mesh_instance)
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(GROUND_SIZE, 0.1, GROUND_SIZE)
	col_shape.shape = box_shape
	ground.add_child(col_shape)
	ground.position.y = -0.05
	add_child(ground)


func _create_axis_gizmo() -> void:
	_axis_gizmo = Node3D.new()
	_axis_gizmo.name = "AxisGizmo"
	add_child(_axis_gizmo)

	var length := 1.0
	var thickness := 0.02

	var axes := [
		{ "dir": Vector3(1, 0, 0), "color": Color(0.9, 0.2, 0.2) },  # X = Red
		{ "dir": Vector3(0, 1, 0), "color": Color(0.2, 0.8, 0.2) },  # Y = Green
		{ "dir": Vector3(0, 0, 1), "color": Color(0.3, 0.4, 1.0) },  # Z = Blue
	]

	for axis in axes:
		var mesh_inst := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = thickness
		cylinder.bottom_radius = thickness
		cylinder.height = length
		mesh_inst.mesh = cylinder

		var mat := StandardMaterial3D.new()
		mat.albedo_color = axis["color"]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_inst.material_override = mat

		# シリンダーはY軸方向がデフォルト → 各軸に回転
		var dir: Vector3 = axis["dir"]
		mesh_inst.position = dir * (length / 2.0)
		if dir == Vector3(1, 0, 0):
			mesh_inst.rotation_degrees.z = -90.0
		elif dir == Vector3(0, 0, 1):
			mesh_inst.rotation_degrees.x = 90.0

		_axis_gizmo.add_child(mesh_inst)


func _create_test_walls() -> void:
	# 前方に近い壁（GunUp テスト用）
	var wall_data := [
		{ "name": "Wall_Front", "pos": Vector3(0, 1.5, 3), "size": Vector3(4.0, 3.0, 0.3) },
		{ "name": "Wall_Left", "pos": Vector3(-5, 1.5, 0), "size": Vector3(0.3, 3.0, 6.0) },
		{ "name": "Wall_Right", "pos": Vector3(5, 1.5, 0), "size": Vector3(0.3, 3.0, 6.0) },
		{ "name": "Wall_Back", "pos": Vector3(0, 1.5, -5), "size": Vector3(6.0, 3.0, 0.3) },
	]
	for data in wall_data:
		var wall := StaticBody3D.new()
		wall.name = data["name"]
		wall.position = data["pos"]
		# コリジョンレイヤー2（壁）に設定
		wall.collision_layer = 2
		wall.collision_mask = 0
		var mesh_inst := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = data["size"]
		mesh_inst.mesh = box_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.55, 0.5)
		mesh_inst.material_override = mat
		wall.add_child(mesh_inst)
		var col := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = data["size"]
		col.shape = box_shape
		wall.add_child(col)
		add_child(wall)


# ============================================
# Vision Systems
# ============================================

func _setup_vision_systems() -> void:
	_vision_service = VisionService.new()
	_vision_service.name = "VisionService"
	add_child(_vision_service)
	_vision_service.setup(MAP_SIZE, true)
	_vision_service.extract_occluders_from_map(self)


func _register_characters_to_vision() -> void:
	call_deferred("_deferred_register_characters")


func _deferred_register_characters() -> void:
	if _vision_service and _character:
		_vision_service.register_character(_character)
	for enemy in _enemies:
		if _vision_service and is_instance_valid(enemy):
			_vision_service.register_character(enemy)


# ============================================
# Character Spawning
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


func _spawn_enemies() -> void:
	var presets = CharacterRegistry.get_terrorists()
	var preset: Resource = null
	for p in presets:
		if p.id == ENEMY_PRESET_ID:
			preset = p
			break
	if not preset:
		if presets.size() > 0:
			preset = presets[0]
		else:
			return

	var positions: Array[Vector3] = [
		Vector3(8, 0, -3),
		Vector3(-6, 0, 5),
	]
	for i in range(positions.size()):
		var enemy := _create_character(preset, positions[i])
		if enemy:
			enemy.name = "Enemy_%d" % i
			add_child(enemy)
			enemy.setup_vision(VISION_FOV, VISION_RANGE)
			enemy.setup_combat_awareness()
			enemy.combat_awareness.enable_firing()
			_enemies.append(enemy)


# ============================================
# Camera
# ============================================

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "TPSCamera"
	_camera.fov = 30.0
	_camera.current = true
	var char_pos := _character.global_position if _character else Vector3.ZERO
	_camera.position = char_pos + Vector3(0, 8.0, -6.0)
	_camera.rotation_degrees.x = -50.0
	add_child(_camera)


# ============================================
# UI
# ============================================

func _setup_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	add_child(_ui_layer)

	# Weapon selector + sprint toggle (top-left)
	_setup_weapon_selector()
	_setup_sprint_controls()

	# IK adjustment panel (right side)
	_setup_ik_panel()


func _setup_weapon_selector() -> void:
	var weapon_hbox := HBoxContainer.new()
	weapon_hbox.position = Vector2(10, 10)
	_ui_layer.add_child(weapon_hbox)

	var wlabel := Label.new()
	wlabel.text = "Weapon:"
	wlabel.add_theme_font_size_override("font_size", 14)
	weapon_hbox.add_child(wlabel)

	_weapon_option = OptionButton.new()
	_weapon_option.custom_minimum_size.x = 120
	weapon_hbox.add_child(_weapon_option)

	_weapon_list = WeaponRegistry.get_all()
	var default_idx := 0
	for i in range(_weapon_list.size()):
		var w: WeaponPreset = _weapon_list[i]
		_weapon_option.add_item(w.display_name, i)
		if w.id == DEFAULT_WEAPON_ID:
			default_idx = i
	_weapon_option.selected = default_idx
	_weapon_option.item_selected.connect(_on_weapon_selected)


func _setup_sprint_controls() -> void:
	var sprint_hbox := HBoxContainer.new()
	sprint_hbox.position = Vector2(10, 40)
	sprint_hbox.add_theme_constant_override("separation", 12)
	_ui_layer.add_child(sprint_hbox)

	_sprint_check = CheckBox.new()
	_sprint_check.text = "Sprint (Shift)"
	_sprint_check.add_theme_font_size_override("font_size", 14)
	sprint_hbox.add_child(_sprint_check)
	_sprint_check.toggled.connect(func(pressed: bool) -> void:
		if _tps_controller:
			_tps_controller.set_sprinting(pressed)
	)

	_speed_label = Label.new()
	_speed_label.text = "Speed: 0.0 m/s"
	_speed_label.add_theme_font_size_override("font_size", 14)
	_speed_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	sprint_hbox.add_child(_speed_label)


func _update_speed_label() -> void:
	if not _speed_label or not _character or not _character.anim_ctrl:
		return
	var speed := _character.anim_ctrl.get_current_speed()
	var state := "Sprint" if _character.anim_ctrl._is_sprinting else ("Walk" if speed > 0.1 else "Idle")
	_speed_label.text = "%s: %.1f m/s" % [state, speed]


func _setup_ik_panel() -> void:
	# Right side panel
	_ik_panel = PanelContainer.new()
	_ik_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_ik_panel.offset_left = -PANEL_WIDTH
	_ik_panel.offset_top = 0
	_ik_panel.offset_right = 0
	_ik_panel.offset_bottom = 0
	_ui_layer.add_child(_ik_panel)

	var tab_container := TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ik_panel.add_child(tab_container)

	# "IK" tab
	var scroll := ScrollContainer.new()
	scroll.name = "IK"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# --- State selector ---
	_add_section_label(vbox, "State")
	_state_option = OptionButton.new()
	_state_option.add_item("READY", 0)
	_state_option.add_item("GUN_UP", 1)
	_state_option.selected = 0
	_state_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_state_option)
	_state_option.item_selected.connect(_on_state_selected)

	# --- Separator ---
	vbox.add_child(HSeparator.new())

	# --- Left Hand Grip Offset ---
	var lh_result := _create_vector3_sliders(
		vbox, "Left Hand Offset",
		Vector3.ZERO,
		Vector2(-0.1, 0.1),   # X range
		Vector2(-0.1, 0.1),   # Y range
		Vector2(-0.1, 0.1),   # Z range
		_on_lh_offset_changed
	)
	_lh_offset_sliders = lh_result[0]
	_lh_offset_spins = lh_result[1]

	vbox.add_child(HSeparator.new())

	# --- Left Elbow Pole Offset ---
	var lp_result := _create_vector3_sliders(
		vbox, "Left Elbow",
		Vector3(0.3, 0.0, 0.0),
		Vector2(-0.5, 1.0),   # X range
		Vector2(-0.5, 0.5),   # Y range
		Vector2(-0.5, 0.5),   # Z range
		_on_lh_pole_changed
	)
	_lh_pole_sliders = lp_result[0]
	_lh_pole_spins = lp_result[1]

	vbox.add_child(HSeparator.new())

	# --- Copy values button ---
	var copy_btn := Button.new()
	copy_btn.text = "Copy Values"
	copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_btn.pressed.connect(_on_copy_values_pressed)
	vbox.add_child(copy_btn)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	parent.add_child(label)


## Vector3スライダー群を生成。戻り値: [sliders: Array[HSlider], spins: Array[SpinBox]]
func _create_vector3_sliders(
	parent: VBoxContainer,
	label_text: String,
	initial: Vector3,
	x_range: Vector2,
	y_range: Vector2,
	z_range: Vector2,
	callback: Callable
) -> Array:
	_add_section_label(parent, label_text)

	var sliders: Array[HSlider] = []
	var spins: Array[SpinBox] = []
	var axes := ["X", "Y", "Z"]
	var axis_colors := [Color(0.9, 0.2, 0.2), Color(0.2, 0.8, 0.2), Color(0.3, 0.4, 1.0)]
	var ranges := [x_range, y_range, z_range]
	var values := [initial.x, initial.y, initial.z]

	for i in range(3):
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		parent.add_child(hbox)

		var axis_label := Label.new()
		axis_label.text = axes[i]
		axis_label.custom_minimum_size.x = 16
		axis_label.add_theme_font_size_override("font_size", 12)
		axis_label.add_theme_color_override("font_color", axis_colors[i])
		hbox.add_child(axis_label)

		var slider := HSlider.new()
		slider.min_value = ranges[i].x
		slider.max_value = ranges[i].y
		slider.step = 0.001
		slider.value = values[i]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.x = 100
		hbox.add_child(slider)

		var spin := SpinBox.new()
		spin.min_value = ranges[i].x
		spin.max_value = ranges[i].y
		spin.step = 0.001
		spin.value = values[i]
		spin.custom_minimum_size.x = 70
		spin.add_theme_font_size_override("font_size", 11)
		hbox.add_child(spin)

		sliders.append(slider)
		spins.append(spin)

		var axis_idx := i
		_connect_slider_spin(slider, spin, func(v: float) -> void:
			callback.call(axis_idx, v)
		)

	return [sliders, spins]


func _connect_slider_spin(slider: HSlider, spin: SpinBox, callback: Callable) -> void:
	slider.value_changed.connect(func(v: float) -> void:
		spin.set_value_no_signal(v)
		callback.call(v)
	)
	spin.value_changed.connect(func(v: float) -> void:
		slider.set_value_no_signal(v)
		callback.call(v)
	)
	slider.drag_started.connect(func() -> void:
		_slider_drag_count += 1
	)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_slider_drag_count -= 1
	)


# ============================================
# IK Panel Callbacks
# ============================================

func _on_weapon_selected(idx: int) -> void:
	if _character and idx >= 0 and idx < _weapon_list.size():
		_character.equip_weapon(_weapon_list[idx])
		# 武器変更後にスライダーを対応する定数値に更新
		_sync_sliders_to_current_state()


func _on_state_selected(idx: int) -> void:
	var ubik := _get_ubik()
	if not ubik:
		return

	match idx:
		0:  # READY
			ubik.set_state(UpperBodyIKController.IKState.READY)
		1:  # GUN_UP
			ubik.set_state(UpperBodyIKController.IKState.GUN_UP)

	_sync_sliders_to_current_state()


func _on_lh_offset_changed(_axis: int, value: float) -> void:
	var ubik := _get_ubik()
	if not ubik:
		return
	var offset := Vector3(
		_lh_offset_sliders[0].value,
		_lh_offset_sliders[1].value,
		_lh_offset_sliders[2].value
	)
	ubik.set_left_hand_grip_offset(offset)


func _on_lh_pole_changed(_axis: int, value: float) -> void:
	var ubik := _get_ubik()
	if not ubik:
		return
	var offset := Vector3(
		_lh_pole_sliders[0].value,
		_lh_pole_sliders[1].value,
		_lh_pole_sliders[2].value
	)
	ubik.set_left_hand_pole_offset(offset)


## 現在のState/Weaponに応じた定数値でスライダーを更新
func _sync_sliders_to_current_state() -> void:
	var ubik := _get_ubik()
	if not ubik:
		return

	var lh_offset := Vector3.ZERO
	var lh_pole := Vector3(0.3, 0.0, 0.0)

	var state_idx := _state_option.selected if _state_option else 0
	if state_idx != 1 and ubik._weapon_type != 2:  # Rifle READY
		lh_offset = UpperBodyIKController.RIFLE_READY_LH_OFFSET
		lh_pole = UpperBodyIKController.RIFLE_READY_LH_POLE

	_set_slider_values(_lh_offset_sliders, _lh_offset_spins, lh_offset)
	ubik.set_left_hand_grip_offset(lh_offset)
	_set_slider_values(_lh_pole_sliders, _lh_pole_spins, lh_pole)
	ubik.set_left_hand_pole_offset(lh_pole)



func _set_slider_values(sliders: Array[HSlider], spins: Array[SpinBox], vec: Vector3) -> void:
	var vals := [vec.x, vec.y, vec.z]
	for i in range(3):
		sliders[i].set_value_no_signal(vals[i])
		spins[i].set_value_no_signal(vals[i])


func _on_copy_values_pressed() -> void:
	var ubik := _get_ubik()
	var state_name := "GUN_UP" if (_state_option and _state_option.selected == 1) else "READY"
	var weapon_name := "Rifle"
	if ubik and ubik._weapon_type == 2:
		weapon_name = "Pistol"

	var lh_offset := Vector3(
		_lh_offset_sliders[0].value if _lh_offset_sliders.size() > 0 else 0.0,
		_lh_offset_sliders[1].value if _lh_offset_sliders.size() > 1 else 0.0,
		_lh_offset_sliders[2].value if _lh_offset_sliders.size() > 2 else 0.0,
	)
	var lh_pole_val := Vector3(
		_lh_pole_sliders[0].value if _lh_pole_sliders.size() > 0 else 0.3,
		_lh_pole_sliders[1].value if _lh_pole_sliders.size() > 1 else 0.0,
		_lh_pole_sliders[2].value if _lh_pole_sliders.size() > 2 else 0.0,
	)

	var text := "# %s %s\nLH_OFFSET := Vector3(%.3f, %.3f, %.3f)\nLH_POLE := Vector3(%.2f, %.2f, %.2f)" % [
		weapon_name, state_name,
		lh_offset.x, lh_offset.y, lh_offset.z,
		lh_pole_val.x, lh_pole_val.y, lh_pole_val.z,
	]
	DisplayServer.clipboard_set(text)
	print("Copied to clipboard:\n", text)


func _get_ubik() -> UpperBodyIKController:
	if _character and _character.anim_ctrl:
		return _character.anim_ctrl.get_upper_body_ik()
	return null


# ============================================
# Character Factory
# ============================================

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

	# Tポーズ防止: セットアップ完了まで非表示
	model.visible = false

	character.ready.connect(func():
		anim_ctrl.setup(model, anim_player)
		var facing = character.get_facing_direction()
		if facing.length_squared() > 0.001:
			anim_ctrl.set_model_direction(facing)
		# ノードセットアップ完了を待ってから武器装備（add_childエラー防止）
		await character.get_tree().process_frame
		var weapon = WeaponRegistry.get_preset(DEFAULT_WEAPON_ID)
		if weapon:
			character.equip_weapon(weapon)
		# アニメーション適用後にSkeleton3Dオフセットを補正
		await character.get_tree().process_frame
		var skel := _find_skeleton_in(model)
		if skel:
			model.position.y = -skel.position.y
		model.visible = true
		# 全定数値をスライダーとIKに反映
		_sync_sliders_to_current_state()
	, CONNECT_ONE_SHOT)

	return character


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

	# Merge unified locomotion animations (game_idle, game_walk_*, game_sprint etc.)
	if lib and ResourceLoader.exists(ANIMATION_SOURCE_UNIFIED):
		var unified_scene = load(ANIMATION_SOURCE_UNIFIED) as PackedScene
		if unified_scene:
			var unified_instance = unified_scene.instantiate()
			var unified_player = _find_animation_player(unified_instance)
			if unified_player:
				var unified_lib = unified_player.get_animation_library("")
				if unified_lib:
					for anim_name in unified_lib.get_animation_list():
						if lib.has_animation(anim_name):
							lib.remove_animation(anim_name)
						lib.add_animation(anim_name, unified_lib.get_animation(anim_name))
			unified_instance.queue_free()

	return lib


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null


func _find_skeleton_in(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton_in(child)
		if result:
			return result
	return null
