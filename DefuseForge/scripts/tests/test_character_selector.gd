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
var selected_characters: Array[Node] = []  ## 選択中の全キャラクター
var primary_character: Node = null  ## 最後に選択したキャラクター（コンテキストメニュー対象）
var characters: Array[Node] = []  ## シーン内の全キャラクター
var aim_position := Vector3.ZERO
var ground_plane := Plane(Vector3.UP, 0)
var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null  ## EnemyVisibilitySystem
var context_menu: Control = null  ## コンテキストメニュー
var outlined_meshes_by_character: Dictionary = {}  ## { character_id: Array[MeshInstance3D] }

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

## キャラクターラベルマネージャー
var label_manager: CharacterLabelManager = null

func _ready() -> void:
	_setup_fog_of_war()
	_setup_enemy_visibility_system()
	_setup_context_menu()
	_setup_path_drawer()
	_setup_controllers()
	_setup_control_buttons()
	_setup_label_manager()
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


## ========================================
## キャラクターラベル
## ========================================

func _setup_label_manager() -> void:
	label_manager = CharacterLabelManager.new()
	label_manager.name = "CharacterLabelManager"
	add_child(label_manager)


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
	_deselect_all()  # 敵を選択中だった場合に解除
	label_manager.refresh_labels(characters)  # ラベルを更新（味方のみ表示）
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
			label_manager.add_label(ct1)
			print("[Test] Spawned CT 1: %s at (-3, 0, -2)" % cts[0].display_name)

		# 2体目のCT（位置: -3, 0, 2）
		var ct_index = 1 if cts.size() > 1 else 0
		var ct2 = CharacterRegistry.create_character(cts[ct_index].id, Vector3(-3, 0, 2))
		if ct2:
			add_child(ct2)
			characters.append(ct2)
			_setup_character_vision_for(ct2)
			label_manager.add_label(ct2)
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
			label_manager.add_label(t1)
			print("[Test] Spawned T 1: %s at (3, 0, -2)" % ts[0].display_name)

		# 2体目のT（位置: 3, 0, 2）
		var t_index = 1 if ts.size() > 1 else 0
		var t2 = CharacterRegistry.create_character(ts[t_index].id, Vector3(3, 0, 2))
		if t2:
			add_child(t2)
			characters.append(t2)
			_setup_character_vision_for(t2)
			label_manager.add_label(t2)
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

	# Remove current character label
	if current_character:
		label_manager.remove_label(current_character)

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
		_deselect_all()  # 生成時は未選択状態
		_setup_character_vision()
		label_manager.add_label(current_character)
		_update_info_label(preset_id)


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
	_update_selection_info()


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

	if not primary_character:
		return

	var anim_ctrl = primary_character.get_anim_controller()
	if not anim_ctrl:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)
			KEY_2:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
			KEY_K:
				primary_character.take_damage(primary_character.max_health)
			KEY_R:
				# Respawn primary character
				if primary_character.has_method("reset_health"):
					primary_character.reset_health()


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
		# プライマリキャラクターは後で別処理
		if character == primary_character:
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
				# 味方キャラクタークリック: トグル選択 + コンテキストメニュー表示
				_toggle_character_selection(clicked_character)
				# 選択中の場合のみコンテキストメニュー表示
				if selected_characters.has(clicked_character):
					_show_context_menu(event.position, clicked_character)
			else:
				# キャラクター以外をクリック: メニューを閉じて全選択解除
				if context_menu and context_menu.is_open():
					context_menu.close()
				_deselect_all()


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


## キャラクターの選択をトグル（選択/解除を切り替え）
func _toggle_character_selection(character: Node) -> void:
	# 敵キャラクターは選択不可
	if PlayerState.is_enemy(character):
		print("[Selection] Cannot select enemy character: %s" % character.name)
		return

	if selected_characters.has(character):
		# 既に選択中なら解除
		_remove_from_selection(character)
	else:
		# 未選択なら追加
		_add_to_selection(character)


## 選択リストにキャラクターを追加
func _add_to_selection(character: Node) -> void:
	if selected_characters.has(character):
		return

	selected_characters.append(character)
	primary_character = character
	current_character = character
	_apply_outline(character)
	_update_selection_info()
	print("[Selection] Added %s (total: %d)" % [character.name, selected_characters.size()])


## 選択リストからキャラクターを削除
func _remove_from_selection(character: Node) -> void:
	if not selected_characters.has(character):
		return

	selected_characters.erase(character)
	_remove_outline(character)

	# プライマリキャラクターを更新
	if primary_character == character:
		if selected_characters.size() > 0:
			primary_character = selected_characters[-1]
			current_character = primary_character
		else:
			primary_character = null

	_update_selection_info()
	print("[Selection] Removed %s (total: %d)" % [character.name, selected_characters.size()])


## 全選択解除
func _deselect_all() -> void:
	for character in selected_characters.duplicate():
		_remove_outline(character)
	selected_characters.clear()
	primary_character = null
	_update_selection_info()
	print("[Selection] Deselected all")


## 選択情報を更新
func _update_selection_info() -> void:
	if selected_characters.size() == 0:
		info_label.text = "[Player Team: %s]\nTap a character to select" % PlayerState.get_team_name()
	elif selected_characters.size() == 1:
		var preset_id = _get_character_preset_id(primary_character)
		if preset_id:
			_update_info_label(preset_id)
	else:
		var player_team_name = PlayerState.get_team_name()
		info_label.text = """[Player Team: %s]
Selected: %d characters

Tap character to toggle selection
Tap ground to deselect all""" % [player_team_name, selected_characters.size()]


## アウトラインを適用（ステンシル方式）
func _apply_outline(character: Node) -> void:
	var char_id = character.get_instance_id()

	# 既にアウトラインがある場合はスキップ
	if outlined_meshes_by_character.has(char_id):
		return

	var meshes = _find_mesh_instances(character)
	var outlined: Array[MeshInstance3D] = []

	for mesh in meshes:
		var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
		for i in range(surface_count):
			var mat = mesh.get_active_material(i)
			if mat and mat is StandardMaterial3D:
				# マテリアルを複製してステンシルアウトラインを設定
				var mat_copy: StandardMaterial3D = mat.duplicate()
				mat_copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				mat_copy.stencil_outline_thickness = 3.5
				mat_copy.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
				mesh.set_surface_override_material(i, mat_copy)
			elif mat:
				# 新しいStandardMaterial3Dを作成
				var new_mat = StandardMaterial3D.new()
				new_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				new_mat.stencil_outline_thickness = 3.5
				new_mat.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
				mesh.set_surface_override_material(i, new_mat)
		outlined.append(mesh)

	outlined_meshes_by_character[char_id] = outlined
	print("[Outline] Applied outline to %s (%d meshes)" % [character.name, outlined.size()])


## 特定キャラクターのアウトラインを削除
func _remove_outline(character: Node) -> void:
	var char_id = character.get_instance_id()
	if not outlined_meshes_by_character.has(char_id):
		return

	var meshes = outlined_meshes_by_character[char_id]
	for mesh in meshes:
		if is_instance_valid(mesh):
			# サーフェスオーバーライドをクリア（元のマテリアルに戻る）
			var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
			for i in range(surface_count):
				mesh.set_surface_override_material(i, null)

	outlined_meshes_by_character.erase(char_id)
	print("[Outline] Removed outline from %s" % character.name)


## 全てのアウトラインを削除
func _clear_all_outlines() -> void:
	for char_id in outlined_meshes_by_character.keys():
		var meshes = outlined_meshes_by_character[char_id]
		for mesh in meshes:
			if is_instance_valid(mesh):
				var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
				for i in range(surface_count):
					mesh.set_surface_override_material(i, null)
	outlined_meshes_by_character.clear()


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


## 移動モード開始（プライマリキャラクターを基準にパス描画）
func _start_move_mode(_character: Node) -> void:
	if selected_characters.is_empty():
		print("[ContextMenu] No characters selected")
		return

	# プライマリキャラクターを基準にパス描画
	print("[ContextMenu] Move mode for %d characters (primary: %s)" % [
		selected_characters.size(), primary_character.name
	])
	is_path_mode = true
	path_editing_character = primary_character
	path_drawer.enable(primary_character)

	if selected_characters.size() == 1:
		_update_mode_info("Path Mode: Draw path (ESC to cancel)")
	else:
		_update_mode_info("Path Mode: Draw path for %d characters (ESC to cancel)" % selected_characters.size())


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

	if not primary_character:
		return

	if not primary_character.is_alive:
		return

	# パス追従中のキャラクターは手動操作をスキップ
	if _is_character_following_path(primary_character):
		return

	var anim_ctrl = primary_character.get_anim_controller()
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
		if primary_character.combat_awareness and primary_character.combat_awareness.has_method("process"):
			primary_character.combat_awareness.process(delta)

		var look_dir: Vector3 = Vector3.ZERO

		# 敵視認チェック（最優先）
		if primary_character.combat_awareness and primary_character.combat_awareness.has_method("is_tracking_enemy"):
			if primary_character.combat_awareness.is_tracking_enemy():
				look_dir = primary_character.combat_awareness.get_override_look_direction()

		# デフォルト: 現在の向きを維持
		if look_dir.length_squared() < 0.1:
			look_dir = anim_ctrl.get_look_direction()

		anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)
		primary_character.velocity.x = 0
		primary_character.velocity.z = 0
		if not primary_character.is_on_floor():
			primary_character.velocity.y -= 9.8 * delta
		primary_character.move_and_slide()
		return

	# Get input
	var move_dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var aim_dir: Vector3 = aim_position - primary_character.global_position
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
		primary_character.velocity.x = move_dir.normalized().x * speed
		primary_character.velocity.z = move_dir.normalized().z * speed
	else:
		primary_character.velocity.x = 0
		primary_character.velocity.z = 0

	if not primary_character.is_on_floor():
		primary_character.velocity.y -= 9.8 * delta

	primary_character.move_and_slide()


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


## 現在編集中のパスを確定して保存（全選択キャラクターに同じパスを適用）
func _confirm_current_path() -> void:
	if not path_drawer.has_pending_path():
		_cancel_path_mode()
		return

	if selected_characters.is_empty():
		print("[PathSystem] No selected characters for path")
		_cancel_path_mode()
		return

	# パス情報を取得（絶対座標のまま）
	var base_path: Array[Vector3] = []
	var pending = path_drawer.get_drawn_path()
	for point in pending:
		base_path.append(point)

	var base_vision_points = path_drawer.get_vision_points().duplicate()
	var base_run_segments = path_drawer.get_run_segments().duplicate()

	# 元のマーカーの所有権を取得
	var original_vision_markers = path_drawer.take_vision_markers()
	var original_run_markers = path_drawer.take_run_markers()

	var path_start = base_path[0] if base_path.size() > 0 else Vector3.ZERO

	# 元のパスの長さを計算
	var base_length = _calculate_path_length(base_path)

	# 選択中の全キャラクターに同じパスを適用
	var first_char_id: int = -1
	var processed_count = 0

	for character in selected_characters:
		var char_id = character.get_instance_id()
		var char_pos = Vector3(character.global_position.x, 0, character.global_position.z)

		# 既存のパスがあれば削除
		_clear_pending_path_for_character(char_id)

		# キャラクター位置からパス開始点への接続を含むパスを作成
		var full_path: Array[Vector3] = []
		var connect_length: float = 0.0

		if char_pos.distance_to(path_start) > 0.1:
			# キャラクターがパス開始点にいない場合、接続線を追加
			full_path.append(char_pos)
			connect_length = char_pos.distance_to(path_start)
		full_path.append_array(base_path)

		# 視線ポイントとRun区間の比率を再計算
		var adjusted_vision_points = _adjust_ratios_for_connection(base_vision_points, connect_length, base_length)
		var adjusted_run_segments = _adjust_run_ratios_for_connection(base_run_segments, connect_length, base_length)

		# パスメッシュを作成（各キャラクターごと）
		var path_mesh = _create_path_mesh(full_path)

		if first_char_id == -1:
			# 最初のキャラクター：マーカーを保持
			first_char_id = char_id
			pending_paths[char_id] = {
				"character": character,
				"path": full_path,
				"vision_points": adjusted_vision_points,
				"run_segments": adjusted_run_segments,
				"path_mesh": path_mesh,
				"vision_markers": original_vision_markers,
				"run_markers": original_run_markers
			}
		else:
			# 2番目以降のキャラクター：マーカーなし
			pending_paths[char_id] = {
				"character": character,
				"path": full_path,
				"vision_points": adjusted_vision_points,
				"run_segments": adjusted_run_segments,
				"path_mesh": path_mesh,
				"vision_markers": [],
				"run_markers": []
			}

		processed_count += 1
		print("[PathSystem] Saved path for %s (%d points, connect: %.2f)" % [character.name, full_path.size(), connect_length])

	print("[PathSystem] Applied same path to %d characters (formation)" % processed_count)

	# パスモードを終了
	is_path_mode = false
	path_editing_character = null
	path_drawer.clear()
	path_drawer.disable()

	if path_panel:
		path_panel.visible = false
	_update_mode_info("")
	_update_pending_paths_label()


## パスの長さを計算
func _calculate_path_length(path: Array[Vector3]) -> float:
	var length: float = 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


## 接続線を考慮して視線ポイントの比率を調整
func _adjust_ratios_for_connection(vision_points: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return vision_points.duplicate()

	var new_length = connect_length + base_length
	var adjusted: Array[Dictionary] = []

	for vp in vision_points:
		var old_ratio: float = vp.path_ratio
		# 新しい比率 = (接続線の長さ + 元の比率 * 元のパス長さ) / 新しいパス長さ
		var new_ratio: float = (connect_length + old_ratio * base_length) / new_length
		adjusted.append({
			"path_ratio": new_ratio,
			"anchor": vp.anchor,
			"direction": vp.direction
		})

	return adjusted


## 接続線を考慮してRun区間の比率を調整
func _adjust_run_ratios_for_connection(run_segments: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return run_segments.duplicate()

	var new_length = connect_length + base_length
	var adjusted: Array[Dictionary] = []

	for seg in run_segments:
		var old_start: float = seg.start_ratio
		var old_end: float = seg.end_ratio
		# 新しい比率を計算
		var new_start: float = (connect_length + old_start * base_length) / new_length
		var new_end: float = (connect_length + old_end * base_length) / new_length
		adjusted.append({
			"start_ratio": new_start,
			"end_ratio": new_end
		})

	return adjusted


## 特定キャラクターの保留パスをクリア
func _clear_pending_path_for_character(char_id: int) -> void:
	if not pending_paths.has(char_id):
		return

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

	pending_paths.erase(char_id)


## 視線マーカーを複製
func _duplicate_vision_markers(vision_points: Array[Dictionary]) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []
	for vp in vision_points:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/vision_marker.gd"))
		add_child(marker)
		marker.set_position_and_direction(vp.anchor, vp.direction)
		markers.append(marker)
	return markers


## Runマーカーを複製
func _duplicate_run_markers(path: Array[Vector3], run_segments: Array[Dictionary]) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	# パス上の位置を計算するためのヘルパー
	var total_length: float = 0.0
	var lengths: Array[float] = [0.0]
	for i in range(1, path.size()):
		var seg_len = path[i - 1].distance_to(path[i])
		total_length += seg_len
		lengths.append(total_length)

	for seg in run_segments:
		# 開始点マーカー
		var start_pos = _get_position_at_ratio(path, lengths, total_length, seg.start_ratio)
		var start_marker = MeshInstance3D.new()
		start_marker.set_script(preload("res://scripts/effects/run_marker.gd"))
		add_child(start_marker)
		start_marker.set_position_and_type(start_pos, 0)  # START = 0
		markers.append(start_marker)

		# 終点マーカー
		var end_pos = _get_position_at_ratio(path, lengths, total_length, seg.end_ratio)
		var end_marker = MeshInstance3D.new()
		end_marker.set_script(preload("res://scripts/effects/run_marker.gd"))
		add_child(end_marker)
		end_marker.set_position_and_type(end_pos, 1)  # END = 1
		markers.append(end_marker)

	return markers


## パス上の進行率から位置を取得
func _get_position_at_ratio(path: Array[Vector3], lengths: Array[float], total_length: float, ratio: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	if ratio <= 0.0:
		return path[0]
	if ratio >= 1.0:
		return path[-1]

	var target_length = total_length * ratio
	for i in range(1, lengths.size()):
		if lengths[i] >= target_length:
			var seg_start = lengths[i - 1]
			var seg_length = lengths[i] - seg_start
			if seg_length > 0:
				var t = (target_length - seg_start) / seg_length
				return path[i - 1].lerp(path[i], t)
			else:
				return path[i - 1]
	return path[-1]


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

		# パスを明示的にArray[Vector3]に変換
		var path: Array[Vector3] = []
		if data.has("path"):
			for p in data["path"]:
				path.append(p)

		# 視線ポイントを明示的にArray[Dictionary]に変換
		var vision_points: Array[Dictionary] = []
		if data.has("vision_points"):
			for vp in data["vision_points"]:
				vision_points.append(vp)

		# Run区間を明示的にArray[Dictionary]に変換
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
			print("[PathSystem] Started path for %s (%d points, run_segments: %d)" % [character.name, path.size(), run_segments.size()])
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
		_update_selection_info()
	else:
		info_label.text = text


## ========================================
## プレイヤーチーム関連ヘルパー
## ========================================

## 指定キャラクターが敵かどうか判定
func _is_enemy_character(character: Node) -> bool:
	return PlayerState.is_enemy(character)
