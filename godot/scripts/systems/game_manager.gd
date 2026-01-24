extends Node
class_name GameManager
## コアゲームシステム管理
## システムの初期化・更新・入力処理・UI管理を一元管理

const MapManagerScript = preload("res://scripts/systems/map_manager.gd")
const PathDrawerScript = preload("res://scripts/effects/path_drawer.gd")
const RotationCtrl = preload("res://scripts/characters/character_rotation_controller.gd")
const ContextMenuScene = preload("res://scenes/ui/context_menu_component.tscn")
const MarkerEditPanelScript = preload("res://scripts/ui/marker_edit_panel.gd")
const WeaponShopModalScript = preload("res://scripts/ui/weapon_shop_modal.gd")
const CharacterSetupServiceScript = preload("res://scripts/systems/character_setup_service.gd")
const PathServiceScript = preload("res://scripts/systems/path_service.gd")
const VisionServiceScript = preload("res://scripts/systems/vision_service.gd")
const GrenadeScene = preload("res://scenes/weapons/grenade.tscn")

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
## グレネード投擲シグナル
signal grenade_thrown(grenade: Node3D, character: Node)
signal grenade_mode_started(character: Node)
signal grenade_mode_ended()

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

@export_group("コンテキストメニュー")
@export var context_menu_offset: Vector2 = Vector2(7.82, 32.19)  ## メニュー位置のスクリーン座標オフセット
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

## グレネードモード状態
var _grenade_mode_active: bool = false
var _grenade_mode_character: CharacterBody3D = null
var _grenade_bounce_point: Vector3 = Vector3.ZERO  ## 1タップ目のバウンスポイント
var _grenade_bounce_normal: Vector3 = Vector3.ZERO  ## バウンス面の法線
var _grenade_has_bounce_point: bool = false  ## バウンスポイントが設定済みか
var _grenade_trajectory_mesh: MeshInstance3D = null  ## 軌道プレビュー用メッシュ


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

	# 死亡シグナル接続
	if character.has_signal("died") and not character.died.is_connected(_on_character_died):
		character.died.connect(_on_character_died)



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



## ========================================
## 入力処理
## ========================================

## マウス/タッチクリック処理（シーンから呼び出す）
func handle_click(screen_pos: Vector2, button_index: int) -> bool:
	# グレネードモード中の処理（2タップ方式）
	if _grenade_mode_active:
		if button_index == MOUSE_BUTTON_LEFT or button_index == MOUSE_BUTTON_RIGHT:
			if _handle_grenade_tap(screen_pos):
				return true
			# 投擲失敗時もクリックは消費しない（他の処理に任せる）

	var clicked_character = raycast_character(screen_pos)

	# コンテキストメニューが開いている場合の処理
	if context_menu and context_menu.is_open():
		var menu_character = context_menu.get_current_character()
		# 同じキャラクターをクリック: 選択解除してメニューを閉じる
		if clicked_character and clicked_character == menu_character:
			selection_manager.remove_from_selection(clicked_character)
			context_menu.close()
			return true
		# メニューUI上のクリック（ボタン以外の部分）: 選択解除してメニューを閉じる
		# ※ボタンがクリックされた場合は_unhandled_inputに到達しないため、ここに来るのはボタン以外
		if _is_point_over_context_menu(screen_pos):
			if menu_character:
				selection_manager.remove_from_selection(menu_character)
			context_menu.close()
			return true
		# メニュー外をクリック（キャラクター以外）: ドアチェック
		if not clicked_character and menu_character:
			var clicked_door = raycast_door(screen_pos)
			if clicked_door:
				context_menu.close()
				_start_door_kick(menu_character, clicked_door)
				return true

	match button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if clicked_character:
				# 敵キャラクターは無視
				if PlayerState.is_enemy(clicked_character):
					return false
				# 移動中キャラクターを選択したら、移動を停止してメニュー表示
				if path_service and path_service.is_character_following_path(clicked_character):
					path_service.cancel_path_following(clicked_character, true)
					if selection_manager and not selection_manager.selected_characters.has(clicked_character):
						selection_manager.add_to_selection(clicked_character)
					_show_context_menu(screen_pos, clicked_character)
					return true
				# 味方キャラクタークリック: トグル選択 + コンテキストメニュー表示
				selection_manager.toggle_selection(clicked_character)
				# 選択中の場合のみコンテキストメニュー表示
				if selection_manager.selected_characters.has(clicked_character):
					_show_context_menu(screen_pos, clicked_character)
				return true
			else:
				# キャラクター選択中 + ドアクリック → ドアキック開始
				if selection_manager and selection_manager.primary_character:
					var clicked_door = raycast_door(screen_pos)
					if clicked_door:
						_start_door_kick(selection_manager.primary_character, clicked_door)
						return true
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


## レイキャストでドアを検出
func raycast_door(screen_pos: Vector2) -> Node3D:
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

	# ドアを探す（衝突したコライダーの親を辿ってdoorsグループを確認）
	var collider = result.collider
	var node = collider
	while node:
		if node.is_in_group(GameConstants.GROUP_DOORS):
			return node as Node3D
		node = node.get_parent()
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


## 視界デバッグ表示の切り替え（味方キャラクターの視界コーンを表示）
func set_vision_debug_draw(enabled: bool) -> void:
	for character in characters:
		if PlayerState.is_friendly(character):
			var game_char := character as GameCharacter
			if game_char and game_char.vision:
				game_char.vision.set_debug_draw(enabled)


## 全味方キャラクターの視界を強制更新（ドア開閉時など）
func _force_update_all_vision() -> void:
	for character in characters:
		if PlayerState.is_friendly(character):
			var game_char := character as GameCharacter
			if game_char and game_char.vision and game_char.vision.is_enabled():
				game_char.vision.force_update()


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

	_update_context_menu_follow()


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
		# キャラクターの体の中心を基準にメニューを表示
		var menu_pos = screen_pos
		if camera and character:
			var character_center = character.global_position + Vector3(0, 0.9, 0)
			menu_pos = camera.unproject_position(character_center)
			menu_pos += context_menu_offset
		context_menu.open(menu_pos, character, is_multi)


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
		# ドアキック用: 個別キャラクターのパス完了シグナルを接続
		path_execution_manager.character_path_completed.connect(_on_character_path_completed)


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
		context_menu = ContextMenuScene.instantiate()
		context_menu.name = GameConstants.NODE_CONTEXT_MENU
		_ui_layer.add_child(context_menu)
		context_menu.setup_default_items()
		context_menu.item_selected.connect(_on_context_menu_item_selected)
		context_menu.background_clicked.connect(_on_context_menu_background_clicked)


func _update_context_menu_follow() -> void:
	if not context_menu or not context_menu.is_open():
		return
	if not camera:
		return
	var character = context_menu.get_current_character()
	if not character:
		return
	var character_center = character.global_position + Vector3(0, 0.9, 0)
	var base_pos = camera.unproject_position(character_center)
	context_menu.update_screen_position(base_pos + context_menu_offset)


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
		weapon_shop_modal.closed.connect(_on_weapon_shop_closed)


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
			# 仮実装: グレネードモード開始
			start_grenade_mode(character)
		"buy":
			_open_weapon_shop(character)
		_:
			# その他のアクションは外部に通知
			context_action_requested.emit(action_id, character)


func _on_context_menu_background_clicked(character: CharacterBody3D) -> void:
	# メニュー背景（中央の穴など）がクリックされた場合、選択解除
	if character and selection_manager:
		selection_manager.remove_from_selection(character)


## 武器ショップを開く
func _open_weapon_shop(character: CharacterBody3D) -> void:
	if weapon_shop_modal:
		weapon_shop_modal.open(character)


## 武器購入完了時
func _on_weapon_purchased(_weapon: WeaponPreset, _character: CharacterBody3D) -> void:
	pass


## 武器ショップ閉じた時
func _on_weapon_shop_closed(character: CharacterBody3D) -> void:
	# キャラクター選択を解除
	if character and selection_manager:
		selection_manager.remove_from_selection(character)


## キャラクター死亡時の処理
func _on_character_died(character: GameCharacter) -> void:
	# パス追従をキャンセルしてパスメッシュ・マーカーをクリア
	if path_service:
		path_service.cancel_path_following(character, true)

	# 選択解除
	if selection_manager:
		selection_manager.remove_from_selection(character)

	# コンテキストメニューが開いている場合は閉じる
	if context_menu and context_menu.is_open():
		var menu_char = context_menu.get_current_character()
		if menu_char == character:
			context_menu.close()


## ========================================
## ドアキック処理
## ========================================

## ドアキック中のドア参照（キャラクターID -> ドア）
var _door_kick_targets: Dictionary = {}
## ドアキック時のドア方向（キャラクターID -> Vector3）
var _door_kick_directions: Dictionary = {}


## ドアキック開始
func _start_door_kick(character: CharacterBody3D, door: Node3D) -> void:
	# ドアキック中は無効
	var anim_ctrl = character.get_anim_controller() if character.has_method("get_anim_controller") else null
	if anim_ctrl and anim_ctrl.has_method("is_door_kicking") and anim_ctrl.is_door_kicking():
		return

	# コンテキストメニューを閉じる
	if context_menu and context_menu.is_open():
		context_menu.close()

	# 選択解除
	if selection_manager:
		selection_manager.deselect_all()

	# キャラクター位置を取得
	var char_pos := character.global_position
	char_pos.y = 0.0

	# ドアの前後アンカー位置を計算（ドアのローカルZ軸方向）
	var door_pos := door.global_position
	door_pos.y = 0.0
	var door_forward := door.global_transform.basis.z.normalized()
	door_forward.y = 0.0
	door_forward = door_forward.normalized()

	# 前後アンカー位置（ドアから0.65m離れた位置）
	var anchor_front := door_pos + door_forward * 0.65  # +Z側
	var anchor_back := door_pos - door_forward * 0.65   # -Z側

	# キャラクターに近い方のアンカーを選択
	var dist_front := char_pos.distance_to(anchor_front)
	var dist_back := char_pos.distance_to(anchor_back)
	var approach_pos := anchor_front if dist_front < dist_back else anchor_back

	# ドア参照を保持（パス完了時にドアキックを実行するため）
	_door_kick_targets[character.get_instance_id()] = door

	# 距離チェック: 既に十分近ければ即座にドアキック
	if char_pos.distance_to(approach_pos) < 0.3:
		_execute_door_kick(character, door)
		return

	# PathExecutionManagerを使用してパス実行（通常のMove処理と同じ）
	if path_execution_manager:
		path_execution_manager.execute_direct_path(character, approach_pos, false)


## キャラクターパス完了時のハンドラ（ドアキック用）
func _on_character_path_completed(character: Node) -> void:
	var char_id = character.get_instance_id()
	if not _door_kick_targets.has(char_id):
		return

	var door = _door_kick_targets[char_id]
	_door_kick_targets.erase(char_id)

	if is_instance_valid(door):
		_execute_door_kick(character as CharacterBody3D, door)


## ドアキック実行（ドア前に到達後）
## スムーズに回転してからキックアニメーションを再生
func _execute_door_kick(character: CharacterBody3D, door: Node3D) -> void:
	if not is_instance_valid(character) or not is_instance_valid(door):
		return

	var door_pos := door.global_position
	door_pos.y = character.global_position.y

	# モデルをTweenでスムーズに回転
	var anim_ctrl = character.get_anim_controller() if character.has_method("get_anim_controller") else null
	if not anim_ctrl:
		return

	# 現在の回転と目標の回転を計算
	var model = anim_ctrl.get_model() if anim_ctrl.has_method("get_model") else null
	if not model:
		# フォールバック: 即座に向きを変えてキック
		if character.has_method("face_towards"):
			character.face_towards(door_pos)
		_play_door_kick_animation(character, door)
		return

	# 目標方向を計算（Mixamoモデルは+Zが前方）
	var direction := (door_pos - character.global_position).normalized()
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	# Basis.looking_at(-direction) でMixamoモデルの向きを正しく設定
	var target_basis := Basis.looking_at(-direction, Vector3.UP)
	var target_quat := target_basis.get_rotation_quaternion()
	var current_quat := Quaternion(model.transform.basis)

	# Tweenでスムーズに回転（0.25秒）
	var tween := create_tween()
	tween.tween_method(
		func(t: float):
			if is_instance_valid(model):
				var new_quat := current_quat.slerp(target_quat, t)
				model.transform.basis = Basis(new_quat),
		0.0, 1.0, 0.25
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	# 回転完了後にキックアニメーション再生
	tween.tween_callback(_play_door_kick_animation.bind(character, door))


## ドアキックアニメーション再生
func _play_door_kick_animation(character: CharacterBody3D, door: Node3D) -> void:
	if not is_instance_valid(character) or not is_instance_valid(door):
		return

	var anim_ctrl = character.get_anim_controller() if character.has_method("get_anim_controller") else null
	if anim_ctrl and anim_ctrl.has_method("play_door_kick"):
		# ドア方向を保存（キック完了後にこの向きを維持するため）
		var door_dir := (door.global_position - character.global_position).normalized()
		door_dir.y = 0.0
		if door_dir.length_squared() > 0.001:
			_door_kick_directions[character.get_instance_id()] = door_dir.normalized()

		# door_kick_impactシグナルに接続（キックがドアに当たるタイミングでドアを開く）
		if anim_ctrl.has_signal("door_kick_impact"):
			if not anim_ctrl.door_kick_impact.is_connected(_on_door_kick_done.bind(door, character)):
				anim_ctrl.door_kick_impact.connect(_on_door_kick_done.bind(door, character), CONNECT_ONE_SHOT)

		# door_kick_finishedシグナルに接続（アニメーション完了後にドア方向を維持）
		if anim_ctrl.has_signal("door_kick_finished"):
			if not anim_ctrl.door_kick_finished.is_connected(_on_door_kick_animation_finished.bind(character)):
				anim_ctrl.door_kick_finished.connect(_on_door_kick_animation_finished.bind(character), CONNECT_ONE_SHOT)

		anim_ctrl.play_door_kick()


## ドアキックインパクト時（フレーム36/66）
## character: ドアをキックしたキャラクター（位置から回転方向を計算）
func _on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# ドアからキャラクターへの方向ベクトル
	var door_to_char := (character.global_position - door.global_position)
	door_to_char.y = 0.0
	door_to_char = door_to_char.normalized()

	# ドアのローカルX軸（ドア表面に垂直、蝶番回転の基準）
	var door_right := door.global_transform.basis.x.normalized()
	door_right.y = 0.0
	door_right = door_right.normalized()

	# キャラクターがドアのどちら側にいるかを判定
	var side_dot := door_right.dot(door_to_char)

	# ドアはキャラクターから離れる方向に開く
	# side_dot > 0: キャラクターはドアの右側 → ドアは左に開く（-方向）
	# side_dot < 0: キャラクターはドアの左側 → ドアは右に開く（+方向）
	var rotation_amount := -170.0 if side_dot > 0 else 170.0

	# TweenでドアをY軸で回転（蝶番を軸に横開き）
	var tween := create_tween()
	var current_y := door.rotation_degrees.y
	tween.tween_property(door, "rotation_degrees:y", current_y + rotation_amount, 0.4) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_BACK)

	# ドアが開いた後に視界を強制更新
	tween.tween_callback(_force_update_all_vision)


## ドアキックアニメーション完了時（ドア方向を維持）
func _on_door_kick_animation_finished(character: CharacterBody3D) -> void:
	if not is_instance_valid(character):
		return

	var char_id := character.get_instance_id()
	if not _door_kick_directions.has(char_id):
		return

	var door_dir: Vector3 = _door_kick_directions[char_id]
	_door_kick_directions.erase(char_id)

	# キャラクターの向きをドア方向に設定
	if character.has_method("set_facing_direction_vec"):
		character.set_facing_direction_vec(door_dir)


## ========================================
## グレネード投擲処理（2タップ方式）
## 1タップ目: バウンスポイント（壁/ドアエッジ）
## 2タップ目: 最終目標位置 → 投擲実行
## ========================================

## グレネードモード開始
func start_grenade_mode(character: CharacterBody3D) -> void:
	if not character or not is_instance_valid(character):
		return

	# 既にアクティブな場合は一度終了してリセット
	if _grenade_mode_active:
		_cleanup_grenade_trajectory_mesh()

	_grenade_mode_active = true
	_grenade_mode_character = character
	_grenade_has_bounce_point = false
	_grenade_bounce_point = Vector3.ZERO
	_grenade_bounce_normal = Vector3.ZERO

	# コンテキストメニューを閉じる
	if context_menu and context_menu.is_open():
		context_menu.close()

	# 軌道プレビュー用メッシュを作成
	_setup_grenade_trajectory_mesh()

	grenade_mode_started.emit(character)


## グレネードモード終了
func end_grenade_mode() -> void:
	if not _grenade_mode_active:
		return

	_grenade_mode_active = false
	_grenade_mode_character = null
	_grenade_has_bounce_point = false
	_grenade_bounce_point = Vector3.ZERO
	_grenade_bounce_normal = Vector3.ZERO

	# 軌道プレビューを削除
	_cleanup_grenade_trajectory_mesh()

	grenade_mode_ended.emit()


## グレネードモード中かどうか
func is_grenade_mode() -> bool:
	return _grenade_mode_active


## バウンスポイントが設定済みか
func has_grenade_bounce_point() -> bool:
	return _grenade_has_bounce_point


## グレネードモードのキャラクターを取得
func get_grenade_mode_character() -> CharacterBody3D:
	return _grenade_mode_character


## グレネードタップ処理（2タップ方式）
## Returns: 処理成功したかどうか
func _handle_grenade_tap(screen_pos: Vector2) -> bool:
	if not _grenade_mode_active or not _grenade_mode_character:
		return false

	if not is_instance_valid(_grenade_mode_character):
		end_grenade_mode()
		return false

	if not _grenade_has_bounce_point:
		# 1タップ目: バウンスポイントを設定
		return _set_grenade_bounce_point(screen_pos)
	else:
		# 2タップ目: 投擲実行
		return _execute_grenade_throw(screen_pos)


## グレネードが壁に当たる固定高さ（地面からの高さ）
const GRENADE_WALL_HIT_HEIGHT: float = 1.0

## 1タップ目: 壁ならバウンスポイント設定、床なら直接投擲
func _set_grenade_bounce_point(screen_pos: Vector2) -> bool:
	# 壁または床へのレイキャスト
	var hit_result = _raycast_wall_or_floor(screen_pos)
	if hit_result.is_empty():
		return false

	var hit_pos: Vector3 = hit_result.position
	var hit_normal: Vector3 = hit_result.normal

	# 壁かどうか判定（法線が水平に近い = 壁）
	var is_wall = abs(hit_normal.y) < 0.5

	# 投擲開始位置
	var start_pos = _grenade_mode_character.global_position + Vector3(0, 1.5, 0)

	if is_wall:
		# 壁の場合: バウンスポイントを設定して2タップ目を待つ
		hit_pos.y = GRENADE_WALL_HIT_HEIGHT

		if not _is_grenade_path_clear(start_pos, hit_pos):
			return false

		_grenade_bounce_point = hit_pos
		_grenade_bounce_normal = hit_normal
		_grenade_has_bounce_point = true

		# 軌道プレビューを更新（バウンスポイントまでの線）
		_update_grenade_trajectory_preview()
		return true
	else:
		# 床の場合: 直接投擲（2タップ目不要）
		if not _is_grenade_path_clear(start_pos, hit_pos):
			return false

		return _throw_grenade_direct(hit_pos)


## グレネードを直接投擲（バウンスなし）
func _throw_grenade_direct(target_pos: Vector3) -> bool:
	if not _grenade_mode_character or not is_instance_valid(_grenade_mode_character):
		return false

	var start_pos = _grenade_mode_character.global_position + Vector3(0, 1.5, 0)

	# グレネードをインスタンス化
	var grenade = GrenadeScene.instantiate() as Grenade
	if not grenade:
		return false

	# ワールドに追加
	_mesh_parent.add_child(grenade)

	# 直接投擲
	grenade.throw(start_pos, target_pos, _grenade_mode_character)

	# シグナル発火
	grenade_thrown.emit(grenade, _grenade_mode_character)

	# グレネードモード終了
	end_grenade_mode()

	# 選択解除
	if selection_manager:
		selection_manager.deselect_all()

	return true


## 2タップ目: グレネード投擲実行
func _execute_grenade_throw(screen_pos: Vector2) -> bool:
	# 最終目標位置を取得
	var target_pos = _screen_to_ground_position(screen_pos)
	if target_pos == Vector3.ZERO:
		return false

	# 投擲開始位置
	var start_pos = _grenade_mode_character.global_position + Vector3(0, 1.5, 0)

	# グレネードをインスタンス化
	var grenade = GrenadeScene.instantiate() as Grenade
	if not grenade:
		return false

	# ワールドに追加
	_mesh_parent.add_child(grenade)

	# バウンス投擲実行
	grenade.throw_with_bounce(start_pos, _grenade_bounce_point, _grenade_bounce_normal, target_pos, _grenade_mode_character)

	# シグナル発火
	grenade_thrown.emit(grenade, _grenade_mode_character)

	# グレネードモード終了
	end_grenade_mode()

	# 選択解除
	if selection_manager:
		selection_manager.deselect_all()

	return true


## スクリーン座標を地面位置に変換
func _screen_to_ground_position(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.ZERO

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)

	# 地面平面（Y=0）との交差を計算
	var ground_plane = Plane(Vector3.UP, 0.0)
	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)

	if intersection:
		return intersection
	return Vector3.ZERO


## 壁または床へのレイキャスト（法線情報付き）
func _raycast_wall_or_floor(screen_pos: Vector2) -> Dictionary:
	if not camera or not _mesh_parent:
		return {}

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 100.0

	var space_state = _mesh_parent.get_world_3d().direct_space_state
	if not space_state:
		return {}

	# 壁と床の両方を検出（mask = 1 | 2 = 3）
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 3)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)
	return result


## グレネード軌道が障害物なしで到達可能かチェック
func _is_grenade_path_clear(from: Vector3, to: Vector3) -> bool:
	if not _mesh_parent:
		return true

	var space_state = _mesh_parent.get_world_3d().direct_space_state
	if not space_state:
		return true

	var query = PhysicsRayQueryParameters3D.create(from, to, 2)  # 壁のみ
	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return true

	# 目標位置に非常に近い場合はOK（壁自体をターゲットにしている）
	var hit_pos: Vector3 = result.position
	return hit_pos.distance_to(to) < 0.3


## 軌道プレビュー用メッシュをセットアップ
func _setup_grenade_trajectory_mesh() -> void:
	if _grenade_trajectory_mesh:
		return

	_grenade_trajectory_mesh = MeshInstance3D.new()
	_grenade_trajectory_mesh.name = "GrenadeTrajectoryPreview"
	_mesh_parent.add_child(_grenade_trajectory_mesh)

	# マテリアル設定
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.8)  # オレンジ
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grenade_trajectory_mesh.material_override = mat


## グレネードプレビューを更新（マウス移動時に呼ばれる）
func update_grenade_preview(screen_pos: Vector2) -> void:
	if not _grenade_mode_active or not _grenade_mode_character:
		return

	if not is_instance_valid(_grenade_mode_character):
		return

	# 現在のマウス位置を3D座標に変換
	var current_pos = _screen_to_ground_position(screen_pos)
	if current_pos == Vector3.ZERO:
		# 地面に当たらない場合は壁へのレイキャスト
		var hit = _raycast_wall_or_floor(screen_pos)
		if not hit.is_empty():
			current_pos = hit.position

	if current_pos == Vector3.ZERO:
		return

	# 軌道プレビューを更新
	_update_grenade_trajectory_preview(current_pos)


## 軌道プレビューを更新
## target_pos: 2タップ目のターゲット位置（マウス位置）。省略時はバウンスポイントのみ表示
func _update_grenade_trajectory_preview(target_pos: Vector3 = Vector3.ZERO) -> void:
	if not _grenade_trajectory_mesh or not _grenade_mode_character:
		return

	var start_pos = _grenade_mode_character.global_position + Vector3(0, 1.5, 0)

	# ImmediateMeshで線を描画
	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	if _grenade_has_bounce_point:
		# バウンスポイントが設定済み: 開始点→バウンス→ターゲット
		# 第1区間: 開始点からバウンスポイント
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(_grenade_bounce_point)

		# バウンスポイントにマーカー（クロス）
		var cross_size = 0.2
		im.surface_add_vertex(_grenade_bounce_point + Vector3(-cross_size, 0, 0))
		im.surface_add_vertex(_grenade_bounce_point + Vector3(cross_size, 0, 0))
		im.surface_add_vertex(_grenade_bounce_point + Vector3(0, -cross_size, 0))
		im.surface_add_vertex(_grenade_bounce_point + Vector3(0, cross_size, 0))
		im.surface_add_vertex(_grenade_bounce_point + Vector3(0, 0, -cross_size))
		im.surface_add_vertex(_grenade_bounce_point + Vector3(0, 0, cross_size))

		# 第2区間: バウンスポイントからターゲット（破線風に）
		if target_pos != Vector3.ZERO:
			var bounce_to_target = target_pos - _grenade_bounce_point
			var distance = bounce_to_target.length()
			var direction = bounce_to_target.normalized()
			var dash_length = 0.3
			var gap_length = 0.15
			var current_dist = 0.0

			while current_dist < distance:
				var dash_start = _grenade_bounce_point + direction * current_dist
				var dash_end_dist = min(current_dist + dash_length, distance)
				var dash_end = _grenade_bounce_point + direction * dash_end_dist

				im.surface_add_vertex(dash_start)
				im.surface_add_vertex(dash_end)

				current_dist += dash_length + gap_length

			# ターゲット位置にマーカー（小さいクロス）
			var target_cross_size = 0.15
			im.surface_add_vertex(target_pos + Vector3(-target_cross_size, 0, 0))
			im.surface_add_vertex(target_pos + Vector3(target_cross_size, 0, 0))
			im.surface_add_vertex(target_pos + Vector3(0, 0, -target_cross_size))
			im.surface_add_vertex(target_pos + Vector3(0, 0, target_cross_size))
	else:
		# バウンスポイント未設定: 開始点から現在のマウス位置への線
		if target_pos != Vector3.ZERO:
			im.surface_add_vertex(start_pos)
			im.surface_add_vertex(target_pos)

	im.surface_end()
	_grenade_trajectory_mesh.mesh = im


## 軌道プレビューを削除
func _cleanup_grenade_trajectory_mesh() -> void:
	if _grenade_trajectory_mesh:
		_grenade_trajectory_mesh.queue_free()
		_grenade_trajectory_mesh = null
