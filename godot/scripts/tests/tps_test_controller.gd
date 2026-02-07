extends Node3D
## TPS テストシーン コントローラー
##
## WASD移動 + マウスエイムのテストシーン。
## TPSゲームへの移行に向けた検証用。
##
## 操作:
## - WASD: 移動
## - マウス: エイム（キャラクターがカーソル方向を向く）
## - 左クリック: 射撃
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
const DEFAULT_WEAPON_ID := "glock"
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const ANIMATION_SOURCE := "res://assets/animations/character_anims.glb"

# ============================================
# References
# ============================================
var _character: GameCharacter = null
var _camera: Camera3D = null
var _animation_library: AnimationLibrary = null
var _weapon_option: OptionButton = null
var _weapon_list: Array = []  # WeaponPreset array


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_environment()
	_create_ground()
	_animation_library = _load_animation_library()
	_spawn_character()
	_setup_camera()
	_setup_ui()


func _physics_process(delta: float) -> void:
	if not _character or not _character.is_alive:
		return

	_handle_movement(delta)
	_handle_aim()
	_handle_fire()
	_update_camera(delta)


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

	var hbox := HBoxContainer.new()
	hbox.position = Vector2(10, 10)
	canvas.add_child(hbox)

	var label := Label.new()
	label.text = "Weapon: "
	hbox.add_child(label)

	_weapon_option = OptionButton.new()
	_weapon_option.custom_minimum_size.x = 160
	hbox.add_child(_weapon_option)

	# Populate weapon list
	_weapon_list = WeaponRegistry.get_all()
	var default_idx := 0
	for i in range(_weapon_list.size()):
		var w: WeaponPreset = _weapon_list[i]
		_weapon_option.add_item(w.display_name, i)
		if w.id == DEFAULT_WEAPON_ID:
			default_idx = i
	_weapon_option.selected = default_idx
	_weapon_option.item_selected.connect(_on_weapon_selected)


func _on_weapon_selected(idx: int) -> void:
	if not _character or idx < 0 or idx >= _weapon_list.size():
		return
	var weapon: WeaponPreset = _weapon_list[idx]
	_character.equip_weapon(weapon)


# ============================================
# Input Handling
# ============================================

func _handle_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.y -= Input.get_action_strength("move_forward")
	input_dir.y += Input.get_action_strength("move_backward")
	input_dir.x -= Input.get_action_strength("move_left")
	input_dir.x += Input.get_action_strength("move_right")

	var move_dir := Vector3.ZERO
	if input_dir.length() > 0.01:
		input_dir = input_dir.normalized()
		move_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()

	var speed := _character.anim_ctrl.get_current_speed() if _character.anim_ctrl else 2.0
	_character.velocity = move_dir * speed
	_character.move_and_slide()

	if _character.anim_ctrl:
		var aim_dir := _character.get_facing_direction()
		_character.anim_ctrl.update_animation(move_dir, aim_dir, false, delta)


func _handle_aim() -> void:
	if not _camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_normal := _camera.project_ray_normal(mouse_pos)

	if absf(ray_normal.y) < 0.001:
		return
	var t := (GROUND_Y - ray_origin.y) / ray_normal.y
	if t < 0:
		return
	var ground_point := ray_origin + ray_normal * t

	var aim_dir := ground_point - _character.global_position
	aim_dir.y = 0
	if aim_dir.length_squared() > 0.01:
		_character.set_facing_direction_vec(aim_dir.normalized())


func _handle_fire() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _character.anim_ctrl:
			_character.anim_ctrl.fire()


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
