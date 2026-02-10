extends Node3D
## TPS テストシーン コントローラー
##
## TPSPlayerControllerを使用したテスト環境。
## テスト用のシーン構築（地面、壁、敵、視界）を行い、
## 操作ロジックはTPSPlayerControllerに委譲する。
##
## 操作:
## - WASD / 左スティック: 移動
## - マウス / 右スティック: エイム（キャラクターがカーソル方向を向く）
## - 射撃は完全自動（視界内の敵に対して自動発砲）
## - 画面左上プルダウン: 武器切り替え

# ============================================
# Constants
# ============================================
const GROUND_SIZE := 50.0

const CHARACTER_PRESET_ID := "alpha"
const ENEMY_PRESET_ID := "ares"
const DEFAULT_WEAPON_ID := "glock"
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const ANIMATION_SOURCE := "res://assets/animations/character_anims_inplace.glb"

# Vision
const VISION_FOV := 75.0
const VISION_RANGE := 7.0
const MAP_SIZE := Vector2(50.0, 50.0)

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
var _tps_controller: TPSPlayerController = null
var _animation_library: AnimationLibrary = null
var _vision_service: VisionService = null
var _ui_layer: CanvasLayer = null

# UI elements
var _weapon_option: OptionButton = null
var _weapon_list: Array = []


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
	_setup_tps_controller()


func _physics_process(delta: float) -> void:
	if _tps_controller:
		_tps_controller.process(delta)


func _input(event: InputEvent) -> void:
	if _tps_controller:
		_tps_controller.handle_input(event)


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
		"camera_height": 10.0,
		"camera_pitch_deg": -50.0,
		"enable_aim_stick": true,
	})


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


# ============================================
# Camera
# ============================================

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "TPSCamera"
	_camera.fov = 30.0
	_camera.current = true

	var char_pos := _character.global_position if _character else Vector3.ZERO
	var pitch_rad := deg_to_rad(-50.0)
	var offset_z := 10.0 / tan(-pitch_rad)
	_camera.position = char_pos + Vector3(0, 10.0, offset_z)
	_camera.rotation_degrees.x = -50.0

	add_child(_camera)


# ============================================
# UI
# ============================================

func _setup_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	add_child(_ui_layer)

	# Weapon selector (top-left)
	var hbox := HBoxContainer.new()
	hbox.position = Vector2(10, 10)
	_ui_layer.add_child(hbox)

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

	# Action buttons (right side)
	_create_action_buttons()


func _create_action_buttons() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "ActionButtons"
	vbox.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vbox.position = Vector2(-170, -80)
	vbox.add_theme_constant_override("separation", 12)
	_ui_layer.add_child(vbox)

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

	var btn_vision := Button.new()
	btn_vision.text = "Debug Vision"
	btn_vision.toggle_mode = true
	btn_vision.custom_minimum_size = Vector2(150, 50)
	btn_vision.toggled.connect(_on_debug_vision_toggled)
	vbox.add_child(btn_vision)


# ============================================
# UI Callbacks
# ============================================

func _on_weapon_selected(idx: int) -> void:
	if not _character or idx < 0 or idx >= _weapon_list.size():
		return
	var weapon: WeaponPreset = _weapon_list[idx]
	_character.equip_weapon(weapon)


func _on_grenade_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_throw()


func _on_door_kick_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_door_kick()


func _on_door_open_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_door_open()


func _on_debug_vision_toggled(enabled: bool) -> void:
	if _vision_service:
		_vision_service.set_debug_draw(enabled)


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

	# コリジョンマスク設定（Layer 1:床 + Layer 2:壁 に衝突する）
	character.collision_mask = 3

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
