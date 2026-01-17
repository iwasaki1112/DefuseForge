extends Node3D
## Test scene for character selection
## Debug tool to test different characters from CharacterRegistry
## Features:
## - マウスクリックでキャラクター選択
## - 右クリックでコンテキストメニュー表示
## - ドロップダウンからキャラクター追加

const AnimCtrl = preload("res://scripts/animation/character_animation_controller.gd")
const FogOfWarSystemScript = preload("res://scripts/systems/fog_of_war_system.gd")
const EnemyVisibilitySystemScript = preload("res://scripts/systems/enemy_visibility_system.gd")
const ContextMenuScript = preload("res://scripts/ui/context_menu_component.gd")
const PathDrawerScript = preload("res://scripts/effects/path_drawer.gd")
const PathFollowingCtrl = preload("res://scripts/characters/path_following_controller.gd")
const RotationCtrl = preload("res://scripts/characters/character_rotation_controller.gd")

@onready var camera: Camera3D = $Camera3D
@onready var character_dropdown: OptionButton = $UI/CharacterDropdown
@onready var info_label: Label = $UI/InfoLabel
@onready var ui_layer: CanvasLayer = $UI
@onready var manual_control_button: Button = $UI/ControlPanel/ManualControlButton
@onready var vision_toggle_button: Button = $UI/ControlPanel/VisionToggleButton
@onready var path_panel: VBoxContainer = $UI/PathPanel
@onready var vision_label: Label = $UI/PathPanel/VisionLabel
@onready var add_vision_button: Button = $UI/PathPanel/VisionHBox/AddVisionButton
@onready var undo_vision_button: Button = $UI/PathPanel/VisionHBox/UndoVisionButton
@onready var run_label: Label = $UI/PathPanel/RunLabel
@onready var add_run_button: Button = $UI/PathPanel/RunHBox/AddRunButton
@onready var undo_run_button: Button = $UI/PathPanel/RunHBox/UndoRunButton
@onready var confirm_path_button: Button = $UI/PathPanel/ConfirmButton
@onready var cancel_button: Button = $UI/PathPanel/CancelButton
@onready var rotate_panel: VBoxContainer = $UI/RotatePanel
@onready var rotate_confirm_button: Button = $UI/RotatePanel/RotateConfirmButton
@onready var rotate_cancel_button: Button = $UI/RotatePanel/RotateCancelButton
## 実行ボタン（外出し）
@onready var pending_paths_label: Label = $UI/ControlPanel/PendingPathsLabel
@onready var execute_walk_button: Button = $UI/ControlPanel/ExecuteWalkButton
@onready var clear_paths_button: Button = $UI/ControlPanel/ClearPathsButton

var current_character: Node = null
var selected_character: Node = null  ## 現在選択中のキャラクター
var characters: Array[Node] = []  ## シーン内の全キャラクター
var aim_position := Vector3.ZERO
var ground_plane := Plane(Vector3.UP, 0)
var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null  ## EnemyVisibilitySystem
var context_menu: Control = null  ## コンテキストメニュー
var outlined_meshes: Array[MeshInstance3D] = []  ## アウトライン適用中のメッシュ

## デバッグ操作モード
var is_debug_control_enabled: bool = false  ## WASD/マウス操作の有効化（デフォルトOFF）
var is_vision_enabled: bool = false  ## 視界/FoWの有効化（デフォルトOFF）

## パスシステム
var path_drawer: Node3D = null
var is_path_mode: bool = false  ## パス描画モード中
var path_editing_character: Node = null  ## 現在パスを編集中のキャラクター

## 保留中のパス（キャラクターごと）
## { character_id: { "character": Node, "path": Array[Vector3], "vision_points": Array, "path_mesh": Node3D } }
var pending_paths: Dictionary = {}

## パスメッシュスクリプト
const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")

## コントローラー
var path_following_controllers: Dictionary = {}  ## character_id -> PathFollowingController
var rotation_controller: Node = null

func _ready() -> void:
	_setup_fog_of_war()
	_setup_enemy_visibility_system()
	_setup_context_menu()
	_setup_path_drawer()
	_setup_controllers()
	_setup_control_buttons()
	_populate_dropdown()
	character_dropdown.item_selected.connect(_on_team_selected)

	# Spawn 2 CT characters at different positions
	_spawn_initial_characters()

	# Apply initial vision state (OFF by default)
	_apply_vision_state()


func _setup_controllers() -> void:
	# CharacterRotationController
	rotation_controller = Node.new()
	rotation_controller.set_script(RotationCtrl)
	rotation_controller.name = "RotationController"
	add_child(rotation_controller)
	rotation_controller.rotation_confirmed.connect(_on_rotation_confirmed)
	rotation_controller.rotation_cancelled.connect(_on_rotation_cancelled)


## キャラクター用のPathFollowingControllerを取得または作成
func _get_or_create_path_controller(character: Node) -> Node:
	var char_id = character.get_instance_id()
	if path_following_controllers.has(char_id):
		var existing = path_following_controllers[char_id]
		# Ensure combat awareness is connected
		if character.combat_awareness and existing.has_method("set_combat_awareness"):
			existing.set_combat_awareness(character.combat_awareness)
		return existing

	var controller = Node.new()
	controller.set_script(PathFollowingCtrl)
	controller.name = "PathFollowingController_%d" % char_id
	add_child(controller)
	controller.path_completed.connect(_on_path_following_completed.bind(character))
	controller.path_cancelled.connect(_on_path_following_cancelled.bind(character))

	# Connect combat awareness for automatic enemy aiming during movement
	if character.combat_awareness:
		controller.set_combat_awareness(character.combat_awareness)

	path_following_controllers[char_id] = controller
	return controller


func _setup_context_menu() -> void:
	context_menu = Control.new()
	context_menu.set_script(ContextMenuScript)
	context_menu.name = "ContextMenu"
	ui_layer.add_child(context_menu)
	context_menu.setup_default_items()
	context_menu.item_selected.connect(_on_context_menu_item_selected)


func _setup_path_drawer() -> void:
	path_drawer = Node3D.new()
	path_drawer.set_script(PathDrawerScript)
	path_drawer.name = "PathDrawer"
	add_child(path_drawer)
	path_drawer.setup(camera)
	path_drawer.drawing_finished.connect(_on_path_drawing_finished)
	path_drawer.mode_changed.connect(_on_path_mode_changed)


func _setup_control_buttons() -> void:
	# Manual Control ボタン
	manual_control_button.pressed.connect(_on_manual_control_button_pressed)
	_update_manual_control_button()

	# Vision Toggle ボタン
	vision_toggle_button.pressed.connect(_on_vision_toggle_button_pressed)
	_update_vision_toggle_button()

	# 視線ポイントボタン
	add_vision_button.pressed.connect(_on_add_vision_button_pressed)
	undo_vision_button.pressed.connect(_on_undo_vision_button_pressed)

	# Runマーカーボタン
	add_run_button.pressed.connect(_on_add_run_button_pressed)
	undo_run_button.pressed.connect(_on_undo_run_button_pressed)

	# パス確定/キャンセルボタン
	confirm_path_button.pressed.connect(_on_confirm_path_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)

	# 視線ポイント追加シグナル
	path_drawer.vision_point_added.connect(_on_vision_point_added)

	# Runセグメント追加シグナル
	path_drawer.run_segment_added.connect(_on_run_segment_added)

	# 実行ボタン（外出し）
	execute_walk_button.pressed.connect(_on_execute_walk_button_pressed)
	clear_paths_button.pressed.connect(_on_clear_paths_button_pressed)
	_update_pending_paths_label()

	# 回転モードボタン
	rotate_confirm_button.pressed.connect(_on_rotate_confirm_pressed)
	rotate_cancel_button.pressed.connect(_on_rotate_cancel_pressed)

	# 初期状態ではパネルを非表示
	path_panel.visible = false
	rotate_panel.visible = false


func _on_manual_control_button_pressed() -> void:
	is_debug_control_enabled = not is_debug_control_enabled
	_update_manual_control_button()
	_refresh_info_label()
	print("[Debug] Manual control: %s" % ("ON" if is_debug_control_enabled else "OFF"))


func _update_manual_control_button() -> void:
	if manual_control_button:
		manual_control_button.text = "Manual Control: %s" % ("ON" if is_debug_control_enabled else "OFF")


func _on_vision_toggle_button_pressed() -> void:
	is_vision_enabled = not is_vision_enabled
	_update_vision_toggle_button()
	_apply_vision_state()
	print("[Debug] Vision/FoW: %s" % ("ON" if is_vision_enabled else "OFF"))


func _update_vision_toggle_button() -> void:
	if vision_toggle_button:
		vision_toggle_button.text = "Vision/FoW: %s" % ("ON" if is_vision_enabled else "OFF")


## 視界/FoWの状態を全キャラクターに適用
func _apply_vision_state() -> void:
	# FogOfWarSystemの表示を切り替え
	if fog_of_war_system:
		fog_of_war_system.set_fog_visible(is_vision_enabled)

	# EnemyVisibilitySystemのモードを切り替え
	if enemy_visibility_system:
		if is_vision_enabled:
			# FoW ON: 詳細な視界ポリゴンベースの判定
			enemy_visibility_system.enable_full()
		else:
			# FoW OFF: 軽量なレイキャストベースの判定（97%レイ削減）
			enemy_visibility_system.enable_lightweight()


## パス確定ボタン：現在のパスを保存
func _on_confirm_path_button_pressed() -> void:
	_confirm_current_path()


## キャンセルボタン
func _on_cancel_button_pressed() -> void:
	_cancel_path_mode()


## 全員実行ボタン
func _on_execute_walk_button_pressed() -> void:
	_execute_all_paths(false)


## 全パスクリアボタン
func _on_clear_paths_button_pressed() -> void:
	_clear_all_pending_paths()


func _on_add_vision_button_pressed() -> void:
	if path_drawer.has_pending_path():
		path_drawer.start_vision_mode()
		_update_vision_label()
		print("[PathSystem] Vision mode activated")


func _on_undo_vision_button_pressed() -> void:
	path_drawer.remove_last_vision_point()
	_update_vision_label()


func _on_vision_point_added(_anchor: Vector3, _direction: Vector3) -> void:
	_update_vision_label()


func _on_add_run_button_pressed() -> void:
	if path_drawer.has_pending_path():
		path_drawer.start_run_mode()
		_update_run_label()
		print("[PathSystem] Run marker mode activated")


func _on_undo_run_button_pressed() -> void:
	path_drawer.remove_last_run_segment()
	_update_run_label()


func _on_run_segment_added(_start_ratio: float, _end_ratio: float) -> void:
	_update_run_label()


func _update_vision_label() -> void:
	if vision_label:
		var count = path_drawer.get_vision_point_count()
		vision_label.text = "Vision Points: %d" % count


func _update_run_label() -> void:
	if run_label:
		var count = path_drawer.get_run_segment_count()
		var incomplete = " (setting...)" if path_drawer.has_incomplete_run_start() else ""
		run_label.text = "Run Segments: %d%s" % [count, incomplete]


func _update_path_panel_visibility() -> void:
	if path_panel:
		path_panel.visible = is_path_mode and path_drawer.has_pending_path()
		_update_vision_label()
		_update_run_label()


## ========================================
## 回転モード
## ========================================

func _on_rotate_confirm_pressed() -> void:
	rotation_controller.confirm()


func _on_rotate_cancel_pressed() -> void:
	rotation_controller.cancel()


func _on_rotation_confirmed(_final_direction: Vector3) -> void:
	rotate_panel.visible = false
	_update_mode_info("")

	# Dismiss enemy tracking for the rotating character
	var rotating_character = rotation_controller.get_character()
	if rotating_character and rotating_character.combat_awareness:
		rotating_character.combat_awareness.dismiss_current_target()

	print("[RotateMode] Confirmed")


func _on_rotation_cancelled() -> void:
	rotate_panel.visible = false
	_update_mode_info("")
	print("[RotateMode] Cancelled")


func _setup_fog_of_war() -> void:
	fog_of_war_system = Node3D.new()
	fog_of_war_system.set_script(FogOfWarSystemScript)
	fog_of_war_system.name = "FogOfWarSystem"
	fog_of_war_system.map_size = Vector2(50, 50)  # Match floor size
	add_child(fog_of_war_system)


func _setup_enemy_visibility_system() -> void:
	enemy_visibility_system = Node.new()
	enemy_visibility_system.set_script(EnemyVisibilitySystemScript)
	enemy_visibility_system.name = "EnemyVisibilitySystem"
	add_child(enemy_visibility_system)
	enemy_visibility_system.setup(fog_of_war_system)

## ドロップダウンをCT/T選択に変更
func _populate_dropdown() -> void:
	character_dropdown.clear()
	character_dropdown.add_item("CT (Counter-Terrorist)")
	character_dropdown.set_item_metadata(0, GameCharacter.Team.COUNTER_TERRORIST)
	character_dropdown.add_item("T (Terrorist)")
	character_dropdown.set_item_metadata(1, GameCharacter.Team.TERRORIST)
	character_dropdown.select(0)

## チーム選択時
func _on_team_selected(index: int) -> void:
	var new_team: GameCharacter.Team = character_dropdown.get_item_metadata(index)
	PlayerState.set_player_team(new_team)
	_deselect_character()  # 敵を選択中だった場合に解除
	_refresh_info_label()


## 初期キャラクター4体を生成（CT 2体 + T 2体）
func _spawn_initial_characters() -> void:
	var cts = CharacterRegistry.get_counter_terrorists()
	var ts = CharacterRegistry.get_terrorists()

	# CT 2体を生成
	if cts.size() >= 1:
		# 1体目のCT（位置: -3, 0, -2）
		var ct1 = CharacterRegistry.create_character(cts[0].id, Vector3(-3, 0, -2))
		if ct1:
			add_child(ct1)
			characters.append(ct1)
			_setup_character_vision_for(ct1)
			print("[Test] Spawned CT 1: %s at (-3, 0, -2)" % cts[0].display_name)

		# 2体目のCT（位置: -3, 0, 2）
		var ct_index = 1 if cts.size() > 1 else 0
		var ct2 = CharacterRegistry.create_character(cts[ct_index].id, Vector3(-3, 0, 2))
		if ct2:
			add_child(ct2)
			characters.append(ct2)
			_setup_character_vision_for(ct2)
			print("[Test] Spawned CT 2: %s at (-3, 0, 2)" % cts[ct_index].display_name)
	else:
		print("[Test] No CT characters available")

	# T 2体を生成
	if ts.size() >= 1:
		# 1体目のT（位置: 3, 0, -2）
		var t1 = CharacterRegistry.create_character(ts[0].id, Vector3(3, 0, -2))
		if t1:
			add_child(t1)
			characters.append(t1)
			_setup_character_vision_for(t1)
			print("[Test] Spawned T 1: %s at (3, 0, -2)" % ts[0].display_name)

		# 2体目のT（位置: 3, 0, 2）
		var t_index = 1 if ts.size() > 1 else 0
		var t2 = CharacterRegistry.create_character(ts[t_index].id, Vector3(3, 0, 2))
		if t2:
			add_child(t2)
			characters.append(t2)
			_setup_character_vision_for(t2)
			print("[Test] Spawned T 2: %s at (3, 0, 2)" % ts[t_index].display_name)
	else:
		print("[Test] No T characters available")

	# 最初のキャラクターをcurrent_characterに設定
	if characters.size() > 0:
		current_character = characters[0]
		if cts.size() >= 1:
			_update_info_label(cts[0].id)

func _spawn_character(preset_id: String) -> void:
	# Unregister old vision from FoW
	if current_character and current_character.vision and fog_of_war_system:
		fog_of_war_system.unregister_vision(current_character.vision)

	# Remove current character
	if current_character:
		characters.erase(current_character)
		current_character.queue_free()
		current_character = null

	# Create new character
	current_character = CharacterRegistry.create_character(preset_id, Vector3.ZERO)
	if current_character:
		add_child(current_character)
		characters.append(current_character)
		selected_character = null  # 生成時は未選択状態
		_setup_character_vision()
		_update_info_label(preset_id)
		_clear_outline()  # アウトラインをクリア


func _setup_character_vision() -> void:
	if not current_character:
		return
	_setup_character_vision_for(current_character)


## 指定したキャラクターの視界をセットアップ
func _setup_character_vision_for(character: Node) -> void:
	if not character:
		return

	# Setup vision component
	var vision = character.setup_vision(90.0, 15.0)

	# Wait for VisionComponent to initialize
	if vision:
		await get_tree().process_frame

	# Register with EnemyVisibilitySystem (handles FoW registration internally)
	if enemy_visibility_system:
		enemy_visibility_system.register_character(character)

	# Setup combat awareness for automatic enemy aiming
	character.setup_combat_awareness()
	if character.combat_awareness:
		character.combat_awareness.enemy_spotted.connect(
			func(enemy): print("[Combat] %s spotted %s" % [character.name, enemy.name])
		)
		character.combat_awareness.enemy_lost.connect(
			func(enemy): print("[Combat] %s lost sight of %s" % [character.name, enemy.name])
		)

	# Apply current vision state
	if not is_vision_enabled and vision:
		vision.disable()
		if fog_of_war_system:
			fog_of_war_system.set_fog_visible(false)

func _update_info_label(preset_id: String) -> void:
	var preset = CharacterRegistry.get_preset(preset_id)
	var player_team_name = PlayerState.get_team_name()
	if preset:
		var control_status = "ON" if is_debug_control_enabled else "OFF"
		info_label.text = """[Player Team: %s]
Selected: %s (%s)
Team: %s | HP: %.0f
Manual Control: %s

Tap character to select
Use context menu for actions""" % [
			player_team_name,
			preset.display_name,
			preset.id,
			"CT" if preset.team == 1 else "T",
			preset.max_health,
			control_status
		]
	else:
		info_label.text = "[Player Team: %s]\nTap a character to select" % player_team_name


## 情報ラベルを現在の状態で更新
func _refresh_info_label() -> void:
	if current_character:
		var preset_id = _get_character_preset_id(current_character)
		if preset_id:
			_update_info_label(preset_id)


func _unhandled_input(event: InputEvent) -> void:
	# 回転モード中のマウス/タッチ処理（UIで処理されなかった入力のみ）
	if rotation_controller.is_rotation_active() and event is InputEventMouseButton and event.pressed:
		rotation_controller.handle_input(event.position)


func _input(event: InputEvent) -> void:
	# ESCキー処理（モードキャンセル）
	if event.is_action_pressed("ui_cancel"):
		if is_path_mode:
			_cancel_path_mode()
		elif _any_path_following_active():
			_cancel_all_path_following()
		elif rotation_controller.is_rotation_active():
			_on_rotate_cancel_pressed()

	# マウス/タッチ処理（回転モード以外）
	if event is InputEventMouseButton and event.pressed:
		if not rotation_controller.is_rotation_active() and not is_path_mode:
			_handle_mouse_click(event)

	if not selected_character:
		return

	var anim_ctrl = selected_character.get_anim_controller()
	if not anim_ctrl:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)
			KEY_2:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
			KEY_K:
				selected_character.take_damage(selected_character.max_health)
			KEY_R:
				# Respawn selected character
				if selected_character.has_method("reset_health"):
					selected_character.reset_health()


## パス追従中のコントローラーがあるかチェック
func _any_path_following_active() -> bool:
	for controller in path_following_controllers.values():
		if controller.is_following_path():
			return true
	return false


## 指定キャラクターがパス追従中かチェック
func _is_character_following_path(character: Node) -> bool:
	if not character:
		return false
	var char_id = character.get_instance_id()
	if path_following_controllers.has(char_id):
		return path_following_controllers[char_id].is_following_path()
	return false


## パス追従していないキャラクターのアイドル状態を更新
func _update_idle_characters(delta: float) -> void:
	for character in characters:
		# パス追従中はスキップ
		if _is_character_following_path(character):
			continue
		# 選択中のキャラクターは後で別処理
		if character == selected_character:
			continue
		# 死亡中はスキップ
		if not character.is_alive:
			continue

		# Combat awarenessを処理（アイドル中も敵を追跡）
		if character.combat_awareness and character.combat_awareness.has_method("process"):
			character.combat_awareness.process(delta)

		var anim_ctrl = character.get_anim_controller()
		if anim_ctrl:
			var look_dir: Vector3 = Vector3.ZERO

			# 敵視認チェック（最優先）
			if character.combat_awareness and character.combat_awareness.has_method("is_tracking_enemy"):
				if character.combat_awareness.is_tracking_enemy():
					look_dir = character.combat_awareness.get_override_look_direction()

			# デフォルト: 現在の向きを維持
			if look_dir.length_squared() < 0.1:
				look_dir = anim_ctrl.get_look_direction()

			anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)


## 全てのパス追従をキャンセル
func _cancel_all_path_following() -> void:
	for controller in path_following_controllers.values():
		if controller.is_following_path():
			controller.cancel()
	_update_mode_info("")
	print("[PathSystem] Cancelled all path following")


## マウスクリック処理
func _handle_mouse_click(event: InputEventMouseButton) -> void:
	# コンテキストメニューが開いている場合、メニューUI上のクリックは無視
	if context_menu and context_menu.is_open():
		if _is_point_over_context_menu(event.position):
			return

	var clicked_character = _raycast_character(event.position)

	match event.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if clicked_character:
				# 敵キャラクターは無視
				if _is_enemy_character(clicked_character):
					return
				# 味方キャラクタークリック: 選択 + コンテキストメニュー表示
				_select_character(clicked_character)
				_show_context_menu(event.position, clicked_character)
			else:
				# キャラクター以外をクリック: メニューを閉じて選択解除
				if context_menu and context_menu.is_open():
					context_menu.close()
				_deselect_character()


## マウス位置がコンテキストメニュー上かどうか
func _is_point_over_context_menu(screen_pos: Vector2) -> bool:
	if not context_menu or not context_menu.is_open():
		return false
	var panel_rect = context_menu.get_panel_rect()
	return panel_rect.has_point(screen_pos)


## レイキャストでキャラクターを検出
func _raycast_character(screen_pos: Vector2) -> Node:
	if not camera:
		return null

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_dir * 100.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null

	# キャラクターを探す（衝突したコライダーの親を辿る）
	var collider = result.collider
	for character in characters:
		if _is_child_of(collider, character):
			return character
	return null


## ノードが親の子孫かどうか
func _is_child_of(child: Node, parent: Node) -> bool:
	var node = child
	while node:
		if node == parent:
			return true
		node = node.get_parent()
	return false


## キャラクターを選択
func _select_character(character: Node) -> void:
	# 敵キャラクターは選択不可
	if PlayerState.is_enemy(character):
		print("[Selection] Cannot select enemy character: %s" % character.name)
		return

	selected_character = character
	current_character = character
	var preset_id = _get_character_preset_id(character)
	if preset_id:
		_update_info_label(preset_id)
	# 選択アウトラインを表示
	_show_selection_outline(character)


## キャラクターの選択を解除
func _deselect_character() -> void:
	selected_character = null
	_clear_outline()
	info_label.text = "[Player Team: %s]\nTap a character to select" % PlayerState.get_team_name()


## 選択アウトラインを表示
func _show_selection_outline(character: Node) -> void:
	# 既存のアウトラインを削除
	_clear_outline()
	# 選択キャラクターにアウトラインを適用
	if character:
		_apply_outline(character)


## アウトラインを適用（ステンシル方式）
func _apply_outline(character: Node) -> void:
	var meshes = _find_mesh_instances(character)
	print("[Outline] Found %d meshes in %s" % [meshes.size(), character.name])

	for mesh in meshes:
		var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
		print("[Outline] Mesh %s has %d surfaces" % [mesh.name, surface_count])
		for i in range(surface_count):
			var mat = mesh.get_active_material(i)
			print("[Outline] Surface %d material type: %s" % [i, mat.get_class() if mat else "null"])
			if mat and mat is StandardMaterial3D:
				# マテリアルを複製してステンシルアウトラインを設定
				var mat_copy: StandardMaterial3D = mat.duplicate()
				mat_copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				mat_copy.stencil_outline_thickness = 3.5
				mat_copy.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
				mesh.set_surface_override_material(i, mat_copy)
				print("[Outline] Stencil mode set to: %d, thickness: %f" % [mat_copy.stencil_mode, mat_copy.stencil_outline_thickness])
			elif mat:
				print("[Outline] Material is not StandardMaterial3D, trying to convert...")
				# 新しいStandardMaterial3Dを作成
				var new_mat = StandardMaterial3D.new()
				new_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				new_mat.stencil_outline_thickness = 3.5
				new_mat.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
				mesh.set_surface_override_material(i, new_mat)
				print("[Outline] Created new StandardMaterial3D with stencil outline")
		outlined_meshes.append(mesh)
		print("[Outline] Applied outline to: %s" % mesh.name)


## アウトラインを削除
func _clear_outline() -> void:
	for mesh in outlined_meshes:
		if is_instance_valid(mesh):
			# サーフェスオーバーライドをクリア（元のマテリアルに戻る）
			var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
			for i in range(surface_count):
				mesh.set_surface_override_material(i, null)
	outlined_meshes.clear()


## MeshInstance3Dを再帰的に探す
func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result


## キャラクターのプリセットIDを取得
func _get_character_preset_id(character: Node) -> String:
	if character.has_method("get_preset_id"):
		return character.get_preset_id()
	# プリセットIDがない場合は名前から推測
	return character.name.to_snake_case()


## コンテキストメニューを表示
func _show_context_menu(screen_pos: Vector2, character: Node) -> void:
	if context_menu:
		context_menu.open(screen_pos, character)


## コンテキストメニューアイテム選択時
func _on_context_menu_item_selected(action_id: String, character: CharacterBody3D) -> void:
	match action_id:
		"move":
			_start_move_mode(character)
		"rotate":
			_start_rotate_mode(character)
		"crouch":
			_toggle_crouch(character)


## 移動モード開始
func _start_move_mode(character: Node) -> void:
	print("[ContextMenu] Move mode for: ", character.name)
	is_path_mode = true
	path_editing_character = character
	path_drawer.enable(character)
	_update_mode_info("Path Mode: Draw path with mouse (ESC to cancel)")


## 回転モード開始
func _start_rotate_mode(character: Node) -> void:
	print("[ContextMenu] Rotate mode for: ", character.name)
	rotation_controller.setup(character as CharacterBody3D, camera)
	rotation_controller.start_rotation()
	rotate_panel.visible = true
	_update_mode_info("Rotate Mode: Tap to set direction")


## しゃがむ/立つ切り替え
func _toggle_crouch(character: Node) -> void:
	if character.has_method("toggle_crouch"):
		character.toggle_crouch()
		print("[ContextMenu] Toggled crouch: ", character.name)

func _physics_process(delta: float) -> void:
	# 全パス追従コントローラーを処理
	for controller in path_following_controllers.values():
		if controller.is_following_path():
			controller.process(delta)

	# パス追従していない全キャラクターのアイドル状態を維持
	_update_idle_characters(delta)

	# 回転モード中はコントローラーに処理を委譲
	if rotation_controller.is_rotation_active():
		rotation_controller.process(delta)
		return

	if not selected_character:
		return

	if not selected_character.is_alive:
		return

	# パス追従中のキャラクターは手動操作をスキップ
	if _is_character_following_path(selected_character):
		return

	var anim_ctrl = selected_character.get_anim_controller()
	if not anim_ctrl:
		return

	# デバッグ操作が無効の場合はマウスエイムも停止
	if is_debug_control_enabled:
		_update_aim_position()

	# パスモード中は現在の向きを維持
	if is_path_mode:
		var current_look_dir = anim_ctrl.get_look_direction()
		anim_ctrl.update_animation(Vector3.ZERO, current_look_dir, false, delta)
		return

	# デバッグ操作が無効の場合は入力を無視（敵追跡は有効）
	if not is_debug_control_enabled:
		# Combat awarenessを処理
		if selected_character.combat_awareness and selected_character.combat_awareness.has_method("process"):
			selected_character.combat_awareness.process(delta)

		var look_dir: Vector3 = Vector3.ZERO

		# 敵視認チェック（最優先）
		if selected_character.combat_awareness and selected_character.combat_awareness.has_method("is_tracking_enemy"):
			if selected_character.combat_awareness.is_tracking_enemy():
				look_dir = selected_character.combat_awareness.get_override_look_direction()

		# デフォルト: 現在の向きを維持
		if look_dir.length_squared() < 0.1:
			look_dir = anim_ctrl.get_look_direction()

		anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)
		selected_character.velocity.x = 0
		selected_character.velocity.z = 0
		if not selected_character.is_on_floor():
			selected_character.velocity.y -= 9.8 * delta
		selected_character.move_and_slide()
		return

	# Get input
	var move_dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var aim_dir: Vector3 = aim_position - selected_character.global_position
	aim_dir.y = 0
	var is_running := Input.is_key_pressed(KEY_SHIFT)

	# Update animation
	anim_ctrl.update_animation(move_dir, aim_dir, is_running, delta)

	# Set state
	anim_ctrl.set_stance(
		AnimCtrl.Stance.CROUCH if Input.is_key_pressed(KEY_C)
		else AnimCtrl.Stance.STAND
	)
	anim_ctrl.set_aiming(Input.is_key_pressed(KEY_F))

	# Fire action
	if Input.is_key_pressed(KEY_SPACE) and Input.is_key_pressed(KEY_F):
		anim_ctrl.fire()

	# Movement
	var speed: float = anim_ctrl.get_current_speed()
	if move_dir.length() > 0.1:
		selected_character.velocity.x = move_dir.normalized().x * speed
		selected_character.velocity.z = move_dir.normalized().z * speed
	else:
		selected_character.velocity.x = 0
		selected_character.velocity.z = 0

	if not selected_character.is_on_floor():
		selected_character.velocity.y -= 9.8 * delta

	selected_character.move_and_slide()


func _update_aim_position() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		aim_position = intersection


## ========================================
## パスシステム
## ========================================

## パス描画完了時
func _on_path_drawing_finished(points: PackedVector3Array) -> void:
	if points.size() < 2:
		_cancel_path_mode()
		return

	print("[PathSystem] Path drawn with %d points" % points.size())

	# 視線ポイントモードへ移行
	if path_drawer.start_vision_mode():
		_update_mode_info("Vision Mode: Click on path to set look direction")
		_update_path_panel_visibility()


## パスモード変更時
func _on_path_mode_changed(mode: int) -> void:
	if mode == 0:  # MOVEMENT
		_update_mode_info("Path Mode: Draw path")
		_update_path_panel_visibility()
	else:  # VISION_POINT
		var count = path_drawer.get_vision_point_count()
		_update_mode_info("Vision Mode: %d vision points" % count)
		_update_path_panel_visibility()


## 現在編集中のパスを確定して保存
func _confirm_current_path() -> void:
	if not path_drawer.has_pending_path():
		_cancel_path_mode()
		return

	if not path_editing_character:
		print("[PathSystem] No character for path")
		_cancel_path_mode()
		return

	# パス情報を取得
	var path: Array[Vector3] = []
	var pending = path_drawer.get_drawn_path()
	for point in pending:
		path.append(point)

	var vision_points = path_drawer.get_vision_points().duplicate()
	var run_segments = path_drawer.get_run_segments().duplicate()

	# 視線マーカーとRunマーカーの所有権を取得（clear前に）
	var vision_markers = path_drawer.take_vision_markers()
	var run_markers = path_drawer.take_run_markers()

	# 既存のパスがあれば削除
	var char_id = path_editing_character.get_instance_id()
	if pending_paths.has(char_id):
		var old_data = pending_paths[char_id]
		if old_data.has("path_mesh") and is_instance_valid(old_data["path_mesh"]):
			old_data["path_mesh"].queue_free()
		if old_data.has("vision_markers"):
			for marker in old_data["vision_markers"]:
				if is_instance_valid(marker):
					marker.queue_free()
		if old_data.has("run_markers"):
			for marker in old_data["run_markers"]:
				if is_instance_valid(marker):
					marker.queue_free()

	# パスメッシュを作成（表示用）
	var path_mesh = _create_path_mesh(path)

	# キャラクターIDでパスを保存
	pending_paths[char_id] = {
		"character": path_editing_character,
		"path": path,
		"vision_points": vision_points,
		"run_segments": run_segments,
		"path_mesh": path_mesh,
		"vision_markers": vision_markers,
		"run_markers": run_markers
	}

	print("[PathSystem] Saved path for %s: %d points, %d vision points, %d run segments" % [
		path_editing_character.name, path.size(), vision_points.size(), run_segments.size()
	])

	# パスモードを終了（パスメッシュと視線マーカーは保持）
	is_path_mode = false
	path_editing_character = null
	path_drawer.clear()
	path_drawer.disable()

	if path_panel:
		path_panel.visible = false
	_update_mode_info("")
	_update_pending_paths_label()


## パスメッシュを作成
func _create_path_mesh(path: Array[Vector3]) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	mesh.set_script(PathLineMeshScript)
	mesh.line_color = Color(0.3, 0.8, 1.0, 0.8)  # 確定パスは水色
	mesh.line_width = 0.04
	add_child(mesh)

	# パスを描画
	var packed_path = PackedVector3Array()
	for point in path:
		packed_path.append(point)
	mesh.update_from_points(packed_path)

	return mesh


## 全キャラクターのパスを同時実行
func _execute_all_paths(run: bool) -> void:
	if pending_paths.is_empty():
		print("[PathSystem] No pending paths to execute")
		return

	var executed_count = 0
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		var character = data["character"] as CharacterBody3D
		var path = data["path"]
		var vision_points = data["vision_points"]
		var run_segments: Array[Dictionary] = []
		if data.has("run_segments"):
			for seg in data["run_segments"]:
				run_segments.append(seg)

		if not is_instance_valid(character):
			continue

		# コントローラーを取得または作成
		var controller = _get_or_create_path_controller(character)
		controller.setup(character)

		if controller.start_path(path, vision_points, run_segments, run):
			executed_count += 1
			print("[PathSystem] Started path for %s (run_segments: %d)" % [character.name, run_segments.size()])
		else:
			print("[PathSystem] Failed to start path for %s" % character.name)

	# パスメッシュは全員完了後に削除（_on_path_following_completedで処理）
	# パスデータのみクリア（メッシュは残す）
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		data.erase("path")
		data.erase("vision_points")
		data.erase("run_segments")
		data.erase("character")

	_update_pending_paths_label()
	_update_mode_info("Executing %d paths..." % executed_count)
	print("[PathSystem] Executed %d paths" % executed_count)


## 全ての保留パスをクリア
func _clear_all_pending_paths() -> void:
	_clear_all_path_meshes()
	pending_paths.clear()
	_update_pending_paths_label()
	print("[PathSystem] Cleared all pending paths")


## 全てのパスメッシュと視線マーカーとRunマーカーを削除
func _clear_all_path_meshes() -> void:
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		if data.has("path_mesh") and is_instance_valid(data["path_mesh"]):
			data["path_mesh"].queue_free()
		if data.has("vision_markers"):
			for marker in data["vision_markers"]:
				if is_instance_valid(marker):
					marker.queue_free()
		if data.has("run_markers"):
			for marker in data["run_markers"]:
				if is_instance_valid(marker):
					marker.queue_free()


## パスモードをキャンセル
func _cancel_path_mode() -> void:
	is_path_mode = false
	path_editing_character = null
	path_drawer.clear()
	path_drawer.disable()
	_update_mode_info("")
	if path_panel:
		path_panel.visible = false
	print("[PathSystem] Path mode cancelled")


## 保留パス数ラベルを更新
func _update_pending_paths_label() -> void:
	if pending_paths_label:
		pending_paths_label.text = "Pending: %d paths" % pending_paths.size()


## パス追従完了時のコールバック
func _on_path_following_completed(character: Node) -> void:
	print("[PathSystem] Path following completed for %s" % character.name)
	# 全てのコントローラーが完了したかチェック
	var any_active = false
	for controller in path_following_controllers.values():
		if controller.is_following_path():
			any_active = true
			break
	if not any_active:
		# 全員完了したのでパスメッシュを削除
		_clear_all_path_meshes()
		pending_paths.clear()
		_update_mode_info("")
		print("[PathSystem] All paths completed, meshes cleared")


## パス追従キャンセル時のコールバック
func _on_path_following_cancelled(character: Node) -> void:
	print("[PathSystem] Path following cancelled for %s" % character.name)


## モード情報を更新
func _update_mode_info(text: String) -> void:
	if text.is_empty():
		_update_info_label(_get_character_preset_id(current_character) if current_character else "")
	else:
		info_label.text = text


## ========================================
## プレイヤーチーム関連ヘルパー
## ========================================

## 指定キャラクターが敵かどうか判定
func _is_enemy_character(character: Node) -> bool:
	return PlayerState.is_enemy(character)
