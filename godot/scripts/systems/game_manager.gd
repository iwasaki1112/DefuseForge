extends Node
class_name GameManager
## コアゲームシステム管理
## システムの初期化・更新・UI管理を一元管理

## システム生成ファクトリ
var _factory: GameSystemFactory = null

## グレネード投擲シグナル
signal grenade_thrown(grenade: Node3D, character: Node)
## スモークグレネード投擲シグナル
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)
## ネットワークイベント（MultiplayerModeProviderが直接接続）
signal grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int)
signal grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool)
signal door_kick_network_event(door_id: int, character_network_id: int)
signal door_open_network_event(door_id: int, character_network_id: int)
signal damage_network_event(attacker_id: int, target_id: int, damage: float, is_headshot: bool)

## コアシステム
var selection_manager: CharacterSelectionManager = null
var idle_manager: IdleCharacterManager = null
var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null
var smoke_area_manager: SmokeAreaManager = null
var map_manager: MapManager = null
var character_setup_service: CharacterSetupService = null
var vision_service: VisionService = null
var round_manager: RoundManager = null

## 抽出されたサービス
var character_manager: CharacterManagerService = null
var grenade_service: GrenadeService = null
var door_service: DoorService = null

## UIコンポーネント（GameScreenから注入される）
var label_manager: CharacterLabelManager = null

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
var default_vision_fov: float = 75.0
var default_vision_range: float = 7.0
var default_weapon_id_ct: String = "glock"
var default_weapon_id_t: String = "glock"
var is_vision_enabled: bool = false


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
	_setup_idle_manager()
	_setup_vision_service()
	# VisionService初期化後にFoWシステムをGrenadeServiceに渡す（リモートグレネードのFoW可視性用）
	if grenade_service and fog_of_war_system:
		grenade_service.set_fow_system(fog_of_war_system)
	# DoorServiceにもFoWシステムを渡す（敵チームのドア可視性制御用）
	if door_service and fog_of_war_system:
		door_service.set_fow_system(fog_of_war_system)
	_setup_map_manager()
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

	# ラベル削除・色解放
	if label_manager:
		label_manager.remove_label(character)
	CharacterColorManager.release_color(character)

	# 選択解除
	if selection_manager:
		selection_manager.remove_from_selection(character)


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

	# アイドルキャラクターを処理
	if idle_manager:
		idle_manager.process_idle_characters(delta)

	# リモートキャラクターの補間更新
	_update_remote_character_interpolation(delta)


## ========================================
## 状態取得API
## ========================================

## プライマリキャラクターを取得
func get_primary_character() -> Node:
	return selection_manager.primary_character if selection_manager else null


## 選択中キャラクター数を取得
func get_selection_count() -> int:
	return selection_manager.get_selection_count() if selection_manager else 0


## ========================================
## UI管理
## ========================================

## UIコンポーネントを設定（GameScreenから呼び出し）
func set_label_manager(mgr: CharacterLabelManager) -> void:
	label_manager = mgr


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
		selection_manager = _factory.create_selection_manager()
		add_child(selection_manager)
		selection_manager.selection_changed.connect(_on_selection_changed)
		selection_manager.primary_changed.connect(_on_primary_changed)


func _setup_idle_manager() -> void:
	if idle_manager == null:
		idle_manager = _factory.create_idle_manager(
			characters,
			func(): return selection_manager.primary_character if selection_manager else null
		)
		add_child(idle_manager)


func _setup_smoke_area_manager() -> void:
	if smoke_area_manager == null:
		smoke_area_manager = _factory.create_smoke_area_manager()
		add_child(smoke_area_manager)


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
			default_weapon_id_ct,
			default_weapon_id_t,
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
		# スモークシェーダーのGPUコンパイルを事前実行（初回投擲ラグ回避）
		grenade_service.warmup_smoke_shader()


func _setup_door_service() -> void:
	if door_service == null:
		door_service = _factory.create_door_service(character_manager, _force_update_all_vision)
		add_child(door_service)
		# シグナル転送
		door_service.door_kick_network_event.connect(func(d, c): door_kick_network_event.emit(d, c))
		door_service.door_open_network_event.connect(func(d, c): door_open_network_event.emit(d, c))
		# ドア開放アニメーション中のFoWオクルーダーリアルタイム更新
		door_service.door_opening_started.connect(func(door):
			if vision_service:
				vision_service.start_door_opening(door)
		)
		door_service.door_opening_finished.connect(func(door):
			if vision_service:
				vision_service.finish_door_opening(door)
		)


## ========================================
## 内部：シグナルハンドラ
## ========================================

func _on_selection_changed(_selected: Array[Node], _primary: Node) -> void:
	pass


func _on_primary_changed(_character: Node) -> void:
	pass


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
	# 選択解除
	if selection_manager:
		selection_manager.remove_from_selection(character)


## ========================================
## ドアキック処理
## ========================================

## ドアキックインパクト時（DoorServiceに委譲）
func _on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void:
	if door_service:
		door_service.on_door_kick_done(door, character)


## ドア開けインパクト時（DoorServiceに委譲）
func _on_door_open_done(door: Node3D, character: CharacterBody3D) -> void:
	if door_service:
		door_service.on_door_open_done(door, character)


## ========================================
## グレネード関連（GrenadeServiceに委譲）
## ========================================

## グレネードを生成して投擲（内部ヘルパー）
func _spawn_and_throw_grenade(start_pos: Vector3, target_pos: Vector3, _bounce_point: Vector3, thrower: Node3D = null) -> Array:
	if grenade_service:
		return grenade_service.spawn_and_throw_grenade(start_pos, target_pos, thrower)
	return [null, Vector3.ZERO, 0]


## スモークグレネードを生成して投擲（内部ヘルパー）
func _spawn_and_throw_smoke_grenade(start_pos: Vector3, target_pos: Vector3, _bounce_point: Vector3, thrower: Node3D = null) -> Array:
	if grenade_service:
		return grenade_service.spawn_and_throw_smoke_grenade(start_pos, target_pos, thrower)
	return [null, Vector3.ZERO, 0]


func _emit_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int = 0) -> void:
	if grenade_service:
		grenade_service.emit_grenade_network_event(start_pos, velocity, is_smoke, grenade_id)


## ネットワークからグレネードをスポーン（リモート用）- 速度を直接使用
func spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0, thrower_team: int = 0) -> void:
	if grenade_service:
		grenade_service.spawn_grenade_from_network(start_pos, velocity, grenade_id, thrower_team)


## ネットワークからスモークグレネードをスポーン（リモート用）- 速度を直接使用
func spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0, thrower_team: int = 0) -> void:
	if grenade_service:
		grenade_service.spawn_smoke_grenade_from_network(start_pos, velocity, grenade_id, thrower_team)


## ネットワークからの爆発イベントを処理（リモートグレネード用）
func handle_grenade_explode_from_network(grenade_id: int, position: Vector3, is_smoke: bool) -> void:
	if grenade_service:
		grenade_service.handle_grenade_explode_from_network(grenade_id, position, is_smoke)


## ========================================
## ドアID管理（マルチプレイヤー同期用）
## ========================================

## ドアを登録し、一意のIDを割り当て（DoorServiceに委譲）
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
	# FoWマップサイズのフォールバック値を更新
	if map_manager and map_manager.current_preset:
		fow_map_size = map_manager.current_preset.map_size

	# ドアを登録
	register_all_doors_in_map()


## マップアンロード前
func _on_map_will_unload(_map_id: String) -> void:
	# ドア登録をクリア
	clear_door_registry()


## ネットワークからのドアキックイベントを適用（リモート側用）（DoorServiceに委譲）
func apply_door_kick_from_network(door_id: int, character_network_id: int) -> void:
	if door_service:
		door_service.apply_door_kick_from_network(door_id, character_network_id)


## ネットワークからのドア開けイベントを適用（リモート側用）（DoorServiceに委譲）
func apply_door_open_from_network(door_id: int, character_network_id: int) -> void:
	if door_service:
		door_service.apply_door_open_from_network(door_id, character_network_id)


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
