extends Node
class_name GameManager
## コアゲームシステム管理
## システムの初期化・更新・入力処理・UI管理を一元管理

const MapManagerScript = preload("res://scripts/systems/map_manager.gd")
const PathDrawerScript = preload("res://scripts/effects/path_drawer.gd")
const RotationCtrl = preload("res://scripts/characters/character_rotation_controller.gd")
const ContextMenuScript = preload("res://scripts/ui/context_menu_component.gd")
const MarkerEditPanelScript = preload("res://scripts/ui/marker_edit_panel.gd")
const WeaponShopModalScript = preload("res://scripts/ui/weapon_shop_modal.gd")
const CharacterSetupServiceScript = preload("res://scripts/systems/character_setup_service.gd")
const PathServiceScript = preload("res://scripts/systems/path_service.gd")
const VisionServiceScript = preload("res://scripts/systems/vision_service.gd")

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
var character_setup_service: CharacterSetupService = null
var path_service: PathService = null
var vision_service: VisionService = null

## UIコンポーネント
var context_menu: Control = null
var marker_edit_panel: VBoxContainer = null
var label_manager: CharacterLabelManager = null
var weapon_shop_modal: Control = null

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
	_setup_vision_service()
	_setup_map_manager()
	_setup_context_menu()
	_setup_marker_edit_panel()
	_setup_weapon_shop_modal()
	_setup_path_service()
	_setup_label_manager()
	_setup_character_setup_service()

	print("[GameManager] Setup complete - 15 systems initialized")


## キャラクターを登録（視界・武器・色・ラベルも自動セットアップ）
func register_character(character: Node) -> void:
	if characters.has(character):
		return

	characters.append(character)
	if idle_manager:
		idle_manager.add_character(character)

	# 視界セットアップ
	if character_setup_service:
		character_setup_service.setup_character(character)

	print("[GameManager] Registered character: %s" % character.name)


## キャラクターを登録解除
func unregister_character(character: Node) -> void:
	if not characters.has(character):
		return

	characters.erase(character)
	if idle_manager:
		idle_manager.remove_character(character)

	# 視界システムから解除
	if vision_service:
		vision_service.unregister_character(character)

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
	return path_service.start_move_mode() if path_service else false


## パスモード開始（外部指定）
func start_path_mode(primary: Node, char_color: Color = Color.WHITE) -> bool:
	return path_service.start_path_mode(primary, char_color) if path_service else false


## パスモード確定
func confirm_path() -> void:
	if path_service:
		path_service.confirm_path()


## パスモードキャンセル
func cancel_path() -> void:
	if path_service:
		path_service.cancel_path()


## 全パスを実行
func execute_all_paths(run: bool) -> int:
	# パス実行開始時にコンテキストメニューを閉じる
	if context_menu and context_menu.is_open():
		context_menu.close()
	return path_service.execute_all_paths(run) if path_service else 0


## 全保留パスをクリア
func clear_all_pending_paths() -> void:
	if path_service:
		path_service.clear_all_pending_paths()


## 全パス追従キャンセル
func cancel_all_path_following() -> void:
	if path_service:
		path_service.cancel_all_path_following()


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
	if character_setup_service:
		character_setup_service.is_vision_enabled = enabled
	if vision_service:
		vision_service.set_enabled(enabled)


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


## 現在のマッププリセットを取得
func get_current_map_preset() -> MapPreset:
	return map_manager.current_preset if map_manager else null


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


## キャラクターを追加する親ノードを取得
func get_character_parent() -> Node3D:
	return _map_container if _map_container else _mesh_parent


## ========================================
## 毎フレーム処理
## ========================================

## 毎フレーム処理（_physics_processから呼ぶ）
func process_frame(delta: float) -> void:
	# パス追従コントローラーを処理
	if path_service:
		path_service.process_controllers(delta)

	# アイドルキャラクターを処理
	if idle_manager:
		idle_manager.process_idle_characters(delta)

	# プライマリキャラクターのアイドル処理（パス追従中でない場合）
	var primary = get_primary_character()
	if primary and idle_manager and not is_character_following_path(primary):
		# 回転モード中でない場合のみ
		if not is_rotation_active():
			idle_manager.process_primary_idle(primary, delta)

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
	return path_service and path_service.is_path_mode()


## パス追従中のキャラクターがいるか
func is_any_path_following_active() -> bool:
	return path_service and path_service.is_any_path_following_active()


## 指定キャラクターがパス追従中か
func is_character_following_path(character: Node) -> bool:
	return path_service and path_service.is_character_following_path(character)


## 保留パス数を取得
func get_pending_path_count() -> int:
	return path_service.get_pending_path_count() if path_service else 0


## 回転中のキャラクターを取得
func get_rotating_character() -> Node:
	return rotation_controller.get_character() if rotation_controller else null


## パスモード対象数を取得
func get_path_target_count() -> int:
	return path_service.get_path_target_count() if path_service else 0


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
	return path_service.has_pending_path() if path_service else false


## 視線モード開始
func start_vision_mode() -> bool:
	return path_service.start_vision_mode() if path_service else false


## 視線ポイントを削除
func remove_last_vision_point() -> void:
	if path_service:
		path_service.remove_last_vision_point()


## Runモード開始
func start_run_mode() -> void:
	if path_service:
		path_service.start_run_mode()


## 最後のRun区間を削除
func remove_last_run_segment() -> void:
	if path_service:
		path_service.remove_last_run_segment()


## 視線ポイント数を取得
func get_vision_point_count() -> int:
	return path_service.get_vision_point_count() if path_service else 0


## Run区間数を取得
func get_run_segment_count() -> int:
	return path_service.get_run_segment_count() if path_service else 0


## 未完了のRun開始点があるか
func has_incomplete_run_start() -> bool:
	return path_service.has_incomplete_run_start() if path_service else false


## マルチキャラクターモードか
func is_multi_character_mode() -> bool:
	return path_service.is_multi_character_mode() if path_service else false


## マルチキャラクターモード開始
func start_multi_character_mode(selected_chars: Array[Node]) -> void:
	if path_service:
		path_service.start_multi_character_mode(selected_chars)


## アクティブ編集キャラクターを設定
func set_active_edit_character(character: Node) -> void:
	if path_service:
		path_service.set_active_edit_character(character)


## キャラクター色を設定
func set_path_drawer_color(color: Color) -> void:
	if path_service:
		path_service.set_path_drawer_color(color)


## ========================================
## UI管理
## ========================================

## コンテキストメニューを表示
func _show_context_menu(screen_pos: Vector2, character: Node) -> void:
	if context_menu:
		var is_multi = selection_manager.get_selection_count() > 1
		context_menu.open(screen_pos, character, is_multi)


## マーカーパネルを表示
## 回転パネル表示状態を取得（外部UI用）
func is_context_menu_open() -> bool:
	return context_menu and context_menu.is_open()


## 全キャラクターの色・ラベルを再割り当て
func refresh_character_colors() -> void:
	CharacterColorManager.clear_all()
	if label_manager:
		label_manager.clear_all()
	for character in characters:
		if character_setup_service:
			character_setup_service.assign_color_and_label(character)


## ========================================
## 内部：システムセットアップ
## ========================================

func _setup_selection_manager() -> void:
	if selection_manager == null:
		selection_manager = CharacterSelectionManager.new()
		selection_manager.name = GameConstants.NODE_SELECTION_MANAGER
		add_child(selection_manager)
		selection_manager.selection_changed.connect(_on_selection_changed)
		selection_manager.primary_changed.connect(_on_primary_changed)


func _setup_path_execution_manager(mesh_parent: Node3D) -> void:
	if path_execution_manager == null:
		path_execution_manager = PathExecutionManager.new()
		path_execution_manager.name = GameConstants.NODE_PATH_EXECUTION_MANAGER
		add_child(path_execution_manager)
		path_execution_manager.setup(mesh_parent)


func _setup_idle_manager() -> void:
	if idle_manager == null:
		idle_manager = IdleCharacterManager.new()
		idle_manager.name = GameConstants.NODE_IDLE_MANAGER
		add_child(idle_manager)
		idle_manager.setup(
			characters,
			func(c): return path_execution_manager.is_character_following_path(c),
			func(): return selection_manager.primary_character
		)


func _setup_path_drawer() -> void:
	if path_drawer == null:
		path_drawer = Node3D.new()
		path_drawer.set_script(PathDrawerScript)
		path_drawer.name = GameConstants.NODE_PATH_DRAWER
		add_child(path_drawer)
		path_drawer.setup(camera)


func _setup_path_mode_controller() -> void:
	if path_mode_controller == null:
		path_mode_controller = PathModeController.new()
		path_mode_controller.name = GameConstants.NODE_PATH_MODE_CONTROLLER
		add_child(path_mode_controller)
		path_mode_controller.setup(path_drawer, selection_manager, path_execution_manager)


func _setup_rotation_controller() -> void:
	if rotation_controller == null:
		rotation_controller = Node.new()
		rotation_controller.set_script(RotationCtrl)
		rotation_controller.name = GameConstants.NODE_ROTATION_CONTROLLER
		add_child(rotation_controller)
		rotation_controller.rotation_confirmed.connect(_on_rotation_confirmed)
		rotation_controller.rotation_cancelled.connect(_on_rotation_cancelled)


func _setup_vision_service() -> void:
	if vision_service == null:
		vision_service = VisionServiceScript.new()
		vision_service.name = GameConstants.NODE_VISION_SERVICE
		add_child(vision_service)
		vision_service.setup(fow_map_size, is_vision_enabled)
		fog_of_war_system = vision_service.fog_of_war_system
		enemy_visibility_system = vision_service.enemy_visibility_system


func _setup_map_manager() -> void:
	if map_manager == null:
		map_manager = MapManager.new()
		map_manager.name = GameConstants.NODE_MAP_MANAGER
		add_child(map_manager)
		map_manager.setup(_map_container, self)


func _setup_context_menu() -> void:
	if context_menu == null:
		context_menu = Control.new()
		context_menu.set_script(ContextMenuScript)
		context_menu.name = GameConstants.NODE_CONTEXT_MENU
		_ui_layer.add_child(context_menu)
		context_menu.setup_default_items()
		context_menu.item_selected.connect(_on_context_menu_item_selected)


func _setup_marker_edit_panel() -> void:
	if marker_edit_panel == null:
		marker_edit_panel = VBoxContainer.new()
		marker_edit_panel.set_script(MarkerEditPanelScript)
		marker_edit_panel.name = GameConstants.NODE_MARKER_EDIT_PANEL
		_ui_layer.add_child(marker_edit_panel)

		# 右側に配置
		marker_edit_panel.anchor_left = 1.0
		marker_edit_panel.anchor_right = 1.0
		marker_edit_panel.anchor_top = 0.0
		marker_edit_panel.anchor_bottom = 0.0
		marker_edit_panel.offset_left = -240
		marker_edit_panel.offset_right = -10
		marker_edit_panel.offset_top = 10

		marker_edit_panel.visible = false


func _setup_weapon_shop_modal() -> void:
	if weapon_shop_modal == null:
		weapon_shop_modal = Control.new()
		weapon_shop_modal.set_script(WeaponShopModalScript)
		weapon_shop_modal.name = GameConstants.NODE_WEAPON_SHOP_MODAL
		_ui_layer.add_child(weapon_shop_modal)
		weapon_shop_modal.weapon_purchased.connect(_on_weapon_purchased)


func _setup_label_manager() -> void:
	if label_manager == null:
		label_manager = CharacterLabelManager.new()
		label_manager.name = GameConstants.NODE_LABEL_MANAGER
		add_child(label_manager)


func _setup_path_service() -> void:
	if path_service == null:
		path_service = PathServiceScript.new()
		path_service.name = GameConstants.NODE_PATH_SERVICE
		add_child(path_service)
		path_service.setup(
			path_drawer,
			selection_manager,
			path_execution_manager,
			path_mode_controller,
			marker_edit_panel
		)
		path_service.mode_started.connect(_on_path_mode_started)
		path_service.mode_ended.connect(_on_path_mode_ended)
		path_service.mode_cancelled.connect(_on_path_mode_cancelled)
		path_service.path_ready.connect(_on_path_ready)
		path_service.path_confirmed.connect(_on_path_confirmed)
		path_service.all_paths_completed.connect(_on_all_paths_completed)
		path_service.paths_cleared.connect(_on_paths_cleared)
		path_service.mode_changed.connect(_on_path_mode_changed)
		path_service.vision_point_added.connect(_on_vision_point_added)
		path_service.run_segment_added.connect(_on_run_segment_added)


func _setup_character_setup_service() -> void:
	if character_setup_service == null:
		character_setup_service = CharacterSetupServiceScript.new()
		character_setup_service.setup(
			vision_service.enemy_visibility_system,
			vision_service.fog_of_war_system,
			label_manager,
			default_weapon_id,
			is_vision_enabled,
			default_vision_fov,
			default_vision_range
		)


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
	path_mode_ended.emit()


func _on_path_mode_cancelled() -> void:
	path_mode_cancelled.emit()


func _on_path_ready() -> void:
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
	vision_point_added.emit(anchor, direction)


func _on_run_segment_added(start_ratio: float, end_ratio: float) -> void:
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
		"buy":
			_open_weapon_shop(character)
		_:
			# その他のアクションは外部に通知
			context_action_requested.emit(action_id, character)


## 武器ショップを開く
func _open_weapon_shop(character: CharacterBody3D) -> void:
	if weapon_shop_modal:
		weapon_shop_modal.open(character)


## 武器購入完了時
func _on_weapon_purchased(weapon: WeaponPreset, character: CharacterBody3D) -> void:
	print("[GameManager] Weapon purchased: %s for %s" % [weapon.display_name, character.name])
