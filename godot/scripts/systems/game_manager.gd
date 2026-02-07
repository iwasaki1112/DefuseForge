extends Node
class_name GameManager
## コアゲームシステム管理
## システムの初期化・更新・入力処理・UI管理を一元管理

## システム生成ファクトリ
var _factory: GameSystemFactory = null

## 内部シグナル（GameManager内部・高頻度で使用されるため残留）
signal path_ready()
signal path_mode_changed(mode: int)
signal vision_point_added(anchor: Vector3, direction: Vector3)
## グレネード投擲シグナル
signal grenade_thrown(grenade: Node3D, character: Node)
## スモークグレネード投擲シグナル
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)
## ネットワークイベント（MultiplayerModeProviderが直接接続）
signal grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int)
signal grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool)
signal door_kick_network_event(door_id: int, character_network_id: int)
signal damage_network_event(attacker_id: int, target_id: int, damage: float, is_headshot: bool)

## コアシステム
var selection_manager: CharacterSelectionManager = null
var path_execution_manager: PathExecutionManager = null
var idle_manager: IdleCharacterManager = null
var path_mode_controller: PathModeController = null
var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null
var smoke_area_manager: SmokeAreaManager = null
var map_manager: MapManager = null
var path_drawer: Node3D = null
var character_setup_service: CharacterSetupService = null
var path_service: PathService = null
var vision_service: VisionService = null
var round_manager: RoundManager = null

## 抽出されたサービス
var character_manager: CharacterManagerService = null
var grenade_service: GrenadeService = null
var door_service: DoorService = null
var moving_path_vision_service: MovingPathVisionService = null

## UIコンポーネント（GameScreenから注入される）
var label_manager: CharacterLabelManager = null
var path_context_menu: PathContextMenu = null

## 外部参照
var camera: Camera3D = null
var characters: Array[Node] = []
var _mesh_parent: Node3D = null
var _map_container: Node3D = null
var _ui_layer: CanvasLayer = null

## スモークグレネードターゲット選択モード
var _grenade_target_mode: bool = false
var _context_menu_item_selected: bool = false
var _grenade_origin_path_data: Dictionary = {}
var _grenade_trajectory_preview: GrenadeTrajectoryPreview = null

## マルチプレイヤー状態
var _is_multiplayer_mode: bool = false
var _local_peer_id: int = 0

## 設定
var fow_map_size: Vector2 = Vector2(50, 50)
var default_vision_fov: float = 90.0
var default_vision_range: float = 15.0
var default_weapon_id: String = "glock"
var is_vision_enabled: bool = false

## 移動中パスVisionポイントはMovingPathVisionServiceに委譲


## セットアップ（カメラ、メッシュ親、UIレイヤーを指定）
## map_container: マップを追加する親ノード（省略時はmesh_parentを使用）
func setup(cam: Camera3D, mesh_parent: Node3D, ui_layer: CanvasLayer, map_size: Vector2 = Vector2(50, 50), map_container: Node3D = null) -> void:
	camera = cam
	_mesh_parent = mesh_parent
	_map_container = map_container if map_container else mesh_parent
	_ui_layer = ui_layer
	fow_map_size = map_size

	# ファクトリを初期化
	if _factory == null:
		_factory = GameSystemFactory.new()

	# 初期化順序が重要
	# SmokeAreaManagerはGrenadeServiceより先に初期化（依存関係）
	_setup_smoke_area_manager()

	# 抽出されたサービスを初期化
	_setup_character_manager_service()
	_setup_grenade_service(mesh_parent)
	_setup_door_service()

	_setup_selection_manager()
	_setup_path_execution_manager(mesh_parent)
	_setup_moving_path_vision_service(mesh_parent)
	_setup_idle_manager()
	_setup_path_drawer()
	_setup_path_mode_controller()
	_setup_vision_service()
	# VisionService初期化後にFoWシステムをGrenadeServiceに渡す（リモートグレネードのFoW可視性用）
	if grenade_service and fog_of_war_system:
		grenade_service.set_fow_system(fog_of_war_system)
	_setup_map_manager()
	_setup_path_service()
	_setup_round_manager()
	_setup_character_setup_service()



## キャラクターを登録（視界・武器・色・ラベルも自動セットアップ）
func register_character(character: Node) -> void:
	if characters.has(character):
		return

	characters.append(character)

	# CharacterManagerServiceにも登録
	if character_manager:
		character_manager.register_character(character)

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

	# ダメージシグナル接続（マルチプレイヤー同期用）
	# combat_awarenessは_complete_character_setupで遅延セットアップされるため、call_deferredで接続
	_connect_damage_signal.call_deferred(character)



## キャラクターを登録解除
func unregister_character(character: Node) -> void:
	if not characters.has(character):
		return

	characters.erase(character)

	# CharacterManagerServiceからも解除
	if character_manager:
		character_manager.unregister_character(character)

	if idle_manager:
		idle_manager.remove_character(character)

	# 視界システムから解除
	if vision_service:
		vision_service.unregister_character(character)

	# 移動中パスVisionポイントとプレビューをクリア
	clear_moving_path_vision_points_for_character(character)
	clear_moving_path_vision_preview()

	# PathFollowingControllerをクリーンアップ
	if path_execution_manager:
		path_execution_manager.cleanup_controller_for_character(character)

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
	# スモークグレネードターゲット選択モード中
	if _grenade_target_mode:
		var ground_pos = _screen_to_ground(screen_pos)
		if ground_pos != null:
			_complete_grenade_target_selection(ground_pos as Vector3)
		else:
			_cancel_grenade_target_mode()
		return true

	var clicked_character = raycast_character(screen_pos)

	match button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if clicked_character:
				# 敵キャラクターは無視
				if PlayerState.is_enemy(clicked_character):
					return false
				# 死亡キャラクターは無視
				var _gc := clicked_character as GameCharacter
				if _gc and not _gc.is_alive:
					return false
				# 移動中キャラクターを選択したら、移動を停止してパスモード開始
				if path_service and path_service.is_character_following_path(clicked_character):
					path_service.cancel_path_following(clicked_character, true)
					if selection_manager and not selection_manager.selected_characters.has(clicked_character):
						selection_manager.add_to_selection(clicked_character)
					start_move_mode()
					return true
				# パスモード中に別のキャラクターをクリック: 現在のパスモードを終了して新キャラクターへ
				if path_service and path_service.is_path_mode():
					var editing_char = path_mode_controller.get_editing_character() if path_mode_controller else null
					if clicked_character != editing_char:
						# 現在のモードを終了（パスがあれば確定、なければキャンセル）
						if path_service.has_path():
							path_service.confirm_path()
						else:
							path_service.cancel_path()
						# 新しいキャラクターを選択してパスモード開始
						selection_manager.deselect_all()
						selection_manager.add_to_selection(clicked_character)
						start_move_mode()
						return true
					# 同じキャラクターをクリック: 何もしない（パスモード継続）
					return true
				# 味方キャラクタークリック: 選択してパスモード開始
				selection_manager.deselect_all()
				selection_manager.add_to_selection(clicked_character)
				start_move_mode()
				return true
			else:
				# キャラクター以外をクリック
				# パスモード中の場合
				if path_service and path_service.is_path_mode():
					if path_service.has_path():
						path_service.confirm_path()
					else:
						path_service.cancel_path()
					return true
				# 通常時: 選択解除
				selection_manager.deselect_all()
				return true
	return false


## レイキャストでキャラクターを検出
## タップ用Area3D（大きめ）を優先し、物理ボディも検出する
func raycast_character(screen_pos: Vector2) -> Node:
	if not camera:
		return null

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_dir * 100.0

	var space_state := _mesh_parent.get_world_3d().direct_space_state

	# まずArea3D（タップエリア）を検出
	var area_query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	area_query.collide_with_areas = true
	area_query.collide_with_bodies = false

	var area_result := space_state.intersect_ray(area_query)
	if not area_result.is_empty():
		var collider = area_result.collider
		for character in characters:
			if _is_child_of(collider, character):
				return character

	# Area3Dにヒットしなかった場合、物理ボディも検出
	var body_query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	body_query.collide_with_areas = false
	body_query.collide_with_bodies = true

	var body_result := space_state.intersect_ray(body_query)
	if not body_result.is_empty():
		var collider = body_result.collider
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
## local_only: trueの場合、ローカルプレイヤーのキャラクターのみ実行
func execute_all_paths(run: bool, local_only: bool = false) -> int:
	return path_service.execute_all_paths(run, local_only) if path_service else 0


## 指定位置近くにある確定済みパスまたは移動中パスの先端を検索し、パス継続モードを開始
## @param screen_pos: 画面座標
## @return: パス継続モードを開始した場合true
func try_start_path_continuation_at_position(screen_pos: Vector2) -> bool:
	if not path_execution_manager or not camera:
		return false

	# パスモード中は通常のパス処理に任せる
	if is_path_mode():
		return false

	# 地面位置を取得
	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return false

	var ground_pos: Vector3 = intersect as Vector3

	# 確定済みパスと移動中パスの両方を検索
	var pending_result := path_execution_manager.find_path_endpoint_at_position(ground_pos, 1.5)
	var moving_result := path_execution_manager.find_moving_path_endpoint_at_position(ground_pos, 1.5)

	# より近い方を選択
	var use_pending := false
	var use_moving := false
	if not pending_result.is_empty() and not moving_result.is_empty():
		if pending_result.get("distance", INF) <= moving_result.get("distance", INF):
			use_pending = true
		else:
			use_moving = true
	elif not pending_result.is_empty():
		use_pending = true
	elif not moving_result.is_empty():
		use_moving = true
	else:
		return false

	var result := pending_result if use_pending else moving_result
	var is_moving_path := use_moving

	var character: Node = result.get("character")
	if not is_instance_valid(character):
		return false

	var endpoint: Vector3 = result.get("endpoint", Vector3.ZERO)
	if endpoint == Vector3.ZERO:
		return false

	# キャラクター色を取得
	var char_color := CharacterColorManager.get_character_color(character)

	# 終点からパスモードを開始（既存パスに追加される）
	if path_service:
		return path_service.start_path_mode_from_point(character, endpoint, char_color, is_moving_path)

	return false


## 指定位置近くにある確定済みパス上でVisionポイント配置モードを開始
## @param screen_pos: 画面座標
## @param ground_pos: 地面座標（既に計算済みの場合）
## @return: Visionポイント配置モードを開始した場合true
func try_start_vision_point_on_confirmed_path(screen_pos: Vector2, ground_pos: Vector3 = Vector3.ZERO, threshold: float = GameConstants.PATH_CLICK_THRESHOLD) -> bool:
	if not path_execution_manager or not camera:
		return false

	# 地面位置が未指定の場合は計算
	var target_ground_pos := ground_pos
	if target_ground_pos == Vector3.ZERO:
		var ground_plane := Plane(Vector3.UP, 0.0)
		var ray_origin := camera.project_ray_origin(screen_pos)
		var ray_dir := camera.project_ray_normal(screen_pos)
		var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
		if not intersect:
			return false
		target_ground_pos = intersect as Vector3

	# 確定済みパス上の点を検索（先端は除外 - 先端はパス延長用）
	var path_result := path_execution_manager.find_path_point_at_position(target_ground_pos, threshold)
	if path_result.is_empty():
		return false

	var character: Node = path_result.get("character")
	if not is_instance_valid(character):
		return false

	# キャラクター色を取得
	var char_color := CharacterColorManager.get_character_color(character)

	# 確定済みパスのデータを取得
	var existing_path: Array = path_execution_manager.get_pending_path_for_character(character)
	if existing_path.size() < 2:
		if Debug.enabled: print("[PointDebug] try_start_vision_point_on_confirmed_path: existing path too short (%d)" % existing_path.size())
		return false

	# 既存パスを使用してパスモードを開始
	if path_service:
		if not path_service.start_path_mode_with_existing_path(character, existing_path, char_color):
			if Debug.enabled: print("[PointDebug] try_start_vision_point_on_confirmed_path: failed to start path mode")
			return false

	# Visionモードを開始して、長押し位置をアンカーとして設定
	if path_drawer:
		if not path_drawer.start_vision_mode():
			if Debug.enabled: print("[PointDebug] try_start_vision_point_on_confirmed_path: start_vision_mode failed")
			return false
		# 公開APIを使用してアンカー位置でVisionモードを開始
		path_drawer.start_vision_mode_with_anchor(
			path_result.point,
			path_result.path_ratio,
			true  # 確認済みパスからなので自動確定
		)

	return true


## 指定位置近くにある移動中パス上でVisionポイント配置モードを開始
## @param screen_pos: 画面座標
## @param ground_pos: 地面座標（既に計算済みの場合）
## @param threshold: クリック判定閾値（デフォルトはPC向け）
## @return: Visionポイント配置モードを開始した場合の情報Dictionary、失敗時は空
func try_start_vision_point_on_moving_path(screen_pos: Vector2, ground_pos: Vector3 = Vector3.ZERO, threshold: float = GameConstants.PATH_CLICK_THRESHOLD) -> Dictionary:
	if not path_execution_manager or not camera:
		return {}

	# 地面位置が未指定の場合は計算
	var target_ground_pos := ground_pos
	if target_ground_pos == Vector3.ZERO:
		var ground_plane := Plane(Vector3.UP, 0.0)
		var ray_origin := camera.project_ray_origin(screen_pos)
		var ray_dir := camera.project_ray_normal(screen_pos)
		var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
		if not intersect:
			return {}
		target_ground_pos = intersect as Vector3

	# 移動中パス上の点を検索（先端は除外 - 先端はパス延長用）
	var path_result := path_execution_manager.find_moving_path_point_at_position(target_ground_pos, threshold)
	if path_result.is_empty():
		return {}

	return path_result


## 移動中パスにVisionポイントを追加
## @param character: 対象キャラクター
## @param path_ratio: パス上の比率
## @param anchor: アンカー位置
## @param target_point: 視線方向の目標点
## @return: 成功した場合true
func add_vision_point_to_moving_path(character: Node, path_ratio: float, anchor: Vector3, target_point: Vector3) -> bool:
	if moving_path_vision_service:
		return moving_path_vision_service.add_vision_point(character, path_ratio, anchor, target_point)
	return false


## 移動中パスVisionポイントのプレビューを更新（MovingPathVisionServiceに委譲）
func update_moving_path_vision_preview(character: Node, anchor: Vector3, target_point: Vector3, path_ratio: float = 0.0) -> void:
	if moving_path_vision_service:
		moving_path_vision_service.update_preview(character, anchor, target_point, path_ratio)


## 移動中パスVisionポイントのプレビューをクリア（MovingPathVisionServiceに委譲）
func clear_moving_path_vision_preview() -> void:
	if moving_path_vision_service:
		moving_path_vision_service.clear_preview()


## 移動中パスVisionポイントをクリア（MovingPathVisionServiceに委譲）
func clear_moving_path_vision_points_for_character(character: Node) -> void:
	if moving_path_vision_service:
		moving_path_vision_service.clear_for_character(character)


## 全ての移動中パスVisionポイントをクリア（MovingPathVisionServiceに委譲）
func clear_all_moving_path_vision_points() -> void:
	if moving_path_vision_service:
		moving_path_vision_service.clear_all()


## 移動中パスVisionポイントを進行状況に応じて非表示（MovingPathVisionServiceに委譲）
func hide_passed_moving_path_vision_points(character: Node, current_ratio: float) -> void:
	if moving_path_vision_service:
		moving_path_vision_service.hide_passed_points(character, current_ratio)


## 全保留パスをクリア
func clear_all_pending_paths() -> void:
	if path_service:
		path_service.clear_all_pending_paths()


## 全パス追従キャンセル
func cancel_all_path_following() -> void:
	if path_service:
		path_service.cancel_all_path_following()


## ========================================
## 視界/FoW制御
## ========================================

## 視界/FoWの有効化切り替え
func set_vision_enabled(enabled: bool) -> void:
	if Debug.enabled: print("[FOW] GameManager.set_vision_enabled: ", enabled)
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


## UIレイヤーを取得
func get_ui_layer() -> CanvasLayer:
	return _ui_layer


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
	var primary_char := primary as GameCharacter

	# リモートキャラクターはネットワークから状態を受信するためスキップ
	if primary_char and primary_char.is_local() and idle_manager and not is_character_following_path(primary):
		idle_manager.process_primary_idle(primary, delta)

	# リモートキャラクターの補間更新
	_update_remote_character_interpolation(delta)


## ========================================
## 状態取得API
## ========================================

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

## パスがあるか
func has_path() -> bool:
	return path_service.has_path() if path_service else false


## 視線モード開始
func start_vision_mode() -> bool:
	return path_service.start_vision_mode() if path_service else false


## 視線ポイントを削除
func remove_last_vision_point() -> void:
	if path_service:
		path_service.remove_last_vision_point()


## 視線ポイント数を取得
func get_vision_point_count() -> int:
	return path_service.get_vision_point_count() if path_service else 0


## アクティブ編集キャラクターを設定
func set_active_edit_character(character: Node) -> void:
	if path_service:
		path_service.set_active_edit_character(character)


## キャラクター色を設定
func set_path_drawer_color(color: Color) -> void:
	if path_service:
		path_service.set_path_drawer_color(color)


## ========================================
## ファサードAPI（深いネスト回避用）
## ========================================

## PathService: 最後のポイントをUndo
func undo_last_point() -> void:
	if path_service:
		path_service.undo_last_point()


## PathService: グローバルUndo
func global_undo() -> bool:
	return path_service.global_undo() if path_service else false


## PathService: Undo履歴クリア
func clear_undo_history() -> void:
	if path_service:
		path_service.clear_undo_history()


## PathService: パス追従をキャンセル
func cancel_path_following(character: Node, clear_pending: bool = true) -> void:
	if path_service:
		path_service.cancel_path_following(character, clear_pending)


## PathService: キャラクターの保留パスがあるか
func has_pending_path_for_character(character: Node) -> bool:
	return path_service.has_pending_path_for_character(character) if path_service else false


## PathService: 指定キャラクターのパスを実行
func execute_path_for_character(character: Node, run: bool) -> bool:
	return path_service.execute_path_for_character(character, run) if path_service else false


## PathService: PathUndoManagerのシグナルに接続するためのアクセサ
func get_path_undo_manager() -> PathUndoManager:
	return path_service.path_undo_manager if path_service else null


## PathService: PathModeControllerへのアクセサ
func get_path_mode_controller() -> PathModeController:
	return path_service.path_mode_controller if path_service else null


## PathExecutionManager: 確定済みパスの先端位置を検索
func find_path_endpoint_at_position(ground_pos: Vector3, threshold: float) -> Dictionary:
	return path_execution_manager.find_path_endpoint_at_position(ground_pos, threshold) if path_execution_manager else {}


## PathExecutionManager: 確定済みパス上の点を検索
func find_path_point_at_position(ground_pos: Vector3, threshold: float) -> Dictionary:
	return path_execution_manager.find_path_point_at_position(ground_pos, threshold) if path_execution_manager else {}


## PathExecutionManager: プレイヤーのパスを確定（マルチプレイヤー用）
func confirm_path_for_player(player_id: int, path_msg: NetworkMessages.PathConfirmMessage, character: Node) -> bool:
	if path_execution_manager:
		return path_execution_manager.confirm_path_for_player(player_id, path_msg, character)
	return false


## ========================================
## UI管理
## ========================================

## UIコンポーネントを設定（GameScreenから呼び出し）
func set_label_manager(mgr: CharacterLabelManager) -> void:
	label_manager = mgr


## パスコンテキストメニューを設定（GameScreenから呼び出し）
func set_path_context_menu(menu: PathContextMenu) -> void:
	path_context_menu = menu
	if path_context_menu:
		path_context_menu.menu_item_selected.connect(_on_path_context_menu_selected)
		path_context_menu.menu_closed.connect(_on_path_context_menu_closed)


## 全キャラクターの色・ラベルを再割り当て
func refresh_character_colors() -> void:
	CharacterColorManager.clear_all()
	if label_manager:
		label_manager.clear_all()
	for character in characters:
		if character_setup_service:
			character_setup_service.assign_color_and_label(character)


## パス上タップ時のコンテキストメニューを表示
## @param screen_pos: 表示位置（スクリーン座標）
## @param path_data: パス情報（character, path_ratio, point等）
func show_path_context_menu(screen_pos: Vector2, path_data: Dictionary) -> void:
	if path_context_menu and not path_context_menu.is_open():
		path_context_menu.show_at_position(screen_pos, path_data)


## コンテキストメニューが開いているか
func is_path_context_menu_open() -> bool:
	return path_context_menu and path_context_menu.is_open()


## コンテキストメニュー選択時のコールバック
func _on_path_context_menu_selected(item_id: String, path_data: Dictionary) -> void:
	_context_menu_item_selected = true
	match item_id:
		"smoke_grenade":
			_start_grenade_target_mode(path_data)


## コンテキストメニュー閉じ時のコールバック
func _on_path_context_menu_closed() -> void:
	# ボタン選択なしでメニューが閉じられた場合（オーバーレイタップ等）のみキャンセル
	if not _context_menu_item_selected and _grenade_target_mode:
		_cancel_grenade_target_mode()
	_context_menu_item_selected = false


## 同期Waitポイントを追加（InputControllerから直接呼び出し可能）
## @param path_data: パス情報（character, path_ratio, point等）
func add_sync_wait_point(path_data: Dictionary) -> void:
	var path_ratio: float = path_data.get("path_ratio", 0.0)
	var anchor: Vector3 = path_data.get("point", Vector3.ZERO)
	var character = path_data.get("character", null)

	# パスモード中（pending path）の場合、PathDrawerにポイントを追加
	if is_path_mode() and path_drawer:
		path_drawer.add_sync_wait_point(path_ratio, anchor)
		# NOTE: Undo履歴はPathDrawer → PathService経由で自動的に追加されるため、
		# ここで重複して呼ぶ必要はない
		return

	# 確認済みパスの場合、PathExecutionManagerにポイントを追加
	if character and path_execution_manager:
		path_execution_manager.add_sync_wait_point_to_path(character, path_ratio, anchor)
		# NOTE: 確認済みパスへの直接追加はシグナル経由ではないため、ここで履歴に追加
		if path_service:
			path_service.push_wait_point_to_history(character, path_ratio, -1.0)


## スモークグレネードターゲット選択モード中か
func is_grenade_target_mode() -> bool:
	return _grenade_target_mode


## グレネードターゲットプレビューを更新（ドラッグ/モーション時に呼ばれる）
func update_grenade_target_preview(screen_pos: Vector2) -> void:
	if not _grenade_target_mode or not _grenade_trajectory_preview:
		return

	var ground_pos = _screen_to_ground(screen_pos)
	if ground_pos == null:
		return

	var anchor: Vector3 = _grenade_origin_path_data.get("point", Vector3.ZERO)
	var start_pos := anchor + Vector3(0, 1.0, 0)  # キャラクター手元位置
	_grenade_trajectory_preview.update(start_pos, ground_pos as Vector3)


## スモークグレネードターゲット選択モードを開始
func _start_grenade_target_mode(path_data: Dictionary) -> void:
	_grenade_target_mode = true
	_grenade_origin_path_data = path_data.duplicate()

	# 軌道プレビューを生成
	if _mesh_parent:
		_grenade_trajectory_preview = GrenadeTrajectoryPreview.new()
		_grenade_trajectory_preview.setup(_mesh_parent)


## スモークグレネードターゲット選択モードをキャンセル
func _cancel_grenade_target_mode() -> void:
	_grenade_target_mode = false
	_grenade_origin_path_data = {}

	# 軌道プレビューを削除
	if _grenade_trajectory_preview:
		_grenade_trajectory_preview.destroy()
		_grenade_trajectory_preview = null


## スモークグレネードターゲット選択を完了（地面タップ時）
func _complete_grenade_target_selection(target_pos: Vector3) -> void:
	if _grenade_origin_path_data.is_empty():
		_cancel_grenade_target_mode()
		return

	var path_ratio: float = _grenade_origin_path_data.get("path_ratio", 0.0)
	var anchor: Vector3 = _grenade_origin_path_data.get("point", Vector3.ZERO)
	var character = _grenade_origin_path_data.get("character", null)

	if not is_instance_valid(character):
		_cancel_grenade_target_mode()
		return

	add_smoke_grenade_point(character, path_ratio, anchor, target_pos)
	_cancel_grenade_target_mode()


## スモークグレネードポイントをパスに追加
## @param character: 対象キャラクター
## @param path_ratio: パス上の位置（0.0〜1.0）
## @param anchor: パス上の3D位置
## @param target_pos: グレネード着弾地点
func add_smoke_grenade_point(character: Node, path_ratio: float, anchor: Vector3, target_pos: Vector3) -> void:
	if not character or not path_execution_manager:
		return

	path_execution_manager.add_smoke_grenade_point_to_path(character, path_ratio, anchor, target_pos)


## 画面座標から地面座標に変換（ヘルパー）
func _screen_to_ground(screen_pos: Vector2) -> Variant:
	if not camera:
		return null
	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	return intersect


## 全キャラクターの同期待機を解除
func release_all_sync_waiting_characters() -> void:
	if path_execution_manager:
		path_execution_manager.release_all_sync_waiting()


## ========================================
## 内部：システムセットアップ
## ========================================

func _setup_selection_manager() -> void:
	if selection_manager == null:
		selection_manager = _factory.create_selection_manager()
		add_child(selection_manager)
		selection_manager.selection_changed.connect(_on_selection_changed)
		selection_manager.primary_changed.connect(_on_primary_changed)


func _setup_path_execution_manager(mesh_parent: Node3D) -> void:
	if path_execution_manager == null:
		path_execution_manager = _factory.create_path_execution_manager(mesh_parent)
		add_child(path_execution_manager)
		path_execution_manager.paths_execution_started.connect(_on_paths_execution_started)
		# パス完了時に移動中パスVisionポイントをクリア
		path_execution_manager.character_path_completed.connect(_on_character_path_completed)
		# Visionポイント到達時に移動中パスポイントを非表示
		path_execution_manager.vision_point_reached.connect(_on_vision_point_reached)
		# パス進行更新時に移動中パスポイントを非表示チェック
		path_execution_manager.path_progress_updated.connect(_on_path_progress_updated)
		# 延長ポイントの比率がスケールされた時に移動中パスポイントの比率を更新
		path_execution_manager.extension_points_scaled.connect(_on_extension_points_scaled)
		# グレネード投擲リリース時にGrenadeServiceでスモークグレネードを生成
		path_execution_manager.grenade_throw_released.connect(_on_grenade_throw_released)


func _setup_idle_manager() -> void:
	if idle_manager == null:
		idle_manager = _factory.create_idle_manager(
			characters,
			func(c): return path_execution_manager.is_character_following_path(c) if path_execution_manager else false,
			func(): return selection_manager.primary_character if selection_manager else null
		)
		add_child(idle_manager)


func _setup_smoke_area_manager() -> void:
	if smoke_area_manager == null:
		smoke_area_manager = _factory.create_smoke_area_manager()
		add_child(smoke_area_manager)


func _setup_path_drawer() -> void:
	if path_drawer == null:
		path_drawer = _factory.create_path_drawer(camera, path_execution_manager)
		add_child(path_drawer)
		_factory.setup_path_drawer(path_drawer, camera, path_execution_manager)
		path_drawer.auto_confirm_requested.connect(_on_path_drawer_auto_confirm_requested)


func _setup_path_mode_controller() -> void:
	if path_mode_controller == null:
		path_mode_controller = _factory.create_path_mode_controller(
			path_drawer, selection_manager, path_execution_manager
		)
		add_child(path_mode_controller)


func _setup_vision_service() -> void:
	if vision_service == null:
		vision_service = _factory.create_vision_service(
			fow_map_size, is_vision_enabled, smoke_area_manager
		)
		add_child(vision_service)
		fog_of_war_system = vision_service.fog_of_war_system
		enemy_visibility_system = vision_service.enemy_visibility_system


func _setup_map_manager() -> void:
	if map_manager == null:
		map_manager = _factory.create_map_manager(_map_container, self)
		add_child(map_manager)
		map_manager.map_loaded.connect(_on_map_loaded)
		map_manager.map_will_unload.connect(_on_map_will_unload)


## リモートキャラクターの補間更新
func _update_remote_character_interpolation(delta: float) -> void:
	for character in characters:
		var game_char := character as GameCharacter
		if game_char and game_char.has_method("update_remote_interpolation"):
			game_char.update_remote_interpolation(delta)


func _setup_path_service() -> void:
	if path_service == null:
		path_service = _factory.create_path_service(
			path_drawer, selection_manager, path_execution_manager, path_mode_controller
		)
		add_child(path_service)
		path_service.mode_started.connect(_on_path_mode_started)
		path_service.mode_ended.connect(_on_path_mode_ended)
		path_service.mode_cancelled.connect(_on_path_mode_cancelled)
		path_service.path_ready.connect(_on_path_ready)
		path_service.path_confirmed.connect(_on_path_confirmed)
		path_service.all_paths_completed.connect(_on_all_paths_completed)
		path_service.paths_cleared.connect(_on_paths_cleared)
		path_service.mode_changed.connect(_on_path_mode_changed)
		path_service.vision_point_added.connect(_on_vision_point_added)


func _setup_round_manager() -> void:
	if round_manager == null:
		round_manager = _factory.create_round_manager(self)
		add_child(round_manager)
		round_manager.round_started.connect(_on_round_started)
		round_manager.round_ended.connect(_on_round_ended)
		round_manager.timer_updated.connect(_on_round_timer_updated)
		round_manager.survivor_count_changed.connect(_on_survivor_count_changed)


func _setup_character_setup_service() -> void:
	if character_setup_service == null:
		character_setup_service = _factory.create_character_setup_service(
			vision_service.enemy_visibility_system,
			vision_service.fog_of_war_system,
			label_manager,
			default_weapon_id,
			is_vision_enabled,
			default_vision_fov,
			default_vision_range
		)


func _setup_character_manager_service() -> void:
	if character_manager == null:
		character_manager = _factory.create_character_manager_service()
		add_child(character_manager)


func _setup_grenade_service(mesh_parent: Node3D) -> void:
	if grenade_service == null:
		grenade_service = _factory.create_grenade_service(mesh_parent, smoke_area_manager)
		add_child(grenade_service)
		# シグナル転送
		grenade_service.grenade_thrown.connect(func(g, c): grenade_thrown.emit(g, c))
		grenade_service.smoke_grenade_thrown.connect(func(g, c): smoke_grenade_thrown.emit(g, c))
		grenade_service.grenade_network_event.connect(func(p, v, s, i): grenade_network_event.emit(p, v, s, i))
		grenade_service.grenade_explode_network_event.connect(func(i, p, s): grenade_explode_network_event.emit(i, p, s))


func _setup_door_service() -> void:
	if door_service == null:
		door_service = _factory.create_door_service(character_manager, _force_update_all_vision)
		add_child(door_service)
		# シグナル転送
		door_service.door_kick_network_event.connect(func(d, c): door_kick_network_event.emit(d, c))


func _setup_moving_path_vision_service(mesh_parent: Node3D) -> void:
	if moving_path_vision_service == null:
		moving_path_vision_service = _factory.create_moving_path_vision_service(
			mesh_parent, path_execution_manager
		)


## ========================================
## 内部：シグナルハンドラ
## ========================================

func _on_selection_changed(selected: Array[Node], primary: Node) -> void:
	SignalBus.selection_changed.emit(selected, primary)


func _on_primary_changed(character: Node) -> void:
	SignalBus.primary_changed.emit(character)


func _on_path_mode_started(character: Node) -> void:
	SignalBus.path_mode_started.emit(character)


func _on_path_mode_ended() -> void:
	SignalBus.path_mode_ended.emit()


func _on_path_mode_cancelled() -> void:
	SignalBus.path_mode_cancelled.emit()


func _on_path_ready() -> void:
	path_ready.emit()


func _on_path_confirmed(count: int) -> void:
	SignalBus.path_confirmed.emit(count)


func _on_all_paths_completed() -> void:
	SignalBus.all_paths_completed.emit()


func _on_character_path_completed(character: Node) -> void:
	# 移動中パスVisionポイントをクリア
	clear_moving_path_vision_points_for_character(character)


func _on_vision_point_reached(character: Node, path_ratio: float) -> void:
	# 移動中パスVisionポイントを進行状況に応じて非表示
	hide_passed_moving_path_vision_points(character, path_ratio)


func _on_path_progress_updated(character: Node) -> void:
	# パス進行時にも移動中パスVisionポイントを非表示チェック
	hide_passed_moving_path_vision_points(character, 0.0)


func _on_extension_points_scaled(character: Node, _scale: float) -> void:
	# 移動中パスVisionポイントの比率をアンカー位置から再計算（サービスに委譲）
	if not character or not path_execution_manager or not moving_path_vision_service:
		return

	# 現在の完全な残りパスを取得
	var full_path: Array[Vector3] = path_execution_manager.get_full_remaining_path_array(character)
	if full_path.size() < 2:
		return

	# サービスに比率再計算を委譲
	moving_path_vision_service.recalculate_ratios_on_scale(
		character,
		full_path,
		_calculate_ratio_from_position_on_path
	)


## ワールド座標からパス上の比率を計算（最近点を使用）
func _calculate_ratio_from_position_on_path(path: Array[Vector3], position: Vector3) -> float:
	if path.is_empty() or path.size() < 2:
		return 0.0

	# パス全体の長さを計算
	var total_length: float = 0.0
	for i in range(1, path.size()):
		total_length += path[i - 1].distance_to(path[i])

	if total_length < 0.001:
		return 0.0

	# パス上の最近点を見つける
	var best_ratio: float = 0.0
	var best_distance: float = INF
	var accumulated: float = 0.0

	for i in range(1, path.size()):
		var segment_start = path[i - 1]
		var segment_end = path[i]
		var segment_length = segment_start.distance_to(segment_end)

		if segment_length < 0.001:
			accumulated += segment_length
			continue

		# セグメント上の最近点を計算
		var segment_dir = (segment_end - segment_start).normalized()
		var to_pos = position - segment_start
		var proj_length = to_pos.dot(segment_dir)
		proj_length = clamp(proj_length, 0.0, segment_length)

		var closest_point = segment_start + segment_dir * proj_length
		var dist = position.distance_to(closest_point)

		if dist < best_distance:
			best_distance = dist
			best_ratio = (accumulated + proj_length) / total_length

		accumulated += segment_length

	return clamp(best_ratio, 0.0, 1.0)


func _on_paths_execution_started(count: int) -> void:
	SignalBus.paths_execution_started.emit(count)


## グレネード投擲リリース時のコールバック
## キャラクターの手元位置からターゲットに向けてスモークグレネードを生成
func _on_grenade_throw_released(character: CharacterBody3D, target_pos: Vector3) -> void:
	if not grenade_service or not is_instance_valid(character):
		return

	# 投擲開始位置（キャラクターの手元付近）
	var start_pos := character.global_position + Vector3(0, 1.0, 0)

	# 着弾マーカーを探して爆発時に非表示にする
	var target_marker := _find_smoke_target_marker(character, target_pos)

	var result := grenade_service.spawn_and_throw_smoke_grenade(start_pos, target_pos, character)
	var smoke_grenade = result[0]
	var velocity: Vector3 = result[1]
	var grenade_id: int = result[2]
	if smoke_grenade:
		if target_marker:
			smoke_grenade.exploded.connect(_on_smoke_grenade_exploded_hide_marker.bind(target_marker))
		smoke_grenade_thrown.emit(smoke_grenade, character)
		# マルチプレイヤー同期: ネットワークイベントを送信
		_emit_grenade_network_event(start_pos, velocity, true, grenade_id)


## スモークグレネード爆発時に着弾マーカーを非表示
func _on_smoke_grenade_exploded_hide_marker(_position: Vector3, marker: MeshInstance3D) -> void:
	if is_instance_valid(marker):
		marker.visible = false


## 着弾マーカーを位置ベースで探す
func _find_smoke_target_marker(character: Node, target_pos: Vector3) -> MeshInstance3D:
	var char_id = character.get_instance_id()
	var target_flat = Vector3(target_pos.x, 0.0, target_pos.z)

	# pending_pathsから探す
	if path_execution_manager and path_execution_manager._path_store.pending_paths.has(char_id):
		var data = path_execution_manager._path_store.pending_paths[char_id]
		var markers: Array = data.get("smoke_grenade_points", [])
		for marker in markers:
			if not is_instance_valid(marker) or not marker.visible:
				continue
			var pos = marker.global_position
			pos.y = 0.0
			if pos.distance_to(target_flat) < 0.3:
				return marker

	# moving_path_pointsから探す
	if path_execution_manager:
		var moving = path_execution_manager._point_mesh_manager.get_moving_path_points(char_id, ActionPointData.Type.SMOKE_GRENADE)
		for marker in moving:
			if not is_instance_valid(marker) or not marker.visible:
				continue
			var pos = marker.global_position
			pos.y = 0.0
			if pos.distance_to(target_flat) < 0.3:
				return marker

	return null


func _on_paths_cleared() -> void:
	SignalBus.paths_cleared.emit()


func _on_path_mode_changed(mode: int) -> void:
	path_mode_changed.emit(mode)


func _on_vision_point_added(anchor: Vector3, direction: Vector3) -> void:
	vision_point_added.emit(anchor, direction)


func _on_path_drawer_auto_confirm_requested() -> void:
	if Debug.enabled: print("[PointDebug] _on_path_drawer_auto_confirm_requested: calling confirm_path")
	confirm_path()


func _on_round_started() -> void:
	SignalBus.round_started.emit()


func _on_round_ended(winner: int, reason: int) -> void:
	SignalBus.round_ended.emit(winner, reason)


func _on_round_timer_updated(remaining: float) -> void:
	SignalBus.round_timer_updated.emit(remaining)


func _on_survivor_count_changed(ct_count: int, t_count: int) -> void:
	SignalBus.survivor_count_changed.emit(ct_count, t_count)


## キャラクター死亡時の処理
func _on_character_died(character: GameCharacter) -> void:
	# パス追従をキャンセルしてパスメッシュ・ポイントをクリア
	if path_service:
		path_service.cancel_path_following(character, true)

	# 選択解除
	if selection_manager:
		selection_manager.remove_from_selection(character)


## ========================================
## ドアキック処理（ポイントからの実行用）
## ========================================

## ドアキックインパクト時（フレーム36/66）（DoorServiceに委譲）
## character: ドアをキックしたキャラクター（位置から回転方向を計算）
func _on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void:
	if door_service:
		door_service.on_door_kick_done(door, character)


## ========================================
## グレネード関連（GrenadeServiceに委譲）
## ========================================

## グレネードを生成して投擲（内部ヘルパー）
## 戻り値: [grenade, velocity, grenade_id] のトリプル
func _spawn_and_throw_grenade(start_pos: Vector3, target_pos: Vector3, _bounce_point: Vector3, thrower: Node3D = null) -> Array:
	if grenade_service:
		return grenade_service.spawn_and_throw_grenade(start_pos, target_pos, thrower)
	return [null, Vector3.ZERO, 0]


## スモークグレネードを生成して投擲（内部ヘルパー）
## 戻り値: [smoke_grenade, velocity, grenade_id] のトリプル
func _spawn_and_throw_smoke_grenade(start_pos: Vector3, target_pos: Vector3, _bounce_point: Vector3, thrower: Node3D = null) -> Array:
	if grenade_service:
		return grenade_service.spawn_and_throw_smoke_grenade(start_pos, target_pos, thrower)
	return [null, Vector3.ZERO, 0]


func _emit_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int = 0) -> void:
	if grenade_service:
		grenade_service.emit_grenade_network_event(start_pos, velocity, is_smoke, grenade_id)


## ネットワークからグレネードをスポーン（リモート用）- 速度を直接使用
func spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0) -> void:
	if grenade_service:
		grenade_service.spawn_grenade_from_network(start_pos, velocity, grenade_id)


## ネットワークからスモークグレネードをスポーン（リモート用）- 速度を直接使用
func spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0) -> void:
	if grenade_service:
		grenade_service.spawn_smoke_grenade_from_network(start_pos, velocity, grenade_id)


## ネットワークからの爆発イベントを処理（リモートグレネード用）
func handle_grenade_explode_from_network(grenade_id: int, position: Vector3, is_smoke: bool) -> void:
	if grenade_service:
		grenade_service.handle_grenade_explode_from_network(grenade_id, position, is_smoke)


## ========================================
## ドアID管理（マルチプレイヤー同期用）
## ========================================

## ドアを登録し、一意のIDを割り当て（DoorServiceに委譲）
## Returns: 割り当てられたドアID
func register_door(door: Node3D) -> int:
	if door_service:
		return door_service.register_door(door)
	return 0


## ドアIDからドアノードを取得（DoorServiceに委譲）
func get_door_by_id(door_id: int) -> Node3D:
	if door_service:
		return door_service.get_door_by_id(door_id)
	return null


## ドアノードからドアIDを取得（DoorServiceに委譲）
func get_door_id(door: Node3D) -> int:
	if door_service:
		return door_service.get_door_id(door)
	return 0


## 全ドアを登録解除（マップアンロード時に呼ぶ）（DoorServiceに委譲）
func clear_door_registry() -> void:
	if door_service:
		door_service.clear_door_registry()


## マップ内の全ドアを登録（"doors"グループから取得）（DoorServiceに委譲）
func register_all_doors_in_map() -> void:
	if door_service:
		door_service.register_all_doors_in_map()


## マップロード完了時
func _on_map_loaded(_map_id: String, _map_instance: Node3D) -> void:
	# FoWマップサイズのフォールバック値を更新（循環参照回避のためここで設定）
	if map_manager and map_manager.current_preset:
		fow_map_size = map_manager.current_preset.map_size

	# ドアを登録
	register_all_doors_in_map()


## マップアンロード前
func _on_map_will_unload(_map_id: String) -> void:
	# 移動中パスVisionポイントとプレビューをすべてクリア
	clear_all_moving_path_vision_points()
	clear_moving_path_vision_preview()
	# PathFollowingControllerをすべてクリーンアップ
	if path_execution_manager:
		path_execution_manager.cleanup_all_controllers()
	# ドア登録をクリア
	clear_door_registry()


## ネットワークからのドアキックイベントを適用（リモート側用）（DoorServiceに委譲）
func apply_door_kick_from_network(door_id: int, character_network_id: int) -> void:
	if door_service:
		door_service.apply_door_kick_from_network(door_id, character_network_id)


# ============================================
# Multiplayer API
# ============================================

## マルチプレイヤーモードを有効化
func enable_multiplayer_mode(local_peer_id: int) -> void:
	_is_multiplayer_mode = true
	_local_peer_id = local_peer_id
	PlayerState.set_local_peer_id(local_peer_id)
	# サービスにモード設定を反映
	if door_service:
		door_service.set_multiplayer_mode(true)
	if character_manager:
		character_manager.set_multiplayer_mode(true, local_peer_id)


## マルチプレイヤーモードを無効化（シングルプレイヤーに戻す）
func disable_multiplayer_mode() -> void:
	_is_multiplayer_mode = false
	_local_peer_id = 0
	PlayerState.clear_multiplayer_session()
	# サービスにモード設定を反映
	if door_service:
		door_service.set_multiplayer_mode(false)
	if character_manager:
		character_manager.set_multiplayer_mode(false, 0)


## マルチプレイヤーモードかどうか
func is_multiplayer_mode() -> bool:
	return _is_multiplayer_mode


## ローカルプレイヤーのpeer_idを取得
func get_local_peer_id() -> int:
	return _local_peer_id


## キャラクターがローカルプレイヤーのものか判定（CharacterManagerServiceに委譲）
func is_local_character(character: Node) -> bool:
	if character_manager:
		return character_manager.is_local_character(character)
	return true  # フォールバック


## キャラクターに対する操作権限があるか判定（CharacterManagerServiceに委譲）
func has_control_permission(character: Node) -> bool:
	if character_manager:
		return character_manager.has_control_permission(character)
	return false  # フォールバック


## ローカルキャラクターのみをフィルタリング（CharacterManagerServiceに委譲）
func filter_local_characters(chars: Array) -> Array[Node]:
	if character_manager:
		return character_manager.filter_local_characters(chars)
	return []


## リモートキャラクターのみをフィルタリング（CharacterManagerServiceに委譲）
func filter_remote_characters(chars: Array) -> Array[Node]:
	if character_manager:
		return character_manager.filter_remote_characters(chars)
	return []


## ローカルプレイヤーの味方キャラクター一覧を取得（CharacterManagerServiceに委譲）
func get_local_friendly_characters() -> Array[Node]:
	if character_manager:
		return character_manager.get_local_friendly_characters()
	return []


## リモートプレイヤーのキャラクター一覧を取得（CharacterManagerServiceに委譲）
func get_remote_characters() -> Array[Node]:
	if character_manager:
		return character_manager.get_remote_characters()
	return []


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


## ネットワークIDからキャラクターを検索（CharacterManagerServiceに委譲）
func find_character_by_network_id(network_id: int) -> GameCharacter:
	if character_manager:
		return character_manager.find_character_by_network_id(network_id)
	return null


## peer_idからキャラクターを検索（複数可）（CharacterManagerServiceに委譲）
func find_characters_by_owner(owner_peer_id: int) -> Array[GameCharacter]:
	if character_manager:
		return character_manager.find_characters_by_owner(owner_peer_id)
	return []


## 全キャラクターの状態をスナップショットとして取得（CharacterManagerServiceに委譲）
func get_all_character_snapshots() -> Array[SyncState.CharacterSnapshot]:
	if character_manager:
		return character_manager.get_all_character_snapshots()
	return []


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


## ダメージシグナル接続（遅延実行用）
func _connect_damage_signal(character: Node) -> void:
	var game_char := character as GameCharacter
	if game_char and game_char.combat_awareness:
		var combat := game_char.combat_awareness
		if not combat.damage_dealt.is_connected(_on_damage_dealt):
			combat.damage_dealt.connect(_on_damage_dealt)


## ダメージが与えられた時のコールバック（マルチプレイヤー同期用）
func _on_damage_dealt(attacker: Node, target: Node, damage: float, is_headshot: bool) -> void:
	var attacker_char := attacker as GameCharacter
	var target_char := target as GameCharacter
	if not attacker_char or not target_char:
		return
	# ネットワークIDを使用してシグナルを発火
	var attacker_id := attacker_char.network_id if attacker_char.network_id != 0 else attacker_char.get_instance_id()
	var target_id := target_char.network_id if target_char.network_id != 0 else target_char.get_instance_id()
	damage_network_event.emit(attacker_id, target_id, damage, is_headshot)
