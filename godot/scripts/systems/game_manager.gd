extends Node
class_name GameManager
## コアゲームシステム管理
## システムの初期化・更新・入力処理・UI管理を一元管理

const AnimCtrl = preload("res://scripts/animation/character_animation_controller.gd")
const FogOfWarSystemScript = preload("res://scripts/systems/fog_of_war_system.gd")
const EnemyVisibilitySystemScript = preload("res://scripts/systems/enemy_visibility_system.gd")
const MapManagerScript = preload("res://scripts/systems/map_manager.gd")
const PathDrawerScript = preload("res://scripts/effects/path_drawer.gd")
const RotationCtrl = preload("res://scripts/characters/character_rotation_controller.gd")
const ContextMenuScript = preload("res://scripts/ui/context_menu_component.gd")
const MarkerEditPanelScript = preload("res://scripts/ui/marker_edit_panel.gd")

## UI接続用シグナル
signal selection_changed(selected: Array[Node], primary: Node)
signal primary_changed(character: Node)
signal path_mode_started(character: Node)
signal path_mode_ended()
signal path_mode_cancelled()
signal path_ready()
signal path_confirmed(count: int)
signal all_paths_completed()
signal paths_cleared()
signal rotation_confirmed(direction: Vector3)
signal rotation_cancelled()
signal path_mode_changed(mode: int)
signal vision_point_added(anchor: Vector3, direction: Vector3)
signal run_segment_added(start_ratio: float, end_ratio: float)
## コンテキストメニュー操作シグナル
signal context_action_requested(action_id: String, character: Node)

## コアシステム
var selection_manager: CharacterSelectionManager = null
var path_execution_manager: PathExecutionManager = null
var idle_manager: IdleCharacterManager = null
var path_mode_controller: PathModeController = null
var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null
var map_manager: MapManager = null
var path_drawer: Node3D = null
var rotation_controller: Node = null

## UIコンポーネント
var context_menu: Control = null
var marker_edit_panel: VBoxContainer = null
var label_manager: CharacterLabelManager = null

## 外部参照
var camera: Camera3D = null
var characters: Array[Node] = []
var _mesh_parent: Node3D = null
var _map_container: Node3D = null
var _ui_layer: CanvasLayer = null

## 設定
var fow_map_size: Vector2 = Vector2(50, 50)
var default_vision_fov: float = 90.0
var default_vision_range: float = 15.0
var default_weapon_id: String = "glock"
var is_vision_enabled: bool = false

## 内部
var _ground_plane := Plane(Vector3.UP, 0)


## セットアップ（カメラ、メッシュ親、UIレイヤーを指定）
## map_container: マップを追加する親ノード（省略時はmesh_parentを使用）
func setup(cam: Camera3D, mesh_parent: Node3D, ui_layer: CanvasLayer, map_size: Vector2 = Vector2(50, 50), map_container: Node3D = null) -> void:
	camera = cam
	_mesh_parent = mesh_parent
	_map_container = map_container if map_container else mesh_parent
	_ui_layer = ui_layer
	fow_map_size = map_size

	# 初期化順序が重要
	_setup_selection_manager()
	_setup_path_execution_manager(mesh_parent)
	_setup_idle_manager()
	_setup_path_drawer()
	_setup_path_mode_controller()
	_setup_rotation_controller()
	_setup_fog_of_war()
	_setup_enemy_visibility_system()
	_setup_map_manager()
	_setup_context_menu()
	_setup_marker_edit_panel()
	_setup_label_manager()

	print("[GameManager] Setup complete - 12 systems initialized")


## キャラクターを登録（視界・武器・色・ラベルも自動セットアップ）
func register_character(character: Node) -> void:
	if characters.has(character):
		return

	characters.append(character)
	if idle_manager:
		idle_manager.add_character(character)

	# 視界セットアップ
	_setup_character_vision(character)

	print("[GameManager] Registered character: %s" % character.name)


## キャラクターを登録解除
func unregister_character(character: Node) -> void:
	if not characters.has(character):
		return

	characters.erase(character)
	if idle_manager:
		idle_manager.remove_character(character)

	# 視界システムから解除
	if character.vision and fog_of_war_system:
		fog_of_war_system.unregister_vision(character.vision)
	if enemy_visibility_system:
		enemy_visibility_system.unregister_character(character)

	# ラベル削除・色解放
	if label_manager:
		label_manager.remove_label(character)
	CharacterColorManager.release_color(character)

	# 選択解除
	if selection_manager:
		selection_manager.remove_from_selection(character)

	print("[GameManager] Unregistered character: %s" % character.name)


## ========================================
## 入力処理
## ========================================

## マウス/タッチクリック処理（シーンから呼び出す）
func handle_click(screen_pos: Vector2, button_index: int) -> bool:
	# コンテキストメニューが開いている場合、メニューUI上のクリックは無視
	if context_menu and context_menu.is_open():
		if _is_point_over_context_menu(screen_pos):
			return true  # 入力を消費

	var clicked_character = raycast_character(screen_pos)

	match button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if clicked_character:
				# 敵キャラクターは無視
				if PlayerState.is_enemy(clicked_character):
					return false
				# 味方キャラクタークリック: トグル選択 + コンテキストメニュー表示
				selection_manager.toggle_selection(clicked_character)
				# 選択中の場合のみコンテキストメニュー表示
				if selection_manager.selected_characters.has(clicked_character):
					_show_context_menu(screen_pos, clicked_character)
				return true
			else:
				# キャラクター以外をクリック: メニューを閉じて全選択解除
				if context_menu and context_menu.is_open():
					context_menu.close()
				selection_manager.deselect_all()
				return true
	return false


## レイキャストでキャラクターを検出
func raycast_character(screen_pos: Vector2) -> Node:
	if not camera:
		return null

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_dir * 100.0

	var space_state := _mesh_parent.get_world_3d().direct_space_state
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


## マウス位置がコンテキストメニュー上かどうか
func _is_point_over_context_menu(screen_pos: Vector2) -> bool:
	if not context_menu or not context_menu.is_open():
		return false
	var panel_rect = context_menu.get_panel_rect()
	return panel_rect.has_point(screen_pos)


## ノードが親の子孫かどうか
func _is_child_of(child: Node, parent: Node) -> bool:
	var node = child
	while node:
		if node == parent:
			return true
		node = node.get_parent()
	return false


## ========================================
## パスモード操作
## ========================================

## 移動モード開始（選択中キャラクターでパス描画）
func start_move_mode() -> bool:
	var primary = selection_manager.primary_character
	if not primary:
		print("[GameManager] No primary character selected")
		return false

	# 選択中のキャラクター配列を取得
	var selected_chars: Array[Node] = []
	for c in selection_manager.selected_characters:
		selected_chars.append(c)

	# プライマリキャラクターの色を取得
	var char_color = CharacterColorManager.get_character_color(primary)

	# パスモード開始
	if not path_mode_controller.start(primary, char_color):
		return false

	# マルチセレクトの場合
	if selected_chars.size() > 1:
		path_drawer.start_multi_character_mode(selected_chars)
		marker_edit_panel.setup(selected_chars, path_drawer)
	else:
		path_drawer.set_active_edit_character(primary)
		marker_edit_panel.setup(selected_chars, path_drawer)

	return true


## パスモード開始（外部指定）
func start_path_mode(primary: Node, char_color: Color = Color.WHITE) -> bool:
	if not path_mode_controller:
		return false
	return path_mode_controller.start(primary, char_color)


## パスモード確定
func confirm_path() -> void:
	if path_mode_controller:
		path_mode_controller.confirm()


## パスモードキャンセル
func cancel_path() -> void:
	if path_mode_controller:
		path_mode_controller.cancel()


## 全パスを実行
func execute_all_paths(run: bool) -> int:
	if not path_execution_manager:
		return 0
	return path_execution_manager.execute_all_paths(run)


## 全保留パスをクリア
func clear_all_pending_paths() -> void:
	if path_execution_manager:
		path_execution_manager.clear_all_pending_paths()


## 全パス追従キャンセル
func cancel_all_path_following() -> void:
	if path_execution_manager:
		path_execution_manager.cancel_all_path_following()


## ========================================
## 回転モード操作
## ========================================

## 回転モード開始
func start_rotation_mode(character: Node) -> void:
	if not rotation_controller or not camera:
		return
	rotation_controller.setup(character as CharacterBody3D, camera)
	rotation_controller.start_rotation()


## 回転入力処理
func handle_rotation_input(screen_pos: Vector2) -> void:
	if rotation_controller and rotation_controller.is_rotation_active():
		rotation_controller.handle_input(screen_pos)


## 回転確定
func confirm_rotation() -> void:
	if rotation_controller:
		rotation_controller.confirm()


## 回転キャンセル
func cancel_rotation() -> void:
	if rotation_controller:
		rotation_controller.cancel()


## ========================================
## 視界/FoW制御
## ========================================

## 視界/FoWの有効化切り替え
func set_vision_enabled(enabled: bool) -> void:
	is_vision_enabled = enabled

	# FogOfWarSystemの表示を切り替え
	if fog_of_war_system:
		fog_of_war_system.set_fog_visible(enabled)

	# EnemyVisibilitySystemのモードを切り替え
	if enemy_visibility_system:
		if enabled:
			enemy_visibility_system.enable_full()
		else:
			enemy_visibility_system.enable_lightweight()


## ========================================
## マップ管理（MapManager委譲）
## ========================================

## マップをロード
## auto_cleanup: 既存マップの自動クリーンアップ（デフォルトtrue）
## Returns: マップインスタンス、失敗時はnull
func load_map(map_preset_id: String, auto_cleanup: bool = true) -> Node3D:
	if map_manager:
		return map_manager.load_map(map_preset_id, auto_cleanup)
	push_error("[GameManager] MapManager not initialized")
	return null


## マップをアンロード
func unload_map(cleanup_characters: bool = true) -> void:
	if map_manager:
		map_manager.unload_map(cleanup_characters)


## マップを切り替え
## Returns: 新しいマップインスタンス、失敗時はnull
func switch_map(new_map_id: String) -> Node3D:
	if map_manager:
		return map_manager.switch_map(new_map_id)
	return null


## マップがロードされているか
func has_map() -> bool:
	return map_manager and map_manager.has_map()


## 現在のマップIDを取得
func get_current_map_id() -> String:
	return map_manager.current_map_id if map_manager else ""


## 現在のマップサイズを取得
func get_map_size() -> Vector2:
	return map_manager.get_map_size() if map_manager else Vector2.ZERO


## スポーン位置を取得（現在のマップから）
func get_spawn_points(is_ct: bool) -> Array[Vector3]:
	return map_manager.get_spawn_points(is_ct) if map_manager else []


## スポーン位置を取得（任意のマップIDから）
func get_spawn_points_for_map(map_preset_id: String, is_ct: bool) -> Array[Vector3]:
	var preset = MapRegistry.get_preset(map_preset_id)
	if not preset:
		return []
	return preset.spawn_points_ct if is_ct else preset.spawn_points_t


## ========================================
## 毎フレーム処理
## ========================================

## 毎フレーム処理（_physics_processから呼ぶ）
func process_frame(delta: float) -> void:
	# パス追従コントローラーを処理
	if path_execution_manager:
		path_execution_manager.process_controllers(delta)

	# アイドルキャラクターを処理
	if idle_manager:
		idle_manager.process_idle_characters(delta)

	# 回転モード処理
	if rotation_controller and rotation_controller.is_rotation_active():
		rotation_controller.process(delta)


## ========================================
## 状態取得API
## ========================================

## 回転モード中か
func is_rotation_active() -> bool:
	return rotation_controller and rotation_controller.is_rotation_active()


## パスモード中か
func is_path_mode() -> bool:
	return path_mode_controller and path_mode_controller.is_path_mode()


## パス追従中のキャラクターがいるか
func is_any_path_following_active() -> bool:
	return path_execution_manager and path_execution_manager.is_any_path_following_active()


## 指定キャラクターがパス追従中か
func is_character_following_path(character: Node) -> bool:
	return path_execution_manager and path_execution_manager.is_character_following_path(character)


## 保留パス数を取得
func get_pending_path_count() -> int:
	return path_execution_manager.get_pending_path_count() if path_execution_manager else 0


## 回転中のキャラクターを取得
func get_rotating_character() -> Node:
	return rotation_controller.get_character() if rotation_controller else null


## パスモード対象数を取得
func get_path_target_count() -> int:
	return path_mode_controller.get_target_count() if path_mode_controller else 0


## プライマリキャラクターを取得
func get_primary_character() -> Node:
	return selection_manager.primary_character if selection_manager else null


## 選択中キャラクター数を取得
func get_selection_count() -> int:
	return selection_manager.get_selection_count() if selection_manager else 0


## ========================================
## PathDrawer委譲API
## ========================================

## パス描画済みか
func has_pending_path() -> bool:
	return path_drawer and path_drawer.has_pending_path()


## 視線モード開始
func start_vision_mode() -> bool:
	return path_drawer.start_vision_mode() if path_drawer else false


## 視線ポイントを削除
func remove_last_vision_point() -> void:
	if path_drawer:
		path_drawer.remove_last_vision_point()


## Runモード開始
func start_run_mode() -> void:
	if path_drawer:
		path_drawer.start_run_mode()


## 最後のRun区間を削除
func remove_last_run_segment() -> void:
	if path_drawer:
		path_drawer.remove_last_run_segment()


## 視線ポイント数を取得
func get_vision_point_count() -> int:
	return path_drawer.get_vision_point_count() if path_drawer else 0


## Run区間数を取得
func get_run_segment_count() -> int:
	return path_drawer.get_run_segment_count() if path_drawer else 0


## 未完了のRun開始点があるか
func has_incomplete_run_start() -> bool:
	return path_drawer.has_incomplete_run_start() if path_drawer else false


## マルチキャラクターモードか
func is_multi_character_mode() -> bool:
	return path_drawer.is_multi_character_mode() if path_drawer else false


## マルチキャラクターモード開始
func start_multi_character_mode(selected_chars: Array[Node]) -> void:
	if path_drawer:
		path_drawer.start_multi_character_mode(selected_chars)


## アクティブ編集キャラクターを設定
func set_active_edit_character(character: Node) -> void:
	if path_drawer:
		path_drawer.set_active_edit_character(character)


## キャラクター色を設定
func set_path_drawer_color(color: Color) -> void:
	if path_drawer:
		path_drawer.set_character_color(color)


## ========================================
## UI管理
## ========================================

## コンテキストメニューを表示
func _show_context_menu(screen_pos: Vector2, character: Node) -> void:
	if context_menu:
		var is_multi = selection_manager.get_selection_count() > 1
		context_menu.open(screen_pos, character, is_multi)


## マーカーパネルを表示
func show_marker_panel() -> void:
	if marker_edit_panel:
		marker_edit_panel.visible = true


## マーカーパネルを非表示
func hide_marker_panel() -> void:
	if marker_edit_panel:
		marker_edit_panel.visible = false
		marker_edit_panel.clear()


## 回転パネル表示状態を取得（外部UI用）
func is_context_menu_open() -> bool:
	return context_menu and context_menu.is_open()


## ========================================
## キャラクターセットアップ（内部）
## ========================================

## キャラクターの視界をセットアップ
func _setup_character_vision(character: Node) -> void:
	if not character:
		return

	# Setup vision component
	var vision = character.setup_vision(default_vision_fov, default_vision_range)

	# 遅延セットアップ
	if vision:
		_complete_character_setup.call_deferred(character)
	else:
		_complete_character_setup(character)


## キャラクターセットアップ完了処理
func _complete_character_setup(character: Node) -> void:
	if not character or not is_instance_valid(character):
		return

	# EnemyVisibilitySystemに登録
	if enemy_visibility_system:
		enemy_visibility_system.register_character(character)

	# Combat awarenessセットアップ
	character.setup_combat_awareness()
	if character.combat_awareness:
		character.combat_awareness.enemy_spotted.connect(
			func(enemy): print("[Combat] %s spotted %s" % [character.name, enemy.name])
		)
		character.combat_awareness.enemy_lost.connect(
			func(enemy): print("[Combat] %s lost sight of %s" % [character.name, enemy.name])
		)
		character.combat_awareness.enable_firing()

	# 視界状態を適用
	var vision = character.vision
	if not is_vision_enabled and vision:
		vision.disable()
		if fog_of_war_system:
			fog_of_war_system.set_fog_visible(false)

	# デフォルト武器を装備
	var anim_ctrl = character.get_anim_controller()
	if anim_ctrl:
		anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)

	var default_weapon = WeaponRegistry.get_preset(default_weapon_id)
	if default_weapon:
		_equip_weapon(character, default_weapon)

	# 味方の場合、色とラベルを割り当て
	if not PlayerState.is_enemy(character):
		_assign_color_and_label(character)


## 武器を装備
func _equip_weapon(character: Node, weapon_preset: Resource) -> void:
	if not character or not weapon_preset:
		return

	if character.has_method("equip_weapon"):
		character.equip_weapon(weapon_preset)


## 色とラベルを割り当て
func _assign_color_and_label(character: Node) -> void:
	if not character:
		return

	# 敵には割り当てない
	if PlayerState.is_enemy(character):
		return

	# 色を割り当て
	var color_index = CharacterColorManager.assign_color(character)
	if color_index == -1:
		if label_manager:
			label_manager.add_label(character)
		return

	# ラベルを追加
	if label_manager:
		label_manager.add_label(character)
		var color = CharacterColorManager.get_character_color(character)
		var label_char = CharacterColorManager.get_character_label(character)
		label_manager.set_label_color(character, color)
		label_manager.set_label_text(character, label_char)


## 全キャラクターの色・ラベルを再割り当て
func refresh_character_colors() -> void:
	CharacterColorManager.clear_all()
	if label_manager:
		label_manager.clear_all()
	for character in characters:
		_assign_color_and_label(character)


## ========================================
## 内部：システムセットアップ
## ========================================

func _setup_selection_manager() -> void:
	selection_manager = CharacterSelectionManager.new()
	selection_manager.name = "SelectionManager"
	add_child(selection_manager)
	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.primary_changed.connect(_on_primary_changed)


func _setup_path_execution_manager(mesh_parent: Node3D) -> void:
	path_execution_manager = PathExecutionManager.new()
	path_execution_manager.name = "PathExecutionManager"
	add_child(path_execution_manager)
	path_execution_manager.setup(mesh_parent)
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


func _setup_path_drawer() -> void:
	path_drawer = Node3D.new()
	path_drawer.set_script(PathDrawerScript)
	path_drawer.name = "PathDrawer"
	add_child(path_drawer)
	path_drawer.setup(camera)
	path_drawer.mode_changed.connect(_on_path_mode_changed)
	path_drawer.vision_point_added.connect(_on_vision_point_added)
	path_drawer.run_segment_added.connect(_on_run_segment_added)


func _setup_path_mode_controller() -> void:
	path_mode_controller = PathModeController.new()
	path_mode_controller.name = "PathModeController"
	add_child(path_mode_controller)
	path_mode_controller.setup(path_drawer, selection_manager, path_execution_manager)
	path_mode_controller.mode_started.connect(_on_path_mode_started)
	path_mode_controller.mode_ended.connect(_on_path_mode_ended)
	path_mode_controller.mode_cancelled.connect(_on_path_mode_cancelled)
	path_mode_controller.path_ready.connect(_on_path_ready)


func _setup_rotation_controller() -> void:
	rotation_controller = Node.new()
	rotation_controller.set_script(RotationCtrl)
	rotation_controller.name = "RotationController"
	add_child(rotation_controller)
	rotation_controller.rotation_confirmed.connect(_on_rotation_confirmed)
	rotation_controller.rotation_cancelled.connect(_on_rotation_cancelled)


func _setup_fog_of_war() -> void:
	fog_of_war_system = Node3D.new()
	fog_of_war_system.set_script(FogOfWarSystemScript)
	fog_of_war_system.name = "FogOfWarSystem"
	fog_of_war_system.map_size = fow_map_size
	add_child(fog_of_war_system)


func _setup_enemy_visibility_system() -> void:
	enemy_visibility_system = Node.new()
	enemy_visibility_system.set_script(EnemyVisibilitySystemScript)
	enemy_visibility_system.name = "EnemyVisibilitySystem"
	add_child(enemy_visibility_system)
	enemy_visibility_system.setup(fog_of_war_system)


func _setup_map_manager() -> void:
	map_manager = MapManager.new()
	map_manager.name = "MapManager"
	add_child(map_manager)
	map_manager.setup(_map_container, self)


func _setup_context_menu() -> void:
	context_menu = Control.new()
	context_menu.set_script(ContextMenuScript)
	context_menu.name = "ContextMenu"
	_ui_layer.add_child(context_menu)
	context_menu.setup_default_items()
	context_menu.item_selected.connect(_on_context_menu_item_selected)


func _setup_marker_edit_panel() -> void:
	marker_edit_panel = VBoxContainer.new()
	marker_edit_panel.set_script(MarkerEditPanelScript)
	marker_edit_panel.name = "MarkerEditPanel"
	_ui_layer.add_child(marker_edit_panel)

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

	marker_edit_panel.visible = false


func _setup_label_manager() -> void:
	label_manager = CharacterLabelManager.new()
	label_manager.name = "CharacterLabelManager"
	add_child(label_manager)


## ========================================
## 内部：シグナルハンドラ
## ========================================

func _on_selection_changed(selected: Array[Node], primary: Node) -> void:
	selection_changed.emit(selected, primary)


func _on_primary_changed(character: Node) -> void:
	primary_changed.emit(character)


func _on_path_mode_started(character: Node) -> void:
	path_mode_started.emit(character)


func _on_path_mode_ended() -> void:
	hide_marker_panel()
	path_mode_ended.emit()


func _on_path_mode_cancelled() -> void:
	hide_marker_panel()
	path_mode_cancelled.emit()


func _on_path_ready() -> void:
	# 視線ポイントモードへ移行
	if start_vision_mode():
		# MarkerEditPanelを表示
		show_marker_panel()
	path_ready.emit()


func _on_path_confirmed(count: int) -> void:
	path_confirmed.emit(count)


func _on_all_paths_completed() -> void:
	all_paths_completed.emit()


func _on_paths_cleared() -> void:
	paths_cleared.emit()


func _on_rotation_confirmed(direction: Vector3) -> void:
	# 回転中キャラクターの敵追跡を解除
	var rotating_character = get_rotating_character()
	if rotating_character and rotating_character.combat_awareness:
		rotating_character.combat_awareness.dismiss_current_target()
	rotation_confirmed.emit(direction)


func _on_rotation_cancelled() -> void:
	rotation_cancelled.emit()


func _on_path_mode_changed(mode: int) -> void:
	path_mode_changed.emit(mode)


func _on_vision_point_added(anchor: Vector3, direction: Vector3) -> void:
	if marker_edit_panel:
		marker_edit_panel.on_vision_point_added()
	vision_point_added.emit(anchor, direction)


func _on_run_segment_added(start_ratio: float, end_ratio: float) -> void:
	if marker_edit_panel:
		marker_edit_panel.on_run_segment_added()
	run_segment_added.emit(start_ratio, end_ratio)


func _on_context_menu_item_selected(action_id: String, character: CharacterBody3D) -> void:
	match action_id:
		"move":
			start_move_mode()
		"rotate":
			start_rotation_mode(character)
		"crouch":
			if character.has_method("toggle_crouch"):
				character.toggle_crouch()
		_:
			# その他のアクションは外部に通知
			context_action_requested.emit(action_id, character)


func _on_marker_panel_character_selected(character: Node) -> void:
	var char_color = CharacterColorManager.get_character_color(character)
	set_path_drawer_color(char_color)


func _on_marker_panel_vision_add(_character: Node) -> void:
	if has_pending_path():
		start_vision_mode()


func _on_marker_panel_vision_undo(_character: Node) -> void:
	remove_last_vision_point()


func _on_marker_panel_run_add(_character: Node) -> void:
	if has_pending_path():
		start_run_mode()


func _on_marker_panel_run_undo(_character: Node) -> void:
	remove_last_run_segment()


func _on_marker_panel_confirm() -> void:
	confirm_path()


func _on_marker_panel_cancel() -> void:
	cancel_path()
