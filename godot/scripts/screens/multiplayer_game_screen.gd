extends Node3D
class_name MultiplayerGameScreen
## マルチプレイヤーゲーム画面
##
## NetworkManagerを使用してリアルタイム同期を行うゲーム画面

## シーン定数
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const GameHUDScene := preload("res://scenes/ui/game_hud.tscn")
const CameraPanControllerScript := preload("res://scripts/utils/camera_pan_controller.gd")
const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"

## シグナル
signal disconnected()

## ノード参照
@onready var camera: Camera3D = $Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var ui_layer: CanvasLayer = $UILayer

## コアシステム
var game_manager: GameManager = null
var environment_setup: EnvironmentSetup = null
var network_manager: NetworkManager = null
var sync_controller: MultiplayerSyncController = null

## UI要素
var _hud: GameHUD = null
var _round_hud: RoundHUD = null
var _status_label: Label = null

## カメラ移動
var _camera_pan_controller: CameraPanController = null
var _input_controller: InputController = null

## 設定
var _map_id: String = "park"
var _is_host: bool = false
var _local_peer_id: int = 0

## キャラクター管理
var _network_id_counter: int = 1


func _ready() -> void:
	add_to_group("game_screen")


## 外部からNetworkManagerを設定してセットアップ
func setup_with_network(net_manager: NetworkManager, map_id: String) -> void:
	network_manager = net_manager
	_map_id = map_id
	_is_host = network_manager.is_host()
	_local_peer_id = network_manager.get_local_peer_id()

	# PlayerStateを設定
	PlayerState.set_local_peer_id(_local_peer_id)

	# プレイヤーのチームを設定
	var players := network_manager.get_players()
	var my_info: Dictionary = players.get(_local_peer_id, {})
	var my_team: int = my_info.get("team", GameCharacter.Team.NONE)
	PlayerState.set_player_team(my_team)

	_setup_environment()
	_setup_game_manager()
	_setup_sync_controller()
	_load_map()
	_setup_hud()
	_setup_round_hud()
	_setup_status_ui()
	_setup_camera_pan()
	_setup_input_controller()
	_spawn_characters()
	_setup_camera_for_team()

	# ネットワークイベント接続
	network_manager.peer_disconnected.connect(_on_peer_disconnected)
	network_manager.message_received.connect(_on_network_message)

	# 視界システム初期化
	game_manager.set_vision_enabled(false)

	# ホストの場合、ラウンド開始
	if _is_host and game_manager.round_manager:
		game_manager.round_manager.start_round()


## ========================================
## 初期化処理
## ========================================

func _setup_environment() -> void:
	environment_setup = EnvironmentSetup.new()
	environment_setup.name = "EnvironmentSetup"
	var preset := load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
	if preset:
		environment_setup.preset = preset
	add_child(environment_setup)


func _setup_game_manager() -> void:
	game_manager = GameManager.new()
	game_manager.name = "GameManager"
	add_child(game_manager)
	game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)

	# シグナル接続
	game_manager.path_confirmed.connect(_on_path_confirmed)
	game_manager.paths_execution_started.connect(_on_paths_execution_started)
	game_manager.all_paths_completed.connect(_on_all_paths_completed)
	game_manager.round_ended.connect(_on_round_ended)
	game_manager.path_ready.connect(_on_path_ready)
	game_manager.path_mode_ended.connect(_on_path_mode_ended)
	game_manager.path_mode_cancelled.connect(_on_path_mode_cancelled)


func _setup_sync_controller() -> void:
	# ネットワークバスをラップするアダプタを作成
	var network_adapter := NetworkBusAdapter.new()
	network_adapter.setup(network_manager)
	add_child(network_adapter)

	sync_controller = MultiplayerSyncController.new()
	sync_controller.name = "SyncController"
	add_child(sync_controller)
	sync_controller.setup(network_adapter, game_manager, _local_peer_id, _is_host)

	# グレネードネットワークイベントを接続
	game_manager.grenade_network_event.connect(_on_grenade_network_event)
	game_manager.grenade_explode_network_event.connect(_on_grenade_explode_network_event)


func _load_map() -> void:
	game_manager.load_map(_map_id, false)


func _setup_hud() -> void:
	_hud = GameHUDScene.instantiate()
	ui_layer.add_child(_hud)
	_hud.setup()
	_hud.execute_all_requested.connect(_on_execute_button_pressed)
	_hud.clear_paths_requested.connect(_on_clear_paths_button_pressed)
	_hud.marker_edit_requested.connect(_on_marker_edit_requested)
	_hud.marker_undo_requested.connect(_on_marker_undo_requested)
	_hud.marker_confirm_requested.connect(_on_marker_confirm_requested)
	_hud.marker_cancel_requested.connect(_on_marker_cancel_requested)


func _setup_round_hud() -> void:
	_round_hud = RoundHUD.new()
	_round_hud.name = GameConstants.NODE_ROUND_HUD
	ui_layer.add_child(_round_hud)

	game_manager.round_timer_updated.connect(_hud.update_timer)
	game_manager.survivor_count_changed.connect(_round_hud.update_survivor_counts)
	game_manager.round_ended.connect(_round_hud.show_result)


func _setup_status_ui() -> void:
	_status_label = Label.new()
	_status_label.name = "NetworkStatus"
	_status_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status_label.position = Vector2(10, 10)
	_status_label.add_theme_font_size_override("font_size", 14)
	ui_layer.add_child(_status_label)
	_update_status()


func _setup_camera_pan() -> void:
	_camera_pan_controller = CameraPanControllerScript.new()
	_camera_pan_controller.setup(camera, 0.05)


func _setup_input_controller() -> void:
	_input_controller = InputController.new()
	_input_controller.name = "InputController"
	add_child(_input_controller)
	_input_controller.setup(game_manager, _camera_pan_controller)


func _spawn_characters() -> void:
	var players := network_manager.get_players()

	# peer_idでソートして確定的な順序でスポーン（ホストとクライアントで同じnetwork_idになるように）
	var sorted_peer_ids: Array[int] = []
	for pid in players.keys():
		sorted_peer_ids.append(pid)
	sorted_peer_ids.sort()

	for peer_id in sorted_peer_ids:
		var info: Dictionary = players[peer_id]
		var team: int = info.get("team", GameCharacter.Team.NONE)

		# チームに基づいてキャラクターをスポーン
		if team == GameCharacter.Team.COUNTER_TERRORIST:
			_spawn_team_characters(peer_id, "dummy_ct", Vector3(-3, 0, -3), team)
		elif team == GameCharacter.Team.TERRORIST:
			_spawn_team_characters(peer_id, "dummy_t", Vector3(3, 0, 3), team)


func _spawn_team_characters(owner_peer_id: int, preset_id: String, base_pos: Vector3, team: int) -> void:
	# 各プレイヤーに2体ずつスポーン
	for i in range(2):
		var offset := Vector3(i * 2.0, 0, 0)
		var character := _create_character(preset_id, base_pos + offset, team)
		if character:
			var network_id := _network_id_counter
			_network_id_counter += 1
			game_manager.register_character_with_network(character, owner_peer_id, network_id)


func _create_character(preset_id: String, pos: Vector3, team: int) -> GameCharacter:
	var character: GameCharacter = CharacterRegistry.create_character(preset_id, pos)
	if character:
		character.team = team
		map_container.add_child(character)
	return character


func _setup_camera_for_team() -> void:
	# プレイヤーのチームに基づいてカメラ位置を調整
	var team := PlayerState.get_player_team()
	if team == GameCharacter.Team.COUNTER_TERRORIST:
		camera.position = Vector3(-5, 20, 20)
	else:
		camera.position = Vector3(5, 20, 20)


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	if game_manager:
		game_manager.process_frame(delta)
	if _camera_pan_controller:
		_camera_pan_controller.process(delta)


func _process(_delta: float) -> void:
	# ステータス更新（30フレームごと）
	if Engine.get_process_frames() % 30 == 0:
		_update_status()


## ========================================
## UI更新
## ========================================

func _update_status() -> void:
	if not _status_label or not network_manager:
		return

	var role := "Host" if _is_host else "Client"
	var player_count := network_manager.get_players().size()
	var team_name := PlayerState.get_team_name()

	_status_label.text = "[%s] Players: %d | Team: %s" % [role, player_count, team_name]


func _update_pending_paths_label() -> void:
	if _hud:
		_hud.set_pending_paths(game_manager.get_pending_path_count())


## ========================================
## ボタンコールバック
## ========================================

func _on_execute_button_pressed() -> void:
	var count := game_manager.execute_all_paths(false)
	if count > 0 and sync_controller:
		sync_controller.send_path_execute(false)


func _on_clear_paths_button_pressed() -> void:
	game_manager.clear_all_pending_paths()


## マーカーエディットボタン押下時のコールバック
func _on_marker_edit_requested(action: String) -> void:
	if not game_manager or not game_manager.path_service:
		return

	var path_service = game_manager.path_service
	if not path_service.has_pending_path():
		return

	match action:
		"vision":
			path_service.start_vision_mode()
		"run":
			path_service.start_run_mode()
		"clear":
			path_service.start_clear_mode()
		"grenade":
			path_service.start_grenade_mode()
		"smoke":
			path_service.start_smoke_grenade_mode()
		"door":
			path_service.start_door_mode()
		"wait":
			path_service.start_wait_mode()


## Undoボタン押下時のコールバック
func _on_marker_undo_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.undo_last_marker()


## Confirmボタン押下時のコールバック
func _on_marker_confirm_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.confirm_path()


## Cancelボタン押下時のコールバック
func _on_marker_cancel_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.cancel_path()


## パス描画完了時のコールバック（マーカー追加モードへ移行）
func _on_path_ready() -> void:
	if _hud:
		_hud.show_marker_edit_panel()


## パスモード終了時のコールバック
func _on_path_mode_ended() -> void:
	if _hud:
		_hud.hide_marker_edit_panel()


## パスモードキャンセル時のコールバック
func _on_path_mode_cancelled() -> void:
	if _hud:
		_hud.hide_marker_edit_panel()


## ========================================
## ネットワークイベント
## ========================================

func _on_peer_disconnected(peer_id: int) -> void:
	print("MultiplayerGameScreen: Peer %d disconnected" % peer_id)
	# 切断されたプレイヤーのキャラクターを処理
	# TODO: ゲーム継続か終了かの判定


func _on_network_message(from_peer: int, msg_type: int, data: Dictionary) -> void:
	# sync_controllerが処理
	pass


## ========================================
## ゲームマネージャーシグナル
## ========================================

func _on_path_confirmed(_count: int) -> void:
	_update_pending_paths_label()
	# パス確定をネットワークに送信
	if sync_controller:
		sync_controller.send_state_sync()


func _on_paths_execution_started(_count: int) -> void:
	pass


func _on_all_paths_completed() -> void:
	_update_pending_paths_label()


func _on_round_ended(winner: int, reason: int) -> void:
	# すべてのキャラクターの移動を停止
	if game_manager:
		game_manager.cancel_all_path_following()

	# ホストがラウンド終了を全クライアントに通知
	if _is_host and sync_controller:
		sync_controller.send_round_state()


func _on_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int) -> void:
	if not sync_controller:
		return

	print("[GRENADE SEND] start=", start_pos, " vel=", velocity, " smoke=", is_smoke, " id=", grenade_id)

	# ネットワークイベントを作成して送信（velocityとIDを送信）
	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.SMOKE_GRENADE_THROW if is_smoke else NetworkConstants.GameEventType.GRENADE_THROW
	event.source_id = 0
	event.target_id = 0
	event.data = {
		"start_x": start_pos.x,
		"start_y": start_pos.y,
		"start_z": start_pos.z,
		"vel_x": velocity.x,
		"vel_y": velocity.y,
		"vel_z": velocity.z,
		"grenade_id": grenade_id,
	}
	sync_controller.send_game_event(event)


func _on_grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool) -> void:
	if not sync_controller:
		return

	print("[GRENADE EXPLODE SEND] id=", grenade_id, " pos=", position, " smoke=", is_smoke)

	# 爆発/展開イベントを送信
	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.SMOKE_DEPLOY if is_smoke else NetworkConstants.GameEventType.GRENADE_EXPLODE
	event.source_id = 0
	event.target_id = 0
	event.data = {
		"grenade_id": grenade_id,
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
	}
	sync_controller.send_game_event(event)


## ========================================
## クリーンアップ
## ========================================

func cleanup() -> void:
	if network_manager:
		network_manager.disconnect_from_game()


## SmokeAreaManagerを取得
func get_smoke_area_manager() -> SmokeAreaManager:
	if game_manager:
		return game_manager.smoke_area_manager
	return null
