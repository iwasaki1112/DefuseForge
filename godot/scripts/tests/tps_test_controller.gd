extends Node3D
## TPS テストシーン コントローラー
##
## WASD移動 + マウスエイム + バーチャルスティックのテストシーン。
## FoW（視界システム）+ 自動攻撃を統合し、TPS視点で全システムが正常動作することを検証する。
##
## 操作:
## - WASD / 左スティック: 移動
## - マウス: エイム（キャラクターがカーソル方向を向く）（PC）
## - モバイル: 移動方向 = 向き（敵検知時は自動で敵方向を向く）
## - 射撃は完全自動（視界内の敵に対して自動発砲）
## - 画面左上プルダウン: 武器切り替え

# ============================================
# Constants
# ============================================
const CAMERA_HEIGHT := 10.0
const CAMERA_PITCH_DEG := -50.0
const CAMERA_FOV := 30.0
const CAMERA_SMOOTH := 8.0
const GROUND_Y := 0.0
const GROUND_SIZE := 50.0

const CHARACTER_PRESET_ID := "alpha"
const ENEMY_PRESET_ID := "ares"
const DEFAULT_WEAPON_ID := "glock"
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const ANIMATION_SOURCE := "res://assets/animations/character_anims_inplace.glb"

# Vision
const VISION_FOV := 90.0
const VISION_RANGE := 15.0
const MAP_SIZE := Vector2(50.0, 50.0)

# Joystick
const STICK_RADIUS := 80.0
const STICK_KNOB_RADIUS := 30.0
const STICK_DEADZONE := 0.15

# Enemy spawn positions
const ENEMY_POSITIONS: Array[Vector3] = [
	Vector3(8, 0, -3),
	Vector3(-6, 0, 5),
	Vector3(4, 0, 8),
]

# ============================================
# References
# ============================================
var _character: GameCharacter = null
var _enemies: Array[GameCharacter] = []
var _camera: Camera3D = null
var _animation_library: AnimationLibrary = null
var _vision_service: VisionService = null
var _weapon_option: OptionButton = null
var _weapon_list: Array = []
var _debug_vision_btn: Button = null

# Joystick state
var _stick_base: Control = null
var _stick_knob: Control = null
var _stick_touch_idx: int = -1
var _stick_mouse_active: bool = false
var _stick_input: Vector2 = Vector2.ZERO
var _stick_center: Vector2 = Vector2.ZERO

# Movement direction cache (for mobile facing)
var _last_move_dir: Vector3 = Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_environment()
	_create_ground()
	_create_test_walls()
	_animation_library = _load_animation_library()
	PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	_spawn_character()
	_setup_camera()
	_setup_vision_systems()
	_spawn_enemies()
	_register_characters_to_vision()
	_setup_ui()


func _physics_process(delta: float) -> void:
	if not _character or not _character.is_alive:
		return

	_handle_movement(delta)
	_handle_aim(delta)
	if _character.combat_awareness:
		_character.combat_awareness.process(delta)
	_update_camera(delta)


func _input(event: InputEvent) -> void:
	_handle_stick_input(event)


# ============================================
# Setup
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


func _create_test_walls() -> void:
	var wall_data := [
		{ "name": "Wall_0", "pos": Vector3(5, 1.5, 0), "size": Vector3(0.3, 3.0, 6.0) },
		{ "name": "Wall_1", "pos": Vector3(-5, 1.5, 0), "size": Vector3(0.3, 3.0, 6.0) },
		{ "name": "Wall_2", "pos": Vector3(0, 1.5, 5), "size": Vector3(6.0, 3.0, 0.3) },
		{ "name": "Wall_3", "pos": Vector3(0, 1.5, -5), "size": Vector3(6.0, 3.0, 0.3) },
	]
	for data in wall_data:
		var wall := StaticBody3D.new()
		wall.name = data["name"]
		wall.position = data["pos"]

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


func _setup_vision_systems() -> void:
	_vision_service = VisionService.new()
	_vision_service.name = "VisionService"
	add_child(_vision_service)
	_vision_service.setup(MAP_SIZE, true)
	_vision_service.extract_occluders_from_map(self)


func _register_characters_to_vision() -> void:
	# call_deferredで登録（シーンツリーに追加後に実行するため）
	call_deferred("_deferred_register_characters")


func _deferred_register_characters() -> void:
	if _vision_service and _character:
		_vision_service.register_character(_character)
	for enemy in _enemies:
		if _vision_service and is_instance_valid(enemy):
			_vision_service.register_character(enemy)


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
			printerr("TPSTest: No character preset found")
			return

	_character = _create_character(preset, Vector3.ZERO)
	if _character:
		add_child(_character)
		_character.setup_vision(VISION_FOV, VISION_RANGE)
		_character.setup_combat_awareness()
		_character.combat_awareness.enable_firing()


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
			printerr("TPSTest: No enemy preset found")
			return

	for i in range(ENEMY_POSITIONS.size()):
		var enemy := _create_character(preset, ENEMY_POSITIONS[i])
		if enemy:
			enemy.name = "Enemy_%d" % i
			add_child(enemy)
			enemy.setup_vision(VISION_FOV, VISION_RANGE)
			enemy.setup_combat_awareness()
			enemy.combat_awareness.enable_firing()
			_enemies.append(enemy)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "TPSCamera"
	_camera.fov = CAMERA_FOV
	_camera.current = true

	var char_pos := _character.global_position if _character else Vector3.ZERO
	var pitch_rad := deg_to_rad(CAMERA_PITCH_DEG)
	var offset_z := CAMERA_HEIGHT / tan(-pitch_rad)
	_camera.position = char_pos + Vector3(0, CAMERA_HEIGHT, offset_z)
	_camera.rotation_degrees.x = CAMERA_PITCH_DEG

	add_child(_camera)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	# Weapon selector (top-left)
	var hbox := HBoxContainer.new()
	hbox.position = Vector2(10, 10)
	canvas.add_child(hbox)

	var label := Label.new()
	label.text = "Weapon: "
	hbox.add_child(label)

	_weapon_option = OptionButton.new()
	_weapon_option.custom_minimum_size.x = 160
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

	# Virtual joystick (bottom-left)
	_create_joystick(canvas)

	# Action buttons (right side)
	_create_action_buttons(canvas)


func _create_action_buttons(canvas: CanvasLayer) -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "ActionButtons"
	vbox.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vbox.position = Vector2(-170, -80)
	vbox.add_theme_constant_override("separation", 12)
	canvas.add_child(vbox)

	var btn_grenade := Button.new()
	btn_grenade.text = "Grenade"
	btn_grenade.custom_minimum_size = Vector2(150, 50)
	btn_grenade.pressed.connect(_on_grenade_pressed)
	vbox.add_child(btn_grenade)

	var btn_door_kick := Button.new()
	btn_door_kick.text = "Door Kick"
	btn_door_kick.custom_minimum_size = Vector2(150, 50)
	btn_door_kick.pressed.connect(_on_door_kick_pressed)
	vbox.add_child(btn_door_kick)

	var btn_door_open := Button.new()
	btn_door_open.text = "Door Open"
	btn_door_open.custom_minimum_size = Vector2(150, 50)
	btn_door_open.pressed.connect(_on_door_open_pressed)
	vbox.add_child(btn_door_open)

	_debug_vision_btn = Button.new()
	_debug_vision_btn.text = "Debug Vision"
	_debug_vision_btn.toggle_mode = true
	_debug_vision_btn.custom_minimum_size = Vector2(150, 50)
	_debug_vision_btn.toggled.connect(_on_debug_vision_toggled)
	vbox.add_child(_debug_vision_btn)


func _on_debug_vision_toggled(enabled: bool) -> void:
	if _vision_service:
		_vision_service.set_debug_draw(enabled)


func _on_grenade_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_throw()


func _on_door_kick_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_door_kick()


func _on_door_open_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_door_open()


func _create_joystick(canvas: CanvasLayer) -> void:
	var margin := 40.0
	var base_size := STICK_RADIUS * 2

	# Base circle (outer ring)
	_stick_base = Control.new()
	_stick_base.name = "StickBase"
	_stick_base.custom_minimum_size = Vector2(base_size, base_size)
	_stick_base.size = Vector2(base_size, base_size)
	_stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.position = Vector2(margin, -margin - base_size)
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_stick_base)

	# Draw base circle
	var base_draw := ColorRect.new()
	base_draw.name = "BaseBG"
	base_draw.size = Vector2(base_size, base_size)
	base_draw.color = Color(1, 1, 1, 0.0)
	base_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(base_draw)

	# Use a custom draw for circles
	var base_circle := _create_circle_control(STICK_RADIUS, Color(0.5, 0.5, 0.5, 0.3))
	base_circle.position = Vector2(STICK_RADIUS, STICK_RADIUS)
	base_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(base_circle)

	# Knob (inner circle)
	_stick_knob = _create_circle_control(STICK_KNOB_RADIUS, Color(0.8, 0.8, 0.8, 0.6))
	_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(_stick_knob)

	_stick_center = _stick_base.global_position + Vector2(STICK_RADIUS, STICK_RADIUS)


func _create_circle_control(radius: float, color: Color) -> Control:
	var ctrl := Control.new()
	ctrl.custom_minimum_size = Vector2(radius * 2, radius * 2)
	ctrl.size = Vector2(radius * 2, radius * 2)
	ctrl.pivot_offset = Vector2(radius, radius)
	ctrl.draw.connect(func():
		ctrl.draw_circle(Vector2.ZERO, radius, color)
	)
	return ctrl


func _on_weapon_selected(idx: int) -> void:
	if not _character or idx < 0 or idx >= _weapon_list.size():
		return
	var weapon: WeaponPreset = _weapon_list[idx]
	_character.equip_weapon(weapon)


# ============================================
# Joystick Input
# ============================================

func _is_in_stick_area(pos: Vector2) -> bool:
	_stick_center = _stick_base.global_position + Vector2(STICK_RADIUS, STICK_RADIUS)
	return pos.distance_to(_stick_center) <= STICK_RADIUS * 1.5


func _handle_stick_input(event: InputEvent) -> void:
	# Touch input (mobile)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _stick_touch_idx < 0 and touch.position.x < get_viewport().get_visible_rect().size.x * 0.5:
				_stick_touch_idx = touch.index
				_stick_center = _stick_base.global_position + Vector2(STICK_RADIUS, STICK_RADIUS)
				_update_stick_position(touch.position)
		else:
			if touch.index == _stick_touch_idx:
				_release_stick()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_touch_idx:
			_update_stick_position(drag.position)

	# Mouse input (PC)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _is_in_stick_area(mb.position):
				_stick_mouse_active = true
				_update_stick_position(mb.position)
			elif not mb.pressed and _stick_mouse_active:
				_stick_mouse_active = false
				_release_stick()

	elif event is InputEventMouseMotion:
		if _stick_mouse_active:
			_update_stick_position(event.position)


func _release_stick() -> void:
	_stick_touch_idx = -1
	_stick_input = Vector2.ZERO
	_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS)


func _update_stick_position(touch_pos: Vector2) -> void:
	var offset := touch_pos - _stick_center
	var dist := offset.length()

	if dist > STICK_RADIUS:
		offset = offset.normalized() * STICK_RADIUS

	# Update knob visual position
	_stick_knob.position = Vector2(STICK_RADIUS, STICK_RADIUS) + offset

	# Calculate normalized input (-1 to 1)
	var normalized := offset / STICK_RADIUS
	if normalized.length() < STICK_DEADZONE:
		_stick_input = Vector2.ZERO
	else:
		_stick_input = normalized


# ============================================
# Input Handling
# ============================================

func _handle_movement(delta: float) -> void:
	# WASD input
	var input_dir := Vector2.ZERO
	input_dir.y -= Input.get_action_strength("move_forward")
	input_dir.y += Input.get_action_strength("move_backward")
	input_dir.x -= Input.get_action_strength("move_left")
	input_dir.x += Input.get_action_strength("move_right")

	# Combine with joystick (stick X = left/right, stick Y = up/down on screen)
	input_dir.x += _stick_input.x
	input_dir.y += _stick_input.y

	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var move_dir := Vector3.ZERO
	if input_dir.length() > 0.01:
		input_dir = input_dir.normalized()
		move_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()

	# Cache move direction for mobile facing
	_last_move_dir = move_dir

	var speed := _character.anim_ctrl.get_current_speed() if _character.anim_ctrl else 2.0
	_character.velocity = move_dir * speed
	_character.move_and_slide()

	if _character.anim_ctrl:
		var aim_dir := _character.get_facing_direction()
		_character.anim_ctrl.update_animation(move_dir, aim_dir, false, delta)


func _handle_aim(_delta: float) -> void:
	# 1. CombatAwareness override — 敵検知時は自動で敵方向を向く
	if _character.combat_awareness:
		var override_dir := _character.combat_awareness.get_override_look_direction()
		if override_dir != Vector3.ZERO:
			_character.set_facing_direction_vec(override_dir)
			return

	# 2. PC: マウスエイム（ジョイスティック非アクティブ時のみ）
	if _camera and _stick_input.length() <= 0.01:
		var mouse_pos := get_viewport().get_mouse_position()
		var ray_origin := _camera.project_ray_origin(mouse_pos)
		var ray_normal := _camera.project_ray_normal(mouse_pos)

		if absf(ray_normal.y) > 0.001:
			var t := (GROUND_Y - ray_origin.y) / ray_normal.y
			if t > 0:
				var ground_point := ray_origin + ray_normal * t
				var aim_dir := ground_point - _character.global_position
				aim_dir.y = 0
				if aim_dir.length_squared() > 0.01:
					_character.set_facing_direction_vec(aim_dir.normalized())
				return

	# 3. モバイル: 移動方向 = 向き
	if _last_move_dir.length_squared() > 0.01:
		_character.set_facing_direction_vec(_last_move_dir)


func _update_camera(delta: float) -> void:
	if not _character or not _camera:
		return
	var pitch_rad := deg_to_rad(CAMERA_PITCH_DEG)
	var offset_z := CAMERA_HEIGHT / tan(-pitch_rad)
	var target := _character.global_position + Vector3(0, CAMERA_HEIGHT, offset_z)
	_camera.global_position = _camera.global_position.lerp(target, CAMERA_SMOOTH * delta)


# ============================================
# Character Factory (lighting_test.gd pattern)
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
		var facing = character.get_facing_direction()
		if facing.length_squared() > 0.001:
			anim_ctrl.set_model_direction(facing)
		var weapon = WeaponRegistry.get_preset(DEFAULT_WEAPON_ID)
		if weapon:
			character.equip_weapon(weapon)
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
	return lib


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null
