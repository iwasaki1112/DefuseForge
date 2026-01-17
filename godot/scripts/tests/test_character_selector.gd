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
const RotationCtrl = preload("res://scripts/characters/character_rotation_controller.gd")
const MarkerEditPanelScript = preload("res://scripts/ui/marker_edit_panel.gd")

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
var characters: Array[Node] = []  ## シーン内の全キャラクター
var aim_position := Vector3.ZERO
var ground_plane := Plane(Vector3.UP, 0)
var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null  ## EnemyVisibilitySystem
var context_menu: Control = null  ## コンテキストメニュー

## マネージャー
var selection_manager: CharacterSelectionManager = null
var path_execution_manager: PathExecutionManager = null
var idle_manager: IdleCharacterManager = null
var path_mode_controller: PathModeController = null

## デバッグ操作モード
var is_debug_control_enabled: bool = false  ## WASD/マウス操作の有効化（デフォルトOFF）
var is_vision_enabled: bool = false  ## 視界/FoWの有効化（デフォルトOFF）

## パスシステム
var path_drawer: Node3D = null

## マーカー編集パネル（マルチキャラクター対応）
var marker_edit_panel: VBoxContainer = null  # MarkerEditPanel script attached

## コントローラー
var rotation_controller: Node = null

## キャラクターラベルマネージャー
var label_manager: CharacterLabelManager = null

func _ready() -> void:
	_setup_selection_manager()
	_setup_path_execution_manager()
	_setup_idle_manager()
	_setup_fog_of_war()
	_setup_enemy_visibility_system()
	_setup_context_menu()
	_setup_path_drawer()
	_setup_path_mode_controller()
	_setup_controllers()
	_setup_control_buttons()
	_setup_marker_edit_panel()
	_setup_label_manager()
	_populate_dropdown()
	character_dropdown.item_selected.connect(_on_team_selected)

	# Spawn 2 CT characters at different positions
	_spawn_initial_characters()

	# Apply initial vision state (OFF by default)
	_apply_vision_state()


func _setup_selection_manager() -> void:
	selection_manager = CharacterSelectionManager.new()
	selection_manager.name = "SelectionManager"
	add_child(selection_manager)
	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.primary_changed.connect(_on_primary_changed)


func _setup_path_execution_manager() -> void:
	path_execution_manager = PathExecutionManager.new()
	path_execution_manager.name = "PathExecutionManager"
	add_child(path_execution_manager)
	path_execution_manager.setup(self)
	path_execution_manager.path_confirmed.connect(_on_path_confirmed)
	path_execution_manager.all_paths_completed.connect(_on_all_paths_completed)
	path_execution_manager.paths_cleared.connect(_on_paths_cleared)


func _setup_idle_manager() -> void:
	idle_manager = IdleCharacterManager.new()
	idle_manager.name = "IdleCharacterManager"
	add_child(idle_manager)
	idle_manager.setup(
		characters,
		func(c): return path_execution_manager.is_character_following_path(c),
		func(): return selection_manager.primary_character
	)


func _setup_path_mode_controller() -> void:
	path_mode_controller = PathModeController.new()
	path_mode_controller.name = "PathModeController"
	add_child(path_mode_controller)
	path_mode_controller.setup(path_drawer, selection_manager, path_execution_manager)
	path_mode_controller.mode_started.connect(_on_path_mode_started)
	path_mode_controller.mode_ended.connect(_on_path_mode_ended)
	path_mode_controller.mode_cancelled.connect(_on_path_mode_cancelled)
	path_mode_controller.path_ready.connect(_on_path_ready)


func _setup_controllers() -> void:
	# CharacterRotationController
	rotation_controller = Node.new()
	rotation_controller.set_script(RotationCtrl)
	rotation_controller.name = "RotationController"
	add_child(rotation_controller)
	rotation_controller.rotation_confirmed.connect(_on_rotation_confirmed)
	rotation_controller.rotation_cancelled.connect(_on_rotation_cancelled)


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
	path_drawer.mode_changed.connect(_on_path_mode_changed)
	path_drawer.vision_point_added.connect(_on_vision_point_added)
	path_drawer.run_segment_added.connect(_on_run_segment_added)


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


func _setup_marker_edit_panel() -> void:
	# MarkerEditPanelを動的に作成
	marker_edit_panel = VBoxContainer.new()
	marker_edit_panel.set_script(MarkerEditPanelScript)
	marker_edit_panel.name = "MarkerEditPanel"
	ui_layer.add_child(marker_edit_panel)

	# 右側に配置
	marker_edit_panel.anchor_left = 1.0
	marker_edit_panel.anchor_right = 1.0
	marker_edit_panel.anchor_top = 0.0
	marker_edit_panel.anchor_bottom = 0.0
	marker_edit_panel.offset_left = -240
	marker_edit_panel.offset_right = -10
	marker_edit_panel.offset_top = 10

	# シグナル接続
	marker_edit_panel.character_selected.connect(_on_marker_panel_character_selected)
	marker_edit_panel.vision_add_requested.connect(_on_marker_panel_vision_add)
	marker_edit_panel.vision_undo_requested.connect(_on_marker_panel_vision_undo)
	marker_edit_panel.run_add_requested.connect(_on_marker_panel_run_add)
	marker_edit_panel.run_undo_requested.connect(_on_marker_panel_run_undo)
	marker_edit_panel.confirm_requested.connect(_on_marker_panel_confirm)
	marker_edit_panel.cancel_requested.connect(_on_marker_panel_cancel)

	# 初期状態は非表示
	marker_edit_panel.visible = false


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
	path_mode_controller.confirm()


## キャンセルボタン
func _on_cancel_button_pressed() -> void:
	path_mode_controller.cancel()


## 全員実行ボタン
func _on_execute_walk_button_pressed() -> void:
	_execute_all_paths(false)


## 全パスクリアボタン
func _on_clear_paths_button_pressed() -> void:
	path_execution_manager.clear_all_pending_paths()


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
	# MarkerEditPanelも更新
	if marker_edit_panel:
		marker_edit_panel.on_vision_point_added()


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
	# MarkerEditPanelも更新
	if marker_edit_panel:
		marker_edit_panel.on_run_segment_added()


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
	# MarkerEditPanelを使用するため、旧path_panelは常に非表示
	if path_panel:
		path_panel.visible = false
	# ラベル更新のみ実行
	_update_vision_label()
	_update_run_label()


## ========================================
## 選択マネージャーコールバック
## ========================================

func _on_selection_changed(_selected: Array[Node], _primary: Node) -> void:
	_update_selection_info()


func _on_primary_changed(character: Node) -> void:
	current_character = character


## ========================================
## パス実行マネージャーコールバック
## ========================================

func _on_path_confirmed(_count: int) -> void:
	_update_pending_paths_label()


func _on_all_paths_completed() -> void:
	_update_mode_info("")
	_update_pending_paths_label()


func _on_paths_cleared() -> void:
	_update_pending_paths_label()


## ========================================
## パスモードコントローラーコールバック
## ========================================

func _on_path_mode_started(character: Node) -> void:
	var target_count = path_mode_controller.get_target_count()
	if target_count == 1:
		_update_mode_info("Path Mode: Draw path (ESC to cancel)")
	else:
		_update_mode_info("Path Mode: Draw path for %d characters (ESC to cancel)" % target_count)

	# MarkerEditPanelは後でパス描画完了時に表示（_on_path_readyで）


func _on_path_mode_ended() -> void:
	if path_panel:
		path_panel.visible = false
	if marker_edit_panel:
		marker_edit_panel.visible = false
		marker_edit_panel.clear()
	_update_mode_info("")


func _on_path_mode_cancelled() -> void:
	if path_panel:
		path_panel.visible = false
	if marker_edit_panel:
		marker_edit_panel.visible = false
		marker_edit_panel.clear()
	_update_mode_info("")


func _on_path_ready() -> void:
	# 視線ポイントモードへ移行
	if path_drawer.start_vision_mode():
		_update_mode_info("Vision Mode: Click on path to set look direction")
		_update_path_panel_visibility()

		# マルチセレクトの場合はMarkerEditPanelを表示、それ以外は従来のPathPanelを表示
		if path_drawer.is_multi_character_mode():
			marker_edit_panel.visible = true
			path_panel.visible = false
		else:
			marker_edit_panel.visible = true  # シングルでもMarkerEditPanelを使用
			path_panel.visible = false


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


## キャラクターに色を割り当てラベルを設定
func _assign_character_color_and_label(character: Node) -> void:
	if not character:
		return

	# 敵キャラクターには色を割り当てない
	if PlayerState.is_enemy(character):
		return

	# 色を割り当て
	var color_index = CharacterColorManager.assign_color(character)
	if color_index == -1:
		# 色が割り当てられなかった場合はデフォルトラベルのみ
		label_manager.add_label(character)
		return

	# ラベルを追加
	label_manager.add_label(character)

	# ラベルに色とテキストを適用
	var color = CharacterColorManager.get_character_color(character)
	var label_char = CharacterColorManager.get_character_label(character)
	label_manager.set_label_color(character, color)
	label_manager.set_label_text(character, label_char)


## チーム変更時に色とラベルを再割り当て
func _refresh_character_colors() -> void:
	# 全ての色割り当てをクリア
	CharacterColorManager.clear_all()

	# 全ラベルをクリア
	label_manager.clear_all()

	# 味方キャラクターに色とラベルを再割り当て
	for character in characters:
		_assign_character_color_and_label(character)


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
	selection_manager.deselect_all()  # 敵を選択中だった場合に解除
	_refresh_character_colors()  # 色を再割り当て（味方のみ）
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
			_assign_character_color_and_label(ct1)
			print("[Test] Spawned CT 1: %s at (-3, 0, -2)" % cts[0].display_name)

		# 2体目のCT（位置: -3, 0, 2）
		var ct_index = 1 if cts.size() > 1 else 0
		var ct2 = CharacterRegistry.create_character(cts[ct_index].id, Vector3(-3, 0, 2))
		if ct2:
			add_child(ct2)
			characters.append(ct2)
			_setup_character_vision_for(ct2)
			_assign_character_color_and_label(ct2)
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
			_assign_character_color_and_label(t1)
			print("[Test] Spawned T 1: %s at (3, 0, -2)" % ts[0].display_name)

		# 2体目のT（位置: 3, 0, 2）
		var t_index = 1 if ts.size() > 1 else 0
		var t2 = CharacterRegistry.create_character(ts[t_index].id, Vector3(3, 0, 2))
		if t2:
			add_child(t2)
			characters.append(t2)
			_setup_character_vision_for(t2)
			_assign_character_color_and_label(t2)
			print("[Test] Spawned T 2: %s at (3, 0, 2)" % ts[t_index].display_name)
	else:
		print("[Test] No T characters available")

	# 最初のキャラクターをcurrent_characterに設定
	if characters.size() > 0:
		current_character = characters[0]
		if cts.size() >= 1:
			_update_info_label(cts[0].id)

	# IdleManagerにキャラクターリストを更新
	if idle_manager:
		idle_manager.set_characters(characters)


func _spawn_character(preset_id: String) -> void:
	# Unregister old vision from FoW
	if current_character and current_character.vision and fog_of_war_system:
		fog_of_war_system.unregister_vision(current_character.vision)

	# Unregister from EnemyVisibilitySystem before deletion
	if current_character and enemy_visibility_system:
		enemy_visibility_system.unregister_character(current_character)

	# Remove current character label and release color
	if current_character:
		label_manager.remove_label(current_character)
		CharacterColorManager.release_color(current_character)

	# Remove current character
	if current_character:
		characters.erase(current_character)
		if idle_manager:
			idle_manager.remove_character(current_character)
		current_character.queue_free()
		current_character = null

	# Create new character
	current_character = CharacterRegistry.create_character(preset_id, Vector3.ZERO)
	if current_character:
		add_child(current_character)
		characters.append(current_character)
		if idle_manager:
			idle_manager.add_character(current_character)
		selection_manager.deselect_all()  # 生成時は未選択状態
		_setup_character_vision()
		_assign_character_color_and_label(current_character)
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

	# Wait for VisionComponent to initialize using call_deferred
	# Note: Using call_deferred instead of await to avoid async function call issues
	if vision:
		_complete_vision_setup.call_deferred(character)
	else:
		_complete_vision_setup(character)


## 視界セットアップの完了処理（call_deferred用）
func _complete_vision_setup(character: Node) -> void:
	if not character or not is_instance_valid(character):
		return

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
		# Enable automatic firing
		character.combat_awareness.enable_firing()

	# Apply current vision state
	var vision = character.vision
	if not is_vision_enabled and vision:
		vision.disable()
		if fog_of_war_system:
			fog_of_war_system.set_fog_visible(false)

	# Set default weapon to pistol with aiming pose
	var anim_ctrl = character.get_anim_controller()
	if anim_ctrl:
		anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
		anim_ctrl.set_aiming(true)

	# Equip Glock
	_equip_glock(character)


## キャラクターにGlockを装備
func _equip_glock(character: Node) -> void:
	if not character:
		return

	var model = character.get_node_or_null("CharacterModel")
	if not model:
		return

	var skeleton = _find_skeleton_in(model)
	if not skeleton:
		return

	var bone_idx = skeleton.find_bone("mixamorig_RightHand")
	if bone_idx < 0:
		return

	# Create BoneAttachment3D
	var attachment = BoneAttachment3D.new()
	attachment.name = "WeaponAttachment"
	attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(attachment)

	# Load Glock
	var weapon_resource = load("res://assets/weapons/glock/glock.glb")
	if not weapon_resource:
		print("[Weapon] Failed to load Glock")
		return

	var weapon = weapon_resource.instantiate()
	weapon.name = "Glock"
	weapon.scale = Vector3.ONE * 100.0  # Skeleton compensation (Mixamo is 0.01)
	weapon.rotation_degrees = Vector3(-79, -66, -28)
	weapon.position = Vector3(1, 7, 2)
	attachment.add_child(weapon)


## モデル内のSkeleton3Dを検索
func _find_skeleton_in(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton_in(child)
		if result:
			return result
	return null


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
		return

	# パスモード中：パス描画後にキャラクター以外をクリックでキャンセル
	if path_mode_controller.is_path_mode() and event is InputEventMouseButton and event.pressed:
		if path_drawer.has_pending_path():
			var clicked_character = _raycast_character(event.position)
			path_mode_controller.handle_click_to_cancel(clicked_character)
		return

	# マウス/タッチ処理（回転モード以外、パスモード以外）
	# Note: _unhandled_input を使用することで、UIが入力を消費した後のみ処理される
	if event is InputEventMouseButton and event.pressed:
		if not rotation_controller.is_rotation_active() and not path_mode_controller.is_path_mode():
			_handle_mouse_click(event)


func _input(event: InputEvent) -> void:
	# ESCキー処理（モードキャンセル）
	if event.is_action_pressed("ui_cancel"):
		if path_execution_manager.is_any_path_following_active():
			path_execution_manager.cancel_all_path_following()
			_update_mode_info("")
		elif rotation_controller.is_rotation_active():
			_on_rotate_cancel_pressed()

	# Note: マウスクリック処理は _unhandled_input に移動（UIが入力を消費できるようにするため）

	var primary = selection_manager.primary_character
	if not primary:
		return

	var anim_ctrl = primary.get_anim_controller()
	if not anim_ctrl:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)
			KEY_2:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
			KEY_K:
				primary.take_damage(primary.max_health)
			KEY_R:
				# Respawn primary character
				if primary.has_method("reset_health"):
					primary.reset_health()


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
				selection_manager.toggle_selection(clicked_character)
				# 選択中の場合のみコンテキストメニュー表示
				if selection_manager.selected_characters.has(clicked_character):
					_show_context_menu(event.position, clicked_character)
			else:
				# キャラクター以外をクリック: メニューを閉じて全選択解除
				if context_menu and context_menu.is_open():
					context_menu.close()
				selection_manager.deselect_all()


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


## 選択情報を更新
func _update_selection_info() -> void:
	var selected = selection_manager.selected_characters
	var primary = selection_manager.primary_character

	if selected.size() == 0:
		info_label.text = "[Player Team: %s]\nTap a character to select" % PlayerState.get_team_name()
	elif selected.size() == 1:
		var preset_id = _get_character_preset_id(primary)
		if preset_id:
			_update_info_label(preset_id)
	else:
		var player_team_name = PlayerState.get_team_name()
		info_label.text = """[Player Team: %s]
Selected: %d characters

Tap character to toggle selection
Tap ground to deselect all""" % [player_team_name, selected.size()]


## キャラクターのプリセットIDを取得
func _get_character_preset_id(character: Node) -> String:
	if not character:
		return ""
	if character.has_method("get_preset_id"):
		return character.get_preset_id()
	# プリセットIDがない場合は名前から推測
	return character.name.to_snake_case()


## コンテキストメニューを表示
func _show_context_menu(screen_pos: Vector2, character: Node) -> void:
	if context_menu:
		var is_multi = selection_manager.get_selection_count() > 1
		context_menu.open(screen_pos, character, is_multi)


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
	var primary = selection_manager.primary_character
	if not primary:
		print("[ContextMenu] No primary character selected")
		return

	# 選択中のキャラクター配列を取得
	var selected_chars: Array[Node] = []
	for c in selection_manager.selected_characters:
		selected_chars.append(c)

	# プライマリキャラクターの色を取得
	var char_color = CharacterColorManager.get_character_color(primary)

	# パスモード開始（enable()→clear()でリセットされる）
	path_mode_controller.start(primary, char_color)

	# マルチセレクトの場合、clear()後にマルチモードを初期化
	if selected_chars.size() > 1:
		path_drawer.start_multi_character_mode(selected_chars)
		marker_edit_panel.setup(selected_chars, path_drawer)
	else:
		# シングルセレクトの場合
		path_drawer.set_active_edit_character(primary)
		marker_edit_panel.setup(selected_chars, path_drawer)


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
	path_execution_manager.process_controllers(delta)

	# パス追従していない全キャラクターのアイドル状態を維持
	idle_manager.process_idle_characters(delta)

	# 回転モード中はコントローラーに処理を委譲
	if rotation_controller.is_rotation_active():
		rotation_controller.process(delta)
		return

	var primary = selection_manager.primary_character
	if not primary:
		return

	if not primary.is_alive:
		return

	# パス追従中のキャラクターは手動操作をスキップ
	if path_execution_manager.is_character_following_path(primary):
		return

	var anim_ctrl = primary.get_anim_controller()
	if not anim_ctrl:
		return

	# デバッグ操作が無効の場合はマウスエイムも停止
	if is_debug_control_enabled:
		_update_aim_position()

	# パスモード中は現在の向きを維持
	if path_mode_controller.is_path_mode():
		var current_look_dir = anim_ctrl.get_look_direction()
		anim_ctrl.update_animation(Vector3.ZERO, current_look_dir, false, delta)
		return

	# デバッグ操作が無効の場合はIdleManagerに処理を委譲
	if not is_debug_control_enabled:
		idle_manager.process_primary_idle(primary, delta)
		return

	# Get input
	var move_dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var aim_dir: Vector3 = aim_position - primary.global_position
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

	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		aim_position = intersection


## ========================================
## MarkerEditPanel コールバック
## ========================================

func _on_marker_panel_character_selected(character: Node) -> void:
	# PathDrawerの色を更新
	var char_color = CharacterColorManager.get_character_color(character)
	path_drawer.set_character_color(char_color)


func _on_marker_panel_vision_add(_character: Node) -> void:
	if path_drawer.has_pending_path():
		path_drawer.start_vision_mode()
		_update_vision_label()
		print("[MarkerPanel] Vision mode activated")


func _on_marker_panel_vision_undo(_character: Node) -> void:
	path_drawer.remove_last_vision_point()
	_update_vision_label()


func _on_marker_panel_run_add(_character: Node) -> void:
	if path_drawer.has_pending_path():
		path_drawer.start_run_mode()
		_update_run_label()
		print("[MarkerPanel] Run marker mode activated")


func _on_marker_panel_run_undo(_character: Node) -> void:
	path_drawer.remove_last_run_segment()
	_update_run_label()


func _on_marker_panel_confirm() -> void:
	path_mode_controller.confirm()


func _on_marker_panel_cancel() -> void:
	path_mode_controller.cancel()


## ========================================
## パスシステム
## ========================================

## パスモード変更時
func _on_path_mode_changed(mode: int) -> void:
	if mode == 0:  # MOVEMENT
		_update_mode_info("Path Mode: Draw path")
		_update_path_panel_visibility()
	else:  # VISION_POINT
		var count = path_drawer.get_vision_point_count()
		_update_mode_info("Vision Mode: %d vision points" % count)
		_update_path_panel_visibility()


## 全キャラクターのパスを同時実行
func _execute_all_paths(run: bool) -> void:
	var count = path_execution_manager.execute_all_paths(run)
	if count > 0:
		_update_mode_info("Executing %d paths..." % count)


## 保留パス数ラベルを更新
func _update_pending_paths_label() -> void:
	if pending_paths_label:
		pending_paths_label.text = "Pending: %d paths" % path_execution_manager.get_pending_path_count()


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
