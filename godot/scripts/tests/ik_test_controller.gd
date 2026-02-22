extends Node3D
## IK Animation System テストコントローラー
##
## 上半身IKシステム（UpperBodyIKController）の動作確認用テストシーン。
## 各IK状態とアクションをボタンで切り替えてテストする。
##
## テスト項目:
## - 基本動作: 移動/スプリント/アイドルの下半身アニメーション
## - 上半身IK: 右手武器位置固定、左手グリップ追従
## - エイム: 頭部と背骨のエイム方向追従
## - GunUp: 壁接近時のIKターゲット上昇
## - 射撃リコイル: IKターゲットベースの跳ね上がり復帰
## - アクション: 投擲/ドア開け/近接（AnimationPlayer全身再生→IK復帰）
## - 死亡: IK無効化→全身死亡アニメーション

# ============================================
# Constants
# ============================================
const GROUND_SIZE := 50.0
const CHARACTER_PRESET_ID := "dummy_ct"
const ENEMY_PRESET_ID := "ares"
const DEFAULT_WEAPON_ID := "glock"
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const ANIMATION_SOURCE := "res://assets/animations/character_anims_kubold.glb"
const ANIMATION_SOURCE_UNIFIED := "res://assets/animations/animations.glb"
const VISION_FOV := 75.0
const VISION_RANGE := 7.0
const MAP_SIZE := Vector2(50.0, 50.0)

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
var _status_label: Label = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_environment()
	_create_ground()
	_animation_library = _load_animation_library()
	PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	_spawn_character()
	_setup_camera()
	_setup_ui()
	_setup_tps_controller()


func _physics_process(delta: float) -> void:
	if _tps_controller:
		_tps_controller.process(delta)
	_update_status_label()


func _input(event: InputEvent) -> void:
	if _tps_controller:
		_tps_controller.handle_input(event)


# ============================================
# Status Display
# ============================================

func _update_status_label() -> void:
	if not _status_label or not _character or not _character.anim_ctrl:
		return

	var ctrl := _character.anim_ctrl
	var ubik := ctrl.get_upper_body_ik()

	var lines: PackedStringArray = []
	lines.append("=== IK Animation System Test ===")
	lines.append("")

	# AnimationTree state
	lines.append("[AnimationTree]")
	lines.append("  Active: %s" % str(ctrl._anim_tree.active if ctrl._anim_tree else "N/A"))
	lines.append("  Movement: %.2f  Sprint: %s" % [ctrl._movement_blend, str(ctrl._is_sprinting)])
	lines.append("  Weapon: %s" % ["NONE", "RIFLE", "PISTOL"][ctrl._weapon])

	lines.append("")
	lines.append("[Upper Body IK]")
	if ubik:
		var state_names := ["READY", "GUN_UP", "ACTION", "DISABLED"]
		lines.append("  State: %s" % state_names[ubik._state])
		lines.append("  Right Arm Influence: %.2f" % ubik.get_right_arm_influence())
		lines.append("  Hand Pos: (%.3f, %.3f, %.3f)" % [ubik._current_hand_pos.x, ubik._current_hand_pos.y, ubik._current_hand_pos.z])
		if ubik._recoil_ctrl:
			var r := ubik._recoil_ctrl.get_recoil_offset()
			lines.append("  Recoil: (%.3f, %.3f, %.3f)" % [r.x, r.y, r.z])
		var left_ik := ubik.get_left_hand_ik()
		if left_ik:
			lines.append("  Left IK: %s (grip: %s)" % [str(left_ik.is_enabled()), str(left_ik.has_grip_source())])
	else:
		lines.append("  NOT SETUP")

	lines.append("")
	lines.append("[Action State]")
	lines.append("  Dead: %s" % str(ctrl._is_dead))
	lines.append("  Throwing: %s" % str(ctrl._is_throwing))
	lines.append("  Door: %s" % str(ctrl._is_opening_door))
	lines.append("  Melee: %s" % str(ctrl._is_meleeing))
	lines.append("  Talking: %s" % str(ctrl._is_talking))
	lines.append("  GunDown: %s" % str(ctrl._is_gun_down))

	_status_label.text = "\n".join(lines)


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

	# Status label (top-left)
	_status_label = Label.new()
	_status_label.position = Vector2(10, 10)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	_status_label.text = "Loading..."
	_ui_layer.add_child(_status_label)

	# Action buttons (right side)
	var vbox := VBoxContainer.new()
	vbox.name = "ActionButtons"
	vbox.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vbox.position = Vector2(-170, -150)
	vbox.add_theme_constant_override("separation", 8)
	_ui_layer.add_child(vbox)

	# Weapon selector
	var weapon_hbox := HBoxContainer.new()
	vbox.add_child(weapon_hbox)
	var wlabel := Label.new()
	wlabel.text = "Weapon:"
	weapon_hbox.add_child(wlabel)
	var weapon_option := OptionButton.new()
	weapon_option.custom_minimum_size.x = 120
	weapon_hbox.add_child(weapon_option)
	var weapon_list = WeaponRegistry.get_all()
	var default_idx := 0
	for i in range(weapon_list.size()):
		var w: WeaponPreset = weapon_list[i]
		weapon_option.add_item(w.display_name, i)
		if w.id == DEFAULT_WEAPON_ID:
			default_idx = i
	weapon_option.selected = default_idx
	weapon_option.item_selected.connect(func(idx: int) -> void:
		if _character and idx >= 0 and idx < weapon_list.size():
			_character.equip_weapon(weapon_list[idx])
	)

	_add_action_button(vbox, "Fire", _on_fire_pressed)
	_add_action_button(vbox, "Grenade (Far)", _on_grenade_far_pressed)
	_add_action_button(vbox, "Grenade (Close)", _on_grenade_close_pressed)
	_add_action_button(vbox, "Door Open", _on_door_open_pressed)
	_add_action_button(vbox, "Melee", _on_melee_pressed)
	_add_action_button(vbox, "Talk", _on_talk_pressed)
	_add_action_button(vbox, "Stop Talk", _on_stop_talk_pressed)
	_add_action_button(vbox, "Die (Front)", _on_die_pressed)
	_add_action_button(vbox, "Debug Vision", _on_debug_vision_pressed, true)


func _add_action_button(parent: Control, text: String, callback: Callable, toggle: bool = false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 40)
	if toggle:
		btn.toggle_mode = true
		btn.toggled.connect(callback)
	else:
		btn.pressed.connect(callback)
	parent.add_child(btn)


# ============================================
# Action Callbacks
# ============================================

func _on_fire_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.fire()


func _on_grenade_far_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_throw_far()


func _on_grenade_close_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_throw_close()


func _on_door_open_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_door_open()


func _on_melee_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_melee()


func _on_talk_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_talking()


func _on_stop_talk_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.stop_talking()


func _on_die_pressed() -> void:
	if _character and _character.anim_ctrl:
		_character.anim_ctrl.play_death(CharacterAnimationController.HitDirection.FRONT)


func _on_debug_vision_pressed(enabled: bool) -> void:
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
		var weapon = WeaponRegistry.get_preset(DEFAULT_WEAPON_ID)
		if weapon:
			character.equip_weapon(weapon)
		# アニメーション適用後にSkeleton3Dオフセットを補正
		await character.get_tree().process_frame
		var skel := _find_skeleton_in(model)
		if skel:
			model.position.y = -skel.position.y
		model.visible = true
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
