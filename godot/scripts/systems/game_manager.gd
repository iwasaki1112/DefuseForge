extends Node
class_name GameManager
## コアゲームシステム管理
## システムの初期化・更新・入力処理・UI管理を一元管理

const MapManagerScript = preload("res://scripts/systems/map_manager.gd")
const PathDrawerScript = preload("res://scripts/effects/path_drawer.gd")
const RotationCtrl = preload("res://scripts/characters/character_rotation_controller.gd")
const ContextMenuScene = preload("res://scenes/ui/context_menu_component.tscn")
const WeaponShopModalScript = preload("res://scripts/ui/weapon_shop_modal.gd")
const CharacterSetupServiceScript = preload("res://scripts/systems/character_setup_service.gd")
const PathServiceScript = preload("res://scripts/systems/path_service.gd")
const VisionServiceScript = preload("res://scripts/systems/vision_service.gd")
const GrenadeScene = preload("res://scenes/weapons/grenade.tscn")
const SmokeGrenadeScene = preload("res://scenes/weapons/smoke_grenade.tscn")

## UI接続用シグナル
signal selection_changed(selected: Array[Node], primary: Node)
signal primary_changed(character: Node)
signal path_mode_started(character: Node)
signal path_mode_ended()
signal path_mode_cancelled()
signal path_ready()
signal path_confirmed(count: int)
signal paths_execution_started(count: int)
signal all_paths_completed()
signal paths_cleared()
signal rotation_confirmed(direction: Vector3)
signal rotation_cancelled()
signal path_mode_changed(mode: int)
signal vision_point_added(anchor: Vector3, direction: Vector3)
signal run_segment_added(start_ratio: float, end_ratio: float)
## タイムラインデータ変更シグナル（リアルタイムプレビュー用）
signal timeline_data_changed()
## コンテキストメニュー操作シグナル
signal context_action_requested(action_id: String, character: Node)
## グレネード投擲シグナル
signal grenade_thrown(grenade: Node3D, character: Node)
## スモークグレネード投擲シグナル
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)
## ラウンド管理シグナル
signal round_started()
signal round_ended(winner: int, reason: int)
signal round_timer_updated(remaining: float)
signal survivor_count_changed(ct_count: int, t_count: int)

## コアシステム
var selection_manager: CharacterSelectionManager = null
var path_execution_manager: PathExecutionManager = null
var idle_manager: IdleCharacterManager = null
var path_mode_controller: PathModeController = null
var timeline_manager: TimelineManager = null
var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null
var smoke_area_manager: SmokeAreaManager = null
var map_manager: MapManager = null
var path_drawer: Node3D = null
var rotation_controller: Node = null
var character_setup_service: CharacterSetupService = null
var path_service: PathService = null
var vision_service: VisionService = null
var round_manager: RoundManager = null

## UIコンポーネント
var context_menu: Control = null

@export_group("コンテキストメニュー")
@export var context_menu_offset: Vector2 = Vector2(7.82, 32.19)  ## メニュー位置のスクリーン座標オフセット
var label_manager: CharacterLabelManager = null
var weapon_shop_modal: Control = null

## 外部参照
var camera: Camera3D = null
var characters: Array[Node] = []
var _mesh_parent: Node3D = null
var _map_container: Node3D = null
var _ui_layer: CanvasLayer = null

## マルチプレイヤー状態
var _is_multiplayer_mode: bool = false
var _local_peer_id: int = 0

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
	_setup_timeline_manager()
	_setup_smoke_area_manager()
	_setup_path_drawer()
	_setup_path_mode_controller()
	_setup_rotation_controller()
	_setup_vision_service()
	_setup_map_manager()
	_setup_context_menu()
	_setup_weapon_shop_modal()
	_setup_path_service()
	_setup_label_manager()
	_setup_round_manager()
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

	# ラウンド管理に登録
	if round_manager and character is GameCharacter:
		round_manager.register_character(character as GameCharacter)

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
	# ラウンドタイマー処理
	if round_manager:
		round_manager.process(delta)

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

	# リモートキャラクターの補間更新
	_update_remote_character_interpolation(delta)

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
		# キャラクターの体の中心を基準にメニューを表示
		var menu_pos = screen_pos
		if camera and character:
			var character_center = character.global_position + Vector3(0, 0.9, 0)
			menu_pos = camera.unproject_position(character_center)
			menu_pos += context_menu_offset
		context_menu.open(menu_pos, character)


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
		# グレネード/スモークグレネード/ドアマーカー到達シグナルを接続
		path_execution_manager.grenade_marker_reached.connect(_on_grenade_marker_reached)
		path_execution_manager.smoke_grenade_marker_reached.connect(_on_smoke_grenade_marker_reached)
		path_execution_manager.door_marker_reached.connect(_on_door_marker_reached)
		path_execution_manager.paths_execution_started.connect(_on_paths_execution_started)


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


func _setup_timeline_manager() -> void:
	if timeline_manager == null:
		timeline_manager = TimelineManager.new()
		timeline_manager.name = "TimelineManager"
		add_child(timeline_manager)
		timeline_manager.timeline_updated.connect(_on_timeline_data_changed)


func _setup_smoke_area_manager() -> void:
	if smoke_area_manager == null:
		smoke_area_manager = SmokeAreaManager.new()
		smoke_area_manager.name = "SmokeAreaManager"
		add_child(smoke_area_manager)


func _setup_path_drawer() -> void:
	if path_drawer == null:
		path_drawer = Node3D.new()
		path_drawer.set_script(PathDrawerScript)
		path_drawer.name = GameConstants.NODE_PATH_DRAWER
		add_child(path_drawer)
		path_drawer.setup(camera, null, timeline_manager)


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
		# スモークエリアマネージャーを接続
		if enemy_visibility_system and smoke_area_manager:
			enemy_visibility_system.set_smoke_area_manager(smoke_area_manager)


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


## リモートキャラクターの補間更新
func _update_remote_character_interpolation(delta: float) -> void:
	for character in characters:
		var game_char := character as GameCharacter
		if game_char and game_char.has_method("update_remote_interpolation"):
			game_char.update_remote_interpolation(delta)


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
			path_mode_controller
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


func _setup_round_manager() -> void:
	if round_manager == null:
		round_manager = RoundManager.new()
		round_manager.name = GameConstants.NODE_ROUND_MANAGER
		add_child(round_manager)
		round_manager.setup(self)
		round_manager.round_started.connect(_on_round_started)
		round_manager.round_ended.connect(_on_round_ended)
		round_manager.timer_updated.connect(_on_round_timer_updated)
		round_manager.survivor_count_changed.connect(_on_survivor_count_changed)


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


func _on_timeline_data_changed() -> void:
	timeline_data_changed.emit()


func _on_path_confirmed(count: int) -> void:
	path_confirmed.emit(count)


func _on_all_paths_completed() -> void:
	all_paths_completed.emit()


func _on_paths_execution_started(count: int) -> void:
	paths_execution_started.emit(count)


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


func _on_round_started() -> void:
	round_started.emit()


func _on_round_ended(winner: int, reason: int) -> void:
	round_ended.emit(winner, reason)


func _on_round_timer_updated(remaining: float) -> void:
	round_timer_updated.emit(remaining)


func _on_survivor_count_changed(ct_count: int, t_count: int) -> void:
	survivor_count_changed.emit(ct_count, t_count)


func _on_context_menu_item_selected(action_id: String, character: CharacterBody3D) -> void:
	match action_id:
		"move":
			start_move_mode()
		"rotate":
			start_rotation_mode(character)
		"crouch":
			# しゃがみ/立ち上がりトグル
			_toggle_crouch(character)
		"buy":
			_open_weapon_shop(character)
		_:
			# その他のアクションは外部に通知
			context_action_requested.emit(action_id, character)


## しゃがみ/立ち上がりトグル
func _toggle_crouch(character: CharacterBody3D) -> void:
	if not character:
		return
	if character.has_method("toggle_crouch"):
		character.toggle_crouch()
	elif character.has_method("set_crouching"):
		var is_crouching = character.is_crouching() if character.has_method("is_crouching") else false
		character.set_crouching(not is_crouching)


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
## ドアキック処理（マーカーからの実行用）
## ========================================

## ドアキック時のドア方向（キャラクターID -> Vector3）
var _door_kick_directions: Dictionary = {}

## グレネード追跡（爆発位置同期用）
var _active_grenades: Dictionary = {}  ## grenade_id -> Grenade/SmokeGrenade
var _next_grenade_id: int = 1


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

	# ドアを「open_doors」グループに追加（他のキャラクターが通過可能になる）
	if not door.is_in_group("open_doors"):
		door.add_to_group("open_doors")

	# TweenでドアをY軸で回転（蝶番を軸に横開き）
	var tween := create_tween()
	var current_y := door.rotation_degrees.y
	tween.tween_property(door, "rotation_degrees:y", current_y + rotation_amount, 0.4) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_BACK)

	# ドアが開いた後に視界を強制更新
	tween.tween_callback(_force_update_all_vision)


## ========================================
## パスマーカー到達時の処理
## ========================================

## グレネードマーカー到達時（移動を継続しながら投擲）
func _on_grenade_marker_reached(character: Node, marker_data: Dictionary) -> void:
	if not is_instance_valid(character):
		return

	var char_body := character as CharacterBody3D
	if not char_body:
		return

	# マルチプレイヤーモード: ローカルキャラクターのみが投擲を実行
	var game_char := character as GameCharacter
	if game_char and not game_char.is_local():
		return  # リモートキャラクターの投擲はネットワークイベントで処理

	# マーカーデータからターゲット位置を取得
	var target_pos: Vector3 = marker_data.get("target_pos", Vector3.ZERO)
	var bounce_point: Vector3 = marker_data.get("bounce_point", Vector3.ZERO)

	if target_pos == Vector3.ZERO:
		return

	# 投擲開始位置
	var start_pos = char_body.global_position + Vector3(0, 1.5, 0)

	# グレネードを生成して投擲（戻り値: [grenade, velocity, grenade_id]）
	var result := _spawn_and_throw_grenade(start_pos, target_pos, bounce_point, char_body)
	var grenade: Grenade = result[0]
	var velocity: Vector3 = result[1]
	var grenade_id: int = result[2]
	if not grenade:
		return

	print("[GRENADE LOCAL] start=", start_pos, " target=", target_pos, " vel=", velocity, " id=", grenade_id)

	# シグナル発火（ネットワーク送信用）
	grenade_thrown.emit(grenade, char_body)

	# ネットワークイベントを送信（velocityとIDを送信）
	_emit_grenade_network_event(start_pos, velocity, false, grenade_id)


## スモークグレネードマーカー到達時（移動を継続しながら投擲）
func _on_smoke_grenade_marker_reached(character: Node, marker_data: Dictionary) -> void:
	if not is_instance_valid(character):
		return

	var char_body := character as CharacterBody3D
	if not char_body:
		return

	# マルチプレイヤーモード: ローカルキャラクターのみが投擲を実行
	var game_char := character as GameCharacter
	if game_char and not game_char.is_local():
		return  # リモートキャラクターの投擲はネットワークイベントで処理

	# マーカーデータからターゲット位置を取得
	var target_pos: Vector3 = marker_data.get("target_pos", Vector3.ZERO)
	var bounce_point: Vector3 = marker_data.get("bounce_point", Vector3.ZERO)

	if target_pos == Vector3.ZERO:
		return

	# 投擲開始位置
	var start_pos = char_body.global_position + Vector3(0, 1.5, 0)

	# スモークグレネードを生成して投擲（戻り値: [smoke_grenade, velocity, grenade_id]）
	var result := _spawn_and_throw_smoke_grenade(start_pos, target_pos, bounce_point, char_body)
	var smoke_grenade: SmokeGrenade = result[0]
	var velocity: Vector3 = result[1]
	var grenade_id: int = result[2]
	if not smoke_grenade:
		return

	# シグナル発火
	smoke_grenade_thrown.emit(smoke_grenade, char_body)

	# ネットワークイベントを送信（velocityとIDを送信）
	_emit_grenade_network_event(start_pos, velocity, true, grenade_id)


## グレネードを生成して投擲（内部ヘルパー）
## 戻り値: [grenade, velocity, grenade_id] のトリプル
func _spawn_and_throw_grenade(start_pos: Vector3, target_pos: Vector3, _bounce_point: Vector3, thrower: Node3D = null) -> Array:
	var grenade = GrenadeScene.instantiate() as Grenade
	if not grenade:
		return [null, Vector3.ZERO, 0]

	_mesh_parent.add_child(grenade)

	# グレネードIDを割り当てて追跡
	var grenade_id: int = _next_grenade_id
	_next_grenade_id += 1
	grenade.network_grenade_id = grenade_id
	_active_grenades[grenade_id] = grenade

	# 爆発シグナルを接続
	grenade.exploded.connect(_on_grenade_exploded.bind(grenade_id, false))

	# ターゲット位置に直接投擲
	grenade.throw(start_pos, target_pos, thrower)

	return [grenade, grenade.initial_velocity, grenade_id]


## スモークグレネードを生成して投擲（内部ヘルパー）
## 戻り値: [smoke_grenade, velocity, grenade_id] のトリプル
func _spawn_and_throw_smoke_grenade(start_pos: Vector3, target_pos: Vector3, _bounce_point: Vector3, thrower: Node3D = null) -> Array:
	var smoke_grenade = SmokeGrenadeScene.instantiate() as SmokeGrenade
	if not smoke_grenade:
		return [null, Vector3.ZERO, 0]

	smoke_grenade.set_smoke_manager(smoke_area_manager)
	_mesh_parent.add_child(smoke_grenade)

	# グレネードIDを割り当てて追跡
	var grenade_id: int = _next_grenade_id
	_next_grenade_id += 1
	smoke_grenade.network_grenade_id = grenade_id
	_active_grenades[grenade_id] = smoke_grenade

	# 爆発シグナルを接続（スモークはis_smoke=true）
	smoke_grenade.exploded.connect(_on_grenade_exploded.bind(grenade_id, true))

	# ターゲット位置に直接投擲
	smoke_grenade.throw(start_pos, target_pos, thrower)

	return [smoke_grenade, smoke_grenade.initial_velocity, grenade_id]


## ネットワークイベントを発火（グレネード投擲）- velocityとIDも含む
signal grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int)

## ネットワークイベントを発火（グレネード爆発/スモーク展開）
signal grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool)

func _emit_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int = 0) -> void:
	grenade_network_event.emit(start_pos, velocity, is_smoke, grenade_id)


## グレネード爆発時のコールバック（ネットワーク送信用）
func _on_grenade_exploded(position: Vector3, grenade_id: int, is_smoke: bool) -> void:
	# 追跡から削除
	if _active_grenades.has(grenade_id):
		_active_grenades.erase(grenade_id)

	# ネットワークイベントを発火（リモート側で同じ位置で爆発させる）
	grenade_explode_network_event.emit(grenade_id, position, is_smoke)


## ネットワークからグレネードをスポーン（リモート用）- 速度を直接使用
func spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0) -> void:
	print("[GRENADE SPAWN] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	var grenade = GrenadeScene.instantiate() as Grenade
	if not grenade:
		return

	_mesh_parent.add_child(grenade)

	# リモートグレネードとしてマーク
	grenade.is_remote = true
	grenade.network_grenade_id = grenade_id

	# 追跡（爆発イベント受信用）
	if grenade_id > 0:
		_active_grenades[grenade_id] = grenade

	grenade.throw_with_velocity(start_pos, velocity)
	print("[GRENADE SPAWNED] vel=", velocity)
	grenade_thrown.emit(grenade, null)


## ネットワークからスモークグレネードをスポーン（リモート用）- 速度を直接使用
func spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0) -> void:
	print("[SMOKE SPAWN] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	var smoke_grenade = SmokeGrenadeScene.instantiate() as SmokeGrenade
	if not smoke_grenade:
		return

	smoke_grenade.set_smoke_manager(smoke_area_manager)
	_mesh_parent.add_child(smoke_grenade)

	# リモートグレネードとしてマーク
	smoke_grenade.is_remote = true
	smoke_grenade.network_grenade_id = grenade_id

	# 追跡（爆発イベント受信用）
	if grenade_id > 0:
		_active_grenades[grenade_id] = smoke_grenade

	smoke_grenade.throw_with_velocity(start_pos, velocity)
	smoke_grenade_thrown.emit(smoke_grenade, null)


## ネットワークからの爆発イベントを処理（リモートグレネード用）
func handle_grenade_explode_from_network(grenade_id: int, position: Vector3, _is_smoke: bool) -> void:
	print("[GRENADE EXPLODE] id=", grenade_id, " pos=", position)
	if not _active_grenades.has(grenade_id):
		push_warning("[GameManager] Grenade not found for explosion: ", grenade_id)
		return

	var grenade: Grenade = _active_grenades[grenade_id] as Grenade
	_active_grenades.erase(grenade_id)

	if is_instance_valid(grenade):
		grenade.explode_at_position(position)


## ドアマーカー到達時（移動を一時停止してドアキック）
func _on_door_marker_reached(character: Node, door: Node3D) -> void:
	if not is_instance_valid(character) or not is_instance_valid(door):
		# ドアが無効な場合はパス追従を再開
		_resume_path_after_door(character)
		return

	var char_body := character as CharacterBody3D
	if not char_body:
		_resume_path_after_door(character)
		return

	# ドアキック実行（完了後にパス追従を再開）
	_execute_door_kick_from_marker(char_body, door)


## マーカーからのドアキック実行（完了後にパス追従を再開）
func _execute_door_kick_from_marker(character: CharacterBody3D, door: Node3D) -> void:
	if not is_instance_valid(character) or not is_instance_valid(door):
		_resume_path_after_door(character)
		return

	var door_pos := door.global_position
	door_pos.y = character.global_position.y

	# モデルをTweenでスムーズに回転
	var anim_ctrl = character.get_anim_controller() if character.has_method("get_anim_controller") else null
	if not anim_ctrl:
		_resume_path_after_door(character)
		return

	# 現在の回転と目標の回転を計算
	var model = anim_ctrl.get_model() if anim_ctrl.has_method("get_model") else null
	if not model:
		# フォールバック: 即座に向きを変えてキック
		if character.has_method("face_towards"):
			character.face_towards(door_pos)
		_play_door_kick_animation_from_marker(character, door)
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
	tween.tween_callback(_play_door_kick_animation_from_marker.bind(character, door))


## ドアキックアニメーション再生（マーカーから）
func _play_door_kick_animation_from_marker(character: CharacterBody3D, door: Node3D) -> void:
	if not is_instance_valid(character) or not is_instance_valid(door):
		_resume_path_after_door(character)
		return

	var anim_ctrl = character.get_anim_controller() if character.has_method("get_anim_controller") else null
	if not anim_ctrl or not anim_ctrl.has_method("play_door_kick"):
		_resume_path_after_door(character)
		return

	# ドア方向を保存（キック完了後にこの向きを維持するため）
	var door_dir := (door.global_position - character.global_position).normalized()
	door_dir.y = 0.0
	if door_dir.length_squared() > 0.001:
		_door_kick_directions[character.get_instance_id()] = door_dir.normalized()

	# door_kick_impactシグナルに接続（キックがドアに当たるタイミングでドアを開く）
	if anim_ctrl.has_signal("door_kick_impact"):
		if not anim_ctrl.door_kick_impact.is_connected(_on_door_kick_done.bind(door, character)):
			anim_ctrl.door_kick_impact.connect(_on_door_kick_done.bind(door, character), CONNECT_ONE_SHOT)

	# door_kick_finishedシグナルに接続（アニメーション完了後にパス追従を再開）
	if anim_ctrl.has_signal("door_kick_finished"):
		if not anim_ctrl.door_kick_finished.is_connected(_on_door_kick_animation_finished_from_marker.bind(character)):
			anim_ctrl.door_kick_finished.connect(_on_door_kick_animation_finished_from_marker.bind(character), CONNECT_ONE_SHOT)

	anim_ctrl.play_door_kick()


## ドアキックアニメーション完了時（マーカーから）
func _on_door_kick_animation_finished_from_marker(character: CharacterBody3D) -> void:
	if not is_instance_valid(character):
		return

	var char_id := character.get_instance_id()
	if _door_kick_directions.has(char_id):
		var door_dir: Vector3 = _door_kick_directions[char_id]
		_door_kick_directions.erase(char_id)

		# キャラクターの向きをドア方向に設定
		if character.has_method("set_facing_direction_vec"):
			character.set_facing_direction_vec(door_dir)

	# パス追従を再開
	_resume_path_after_door(character)


## ドアキック後にパス追従を再開
func _resume_path_after_door(character: Node) -> void:
	if not is_instance_valid(character):
		return

	# PathExecutionManagerからコントローラーを取得してresumeを呼ぶ
	if path_execution_manager:
		var char_id = character.get_instance_id()
		if path_execution_manager._path_controllers.has(char_id):
			var controller = path_execution_manager._path_controllers[char_id]
			if controller.has_method("resume_after_door"):
				controller.resume_after_door()


# ============================================
# Multiplayer API
# ============================================

## マルチプレイヤーモードを有効化
func enable_multiplayer_mode(local_peer_id: int) -> void:
	_is_multiplayer_mode = true
	_local_peer_id = local_peer_id
	PlayerState.set_local_peer_id(local_peer_id)


## マルチプレイヤーモードを無効化（シングルプレイヤーに戻す）
func disable_multiplayer_mode() -> void:
	_is_multiplayer_mode = false
	_local_peer_id = 0
	PlayerState.clear_multiplayer_session()


## マルチプレイヤーモードかどうか
func is_multiplayer_mode() -> bool:
	return _is_multiplayer_mode


## ローカルプレイヤーのpeer_idを取得
func get_local_peer_id() -> int:
	return _local_peer_id


## キャラクターがローカルプレイヤーのものか判定
func is_local_character(character: Node) -> bool:
	if not _is_multiplayer_mode:
		return true  # シングルプレイヤーモードでは全てローカル

	var game_char := character as GameCharacter
	if game_char:
		return game_char.is_local()

	return true  # GameCharacterでない場合はローカル扱い


## キャラクターに対する操作権限があるか判定
func has_control_permission(character: Node) -> bool:
	# ローカルキャラクターでなければ操作不可
	if not is_local_character(character):
		return false

	# 敵キャラクターは操作不可
	if PlayerState.is_enemy(character):
		return false

	return true


## ローカルキャラクターのみをフィルタリング
func filter_local_characters(chars: Array) -> Array[Node]:
	var result: Array[Node] = []
	for character in chars:
		if is_local_character(character):
			result.append(character)
	return result


## リモートキャラクターのみをフィルタリング
func filter_remote_characters(chars: Array) -> Array[Node]:
	var result: Array[Node] = []
	for character in chars:
		if not is_local_character(character):
			result.append(character)
	return result


## ローカルプレイヤーの味方キャラクター一覧を取得
func get_local_friendly_characters() -> Array[Node]:
	var result: Array[Node] = []
	for character in characters:
		if is_local_character(character) and PlayerState.is_friendly(character):
			result.append(character)
	return result


## リモートプレイヤーのキャラクター一覧を取得
func get_remote_characters() -> Array[Node]:
	return filter_remote_characters(characters)


## キャラクターを登録（マルチプレイヤー対応）
## peer_idとnetwork_idを指定可能
func register_character_with_network(
	character: Node,
	owner_peer_id: int = 0,
	network_id: int = 0
) -> void:
	var game_char := character as GameCharacter
	if game_char:
		game_char.owner_peer_id = owner_peer_id
		game_char.network_id = network_id

	register_character(character)


## ネットワークIDからキャラクターを検索
func find_character_by_network_id(network_id: int) -> GameCharacter:
	for character in characters:
		var game_char := character as GameCharacter
		if game_char and game_char.network_id == network_id:
			return game_char
	return null


## peer_idからキャラクターを検索（複数可）
func find_characters_by_owner(owner_peer_id: int) -> Array[GameCharacter]:
	var result: Array[GameCharacter] = []
	for character in characters:
		var game_char := character as GameCharacter
		if game_char and game_char.owner_peer_id == owner_peer_id:
			result.append(game_char)
	return result


## 全キャラクターの状態をスナップショットとして取得
func get_all_character_snapshots() -> Array[SyncState.CharacterSnapshot]:
	var result: Array[SyncState.CharacterSnapshot] = []
	for character in characters:
		var game_char := character as GameCharacter
		if game_char:
			result.append(game_char.to_character_snapshot())
	return result


## ゲーム状態全体のスナップショットを取得
func get_game_state_snapshot() -> SyncState.GameStateSnapshot:
	var snapshot := SyncState.GameStateSnapshot.new()
	snapshot.is_game_started = true
	snapshot.round_number = 1  # TODO: ラウンド番号を管理

	# ラウンド状態
	if round_manager:
		snapshot.round_state = round_manager.to_round_state()

	# キャラクター状態
	for character in characters:
		var game_char := character as GameCharacter
		if game_char:
			snapshot.characters.append(game_char.to_character_state())

	# 保留パス
	if path_execution_manager:
		var paths_by_player = path_execution_manager.get_all_pending_paths_by_player()
		for player_id in paths_by_player:
			snapshot.pending_paths[player_id] = paths_by_player[player_id]

	return snapshot


## ゲーム状態スナップショットを適用（クライアント側用）
func apply_game_state_snapshot(snapshot: SyncState.GameStateSnapshot) -> void:
	# ラウンド状態を適用
	if round_manager and snapshot.round_state:
		round_manager.apply_round_state(snapshot.round_state)

	# キャラクター状態を適用
	for char_state in snapshot.characters:
		var game_char := find_character_by_network_id(char_state.character_id)
		if game_char:
			game_char.apply_remote_state(char_state)
