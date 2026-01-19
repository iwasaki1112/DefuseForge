extends Node3D
## Test scene for character selection
## Debug tool to test different characters from CharacterRegistry
## Features:
## - マウスクリックでキャラクター選択
## - 右クリックでコンテキストメニュー表示
## - ドロップダウンからキャラクター追加

const AnimCtrl = preload("res://scripts/animation/character_animation_controller.gd")

## UI参照
@onready var camera: Camera3D = $Camera3D
@onready var character_dropdown: OptionButton = $UI/CharacterDropdown
@onready var weapon_dropdown: OptionButton = $UI/WeaponDropdown
@onready var info_label: Label = $UI/InfoLabel
@onready var ui_layer: CanvasLayer = $UI
@onready var manual_control_button: Button = $UI/ControlPanel/ManualControlButton
@onready var vision_toggle_button: Button = $UI/ControlPanel/VisionToggleButton
@onready var rotate_panel: VBoxContainer = $UI/RotatePanel
@onready var rotate_confirm_button: Button = $UI/RotatePanel/RotateConfirmButton
@onready var rotate_cancel_button: Button = $UI/RotatePanel/RotateCancelButton
@onready var pending_paths_label: Label = $UI/ControlPanel/PendingPathsLabel
@onready var execute_walk_button: Button = $UI/ControlPanel/ExecuteWalkButton
@onready var clear_paths_button: Button = $UI/ControlPanel/ClearPathsButton

## コアゲームシステムマネージャー
var game_manager: GameManager = null

## デバッグ操作モード
var is_debug_control_enabled: bool = false
var aim_position := Vector3.ZERO
var _ground_plane := Plane(Vector3.UP, 0)


func _ready() -> void:
	_setup_game_manager()
	_setup_control_buttons()
	_populate_dropdown()
	_populate_weapon_dropdown()
	character_dropdown.item_selected.connect(_on_team_selected)
	weapon_dropdown.item_selected.connect(_on_weapon_selected)

	# 初期キャラクターを生成
	_spawn_initial_characters()

	# 初期視界状態を適用
	game_manager.set_vision_enabled(false)


## GameManagerのセットアップ
func _setup_game_manager() -> void:
	game_manager = GameManager.new()
	game_manager.name = "GameManager"
	add_child(game_manager)
	game_manager.setup(camera, self, ui_layer, Vector2(50, 50))

	# GameManagerのシグナルを接続
	game_manager.selection_changed.connect(_on_selection_changed)
	game_manager.primary_changed.connect(_on_primary_changed)
	game_manager.path_mode_started.connect(_on_path_mode_started)
	game_manager.path_mode_ended.connect(_on_path_mode_ended)
	game_manager.path_mode_cancelled.connect(_on_path_mode_cancelled)
	game_manager.path_ready.connect(_on_path_ready)
	game_manager.path_confirmed.connect(_on_path_confirmed)
	game_manager.all_paths_completed.connect(_on_all_paths_completed)
	game_manager.paths_cleared.connect(_on_paths_cleared)
	game_manager.rotation_confirmed.connect(_on_rotation_confirmed)
	game_manager.rotation_cancelled.connect(_on_rotation_cancelled)
	game_manager.path_mode_changed.connect(_on_path_mode_changed)


func _setup_control_buttons() -> void:
	manual_control_button.pressed.connect(_on_manual_control_button_pressed)
	_update_manual_control_button()

	vision_toggle_button.pressed.connect(_on_vision_toggle_button_pressed)
	_update_vision_toggle_button()

	execute_walk_button.pressed.connect(_on_execute_walk_button_pressed)
	clear_paths_button.pressed.connect(_on_clear_paths_button_pressed)
	_update_pending_paths_label()

	rotate_confirm_button.pressed.connect(_on_rotate_confirm_pressed)
	rotate_cancel_button.pressed.connect(_on_rotate_cancel_pressed)

	rotate_panel.visible = false


## ========================================
## デバッグボタンコールバック
## ========================================

func _on_manual_control_button_pressed() -> void:
	is_debug_control_enabled = not is_debug_control_enabled
	_update_manual_control_button()
	_update_selection_info()
	print("[Debug] Manual control: %s" % ("ON" if is_debug_control_enabled else "OFF"))


func _update_manual_control_button() -> void:
	if manual_control_button:
		manual_control_button.text = "Manual Control: %s" % ("ON" if is_debug_control_enabled else "OFF")


func _on_vision_toggle_button_pressed() -> void:
	game_manager.set_vision_enabled(not game_manager.is_vision_enabled)
	_update_vision_toggle_button()
	print("[Debug] Vision/FoW: %s" % ("ON" if game_manager.is_vision_enabled else "OFF"))


func _update_vision_toggle_button() -> void:
	if vision_toggle_button:
		vision_toggle_button.text = "Vision/FoW: %s" % ("ON" if game_manager.is_vision_enabled else "OFF")


func _on_execute_walk_button_pressed() -> void:
	var count = game_manager.execute_all_paths(false)
	if count > 0:
		_update_mode_info("Executing %d paths..." % count)


func _on_clear_paths_button_pressed() -> void:
	game_manager.clear_all_pending_paths()


func _on_rotate_confirm_pressed() -> void:
	game_manager.confirm_rotation()


func _on_rotate_cancel_pressed() -> void:
	game_manager.cancel_rotation()


## ========================================
## GameManagerシグナルコールバック
## ========================================

func _on_selection_changed(_selected: Array[Node], _primary: Node) -> void:
	_update_selection_info()


func _on_primary_changed(_character: Node) -> void:
	pass


func _on_path_confirmed(_count: int) -> void:
	_update_pending_paths_label()


func _on_all_paths_completed() -> void:
	_update_mode_info("")
	_update_pending_paths_label()


func _on_paths_cleared() -> void:
	_update_pending_paths_label()


func _on_path_mode_started(_character: Node) -> void:
	var target_count = game_manager.get_path_target_count()
	if target_count == 1:
		_update_mode_info("Path Mode: Draw path (ESC to cancel)")
	else:
		_update_mode_info("Path Mode: Draw path for %d characters (ESC to cancel)" % target_count)


func _on_path_mode_ended() -> void:
	_update_mode_info("")


func _on_path_mode_cancelled() -> void:
	_update_mode_info("")


func _on_path_ready() -> void:
	_update_mode_info("Vision Mode: Click on path to set look direction")


func _on_rotation_confirmed(_final_direction: Vector3) -> void:
	rotate_panel.visible = false
	_update_mode_info("")
	print("[RotateMode] Confirmed")


func _on_rotation_cancelled() -> void:
	rotate_panel.visible = false
	_update_mode_info("")
	print("[RotateMode] Cancelled")


func _on_path_mode_changed(mode: int) -> void:
	if mode == 0:  # MOVEMENT
		_update_mode_info("Path Mode: Draw path")
	else:  # VISION_POINT
		var count = game_manager.get_vision_point_count()
		_update_mode_info("Vision Mode: %d vision points" % count)


## ========================================
## ドロップダウン
## ========================================

func _populate_dropdown() -> void:
	character_dropdown.clear()
	character_dropdown.add_item("CT (Counter-Terrorist)")
	character_dropdown.set_item_metadata(0, GameCharacter.Team.COUNTER_TERRORIST)
	character_dropdown.add_item("T (Terrorist)")
	character_dropdown.set_item_metadata(1, GameCharacter.Team.TERRORIST)
	character_dropdown.select(0)


func _populate_weapon_dropdown() -> void:
	weapon_dropdown.clear()
	var all_weapons = WeaponRegistry.get_all()
	for i in range(all_weapons.size()):
		var weapon = all_weapons[i]
		weapon_dropdown.add_item(weapon.display_name)
		weapon_dropdown.set_item_metadata(i, weapon.id)
	for i in range(all_weapons.size()):
		if all_weapons[i].id == "glock":
			weapon_dropdown.select(i)
			break


func _on_weapon_selected(index: int) -> void:
	var weapon_id: String = weapon_dropdown.get_item_metadata(index)
	var weapon = WeaponRegistry.get_preset(weapon_id)
	if not weapon:
		return

	for character in game_manager.characters:
		if character.has_method("equip_weapon"):
			character.equip_weapon(weapon)

	print("[Weapon] Equipped %s to all characters" % weapon.display_name)


func _on_team_selected(index: int) -> void:
	var new_team: GameCharacter.Team = character_dropdown.get_item_metadata(index)
	PlayerState.set_player_team(new_team)
	game_manager.selection_manager.deselect_all()
	game_manager.refresh_character_colors()
	_update_selection_info()


## ========================================
## キャラクター生成
## ========================================

func _spawn_initial_characters() -> void:
	var cts = CharacterRegistry.get_counter_terrorists()
	var ts = CharacterRegistry.get_terrorists()

	# CT 2体を生成
	if cts.size() >= 1:
		var ct1 = CharacterRegistry.create_character(cts[0].id, Vector3(-3, 0, -2))
		if ct1:
			add_child(ct1)
			game_manager.register_character(ct1)
			print("[Test] Spawned CT 1: %s at (-3, 0, -2)" % cts[0].display_name)

		var ct_index = 1 if cts.size() > 1 else 0
		var ct2 = CharacterRegistry.create_character(cts[ct_index].id, Vector3(-3, 0, 2))
		if ct2:
			add_child(ct2)
			game_manager.register_character(ct2)
			print("[Test] Spawned CT 2: %s at (-3, 0, 2)" % cts[ct_index].display_name)

	# T 2体を生成
	if ts.size() >= 1:
		var t1 = CharacterRegistry.create_character(ts[0].id, Vector3(3, 0, -2))
		if t1:
			add_child(t1)
			game_manager.register_character(t1)
			print("[Test] Spawned T 1: %s at (3, 0, -2)" % ts[0].display_name)

		var t_index = 1 if ts.size() > 1 else 0
		var t2 = CharacterRegistry.create_character(ts[t_index].id, Vector3(3, 0, 2))
		if t2:
			add_child(t2)
			game_manager.register_character(t2)
			print("[Test] Spawned T 2: %s at (3, 0, 2)" % ts[t_index].display_name)

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)


## ========================================
## 入力処理
## ========================================

func _unhandled_input(event: InputEvent) -> void:
	# 回転モード中
	if game_manager.is_rotation_active() and event is InputEventMouseButton and event.pressed:
		game_manager.handle_rotation_input(event.position)
		return

	# パスモード中：パス描画後にキャラクター以外をクリックでキャンセル
	if game_manager.is_path_mode() and event is InputEventMouseButton and event.pressed:
		if game_manager.has_pending_path():
			var clicked = game_manager.raycast_character(event.position)
			game_manager.path_mode_controller.handle_click_to_cancel(clicked)
		return

	# 通常クリック処理
	if event is InputEventMouseButton and event.pressed:
		if not game_manager.is_rotation_active() and not game_manager.is_path_mode():
			game_manager.handle_click(event.position, event.button_index)


func _input(event: InputEvent) -> void:
	# ESCキー処理
	if event.is_action_pressed("ui_cancel"):
		if game_manager.is_any_path_following_active():
			game_manager.cancel_all_path_following()
			_update_mode_info("")
		elif game_manager.is_rotation_active():
			_on_rotate_cancel_pressed()

	var primary = game_manager.get_primary_character()
	if not primary:
		return

	var anim_ctrl = primary.get_anim_controller()
	if not anim_ctrl:
		return

	# キーボード入力（デバッグ用）
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)
			KEY_2:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
			KEY_K:
				primary.take_damage(primary.max_health)
			KEY_R:
				if primary.has_method("reset_health"):
					primary.reset_health()


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	game_manager.process_frame(delta)

	if game_manager.is_rotation_active():
		return

	var primary = game_manager.get_primary_character()
	if not primary or not primary.is_alive:
		return

	if game_manager.is_character_following_path(primary):
		return

	var anim_ctrl = primary.get_anim_controller()
	if not anim_ctrl:
		return

	# デバッグ操作が有効な場合のみエイム更新
	if is_debug_control_enabled:
		_update_aim_position()

	# パスモード中は向きを維持
	if game_manager.is_path_mode():
		var look_dir = anim_ctrl.get_look_direction()
		anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)
		return

	# デバッグ操作が無効な場合はアイドル処理
	if not is_debug_control_enabled:
		game_manager.idle_manager.process_primary_idle(primary, delta)
		return

	# WASD操作
	var move_dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var aim_dir: Vector3 = aim_position - primary.global_position
	aim_dir.y = 0
	var is_running := Input.is_key_pressed(KEY_SHIFT)

	anim_ctrl.update_animation(move_dir, aim_dir, is_running, delta)
	anim_ctrl.set_stance(
		AnimCtrl.Stance.CROUCH if Input.is_key_pressed(KEY_C) else AnimCtrl.Stance.STAND
	)

	if Input.is_key_pressed(KEY_SPACE):
		anim_ctrl.fire()

	var speed: float = anim_ctrl.get_current_speed()
	if move_dir.length() > 0.1:
		primary.velocity.x = move_dir.normalized().x * speed
		primary.velocity.z = move_dir.normalized().z * speed
	else:
		primary.velocity.x = 0
		primary.velocity.z = 0

	if not primary.is_on_floor():
		primary.velocity.y -= 9.8 * delta

	primary.move_and_slide()


func _update_aim_position() -> void:
	if not camera:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var intersection = _ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		aim_position = intersection


## ========================================
## UI更新
## ========================================

func _update_selection_info() -> void:
	var selected = game_manager.selection_manager.selected_characters
	var primary = game_manager.get_primary_character()

	if selected.size() == 0:
		info_label.text = "[Player Team: %s]\nTap a character to select" % PlayerState.get_team_name()
	elif selected.size() == 1:
		_update_info_label_for_character(primary)
	else:
		info_label.text = """[Player Team: %s]
Selected: %d characters

Tap character to toggle selection
Tap ground to deselect all""" % [PlayerState.get_team_name(), selected.size()]


func _update_info_label_for_character(character: Node) -> void:
	if not character:
		return
	var preset_id = character.get_preset_id() if character.has_method("get_preset_id") else character.name.to_snake_case()
	var preset = CharacterRegistry.get_preset(preset_id)
	if preset:
		var control_status = "ON" if is_debug_control_enabled else "OFF"
		info_label.text = """[Player Team: %s]
Selected: %s (%s)
Team: %s | HP: %.0f
Manual Control: %s

Tap character to select
Use context menu for actions""" % [
			PlayerState.get_team_name(),
			preset.display_name,
			preset.id,
			"CT" if preset.team == 1 else "T",
			preset.max_health,
			control_status
		]


func _update_pending_paths_label() -> void:
	if pending_paths_label:
		pending_paths_label.text = "Pending: %d paths" % game_manager.get_pending_path_count()


func _update_mode_info(text: String) -> void:
	if text.is_empty():
		_update_selection_info()
	else:
		info_label.text = text
