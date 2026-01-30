extends Node3D
class_name MultiplayerTestScreen
## マルチプレイヤー同期テストシーン
## 本番環境に近い構成でHost/Client視点切り替えをテスト
##
## 注意: このテストは同一プロセス内でHost/Client切り替えをシミュレート
## 実際のマルチプレイでは別プロセス/別デバイスで動作する

## シーン定数
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const GameHUDScene := preload("res://scenes/ui/game_hud.tscn")
const CameraPanControllerScript := preload("res://scripts/utils/camera_pan_controller.gd")

## ノード参照
@onready var camera: Camera3D = $Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var ui_layer: CanvasLayer = $UILayer

## コアシステム
var environment_setup: EnvironmentSetup = null
var game_manager: GameManager = null
var network_bus: LocalNetworkBus = null
var sync_controller: MultiplayerSyncController = null

## 入力・カメラ
var _camera_pan_controller: CameraPanController = null
var _input_controller: InputController = null
var _hud: GameHUD = null

## 現在のビュー（Host/Client）
enum ViewMode { HOST, CLIENT }
var current_view: ViewMode = ViewMode.HOST

## キャラクター管理
var ct_characters: Array[Node] = []
var t_characters: Array[Node] = []
var _network_id_counter: int = 1

## デバッグUI
var _debug_panel: VBoxContainer
var _status_label: Label
var _log_label: RichTextLabel
var _view_button: Button

## 設定
var _map_id: String = "iwasaki_test"


func _ready() -> void:
	_setup_environment()
	_setup_network_bus()
	_setup_game_manager()
	_load_map()
	_setup_hud()
	_setup_camera_pan()
	_setup_input_controller()
	_spawn_test_characters()
	_setup_debug_ui()

	# 初期状態：HOSTビュー（CT操作）
	_apply_view_state()

	# FoW無効化（デバッグ用）
	game_manager.set_vision_enabled(false)


func _process(delta: float) -> void:
	if game_manager:
		game_manager.process_frame(delta)

	# 全キャラクター可視化を維持
	_force_all_characters_visible()

	# ステータス更新
	if Engine.get_process_frames() % 30 == 0:
		_update_status_display()


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


func _setup_network_bus() -> void:
	network_bus = LocalNetworkBus.new()
	network_bus.name = "NetworkBus"
	add_child(network_bus)
	network_bus.setup_local_session()
	network_bus.message_received.connect(_on_network_message)


func _setup_game_manager() -> void:
	game_manager = GameManager.new()
	game_manager.name = "GameManager"
	add_child(game_manager)
	game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)

	# 同期コントローラー（Hostとして動作）
	sync_controller = MultiplayerSyncController.new()
	sync_controller.name = "SyncController"
	add_child(sync_controller)
	sync_controller.setup(network_bus, game_manager, LocalNetworkBus.HOST_PEER_ID, true)


func _load_map() -> void:
	game_manager.load_map(_map_id, false)


func _setup_hud() -> void:
	_hud = GameHUDScene.instantiate()
	ui_layer.add_child(_hud)
	_hud.setup()
	_hud.execute_all_requested.connect(_on_execute_button_pressed)
	_hud.clear_paths_requested.connect(_on_clear_paths_button_pressed)
	_hud.sync_go_requested.connect(_on_sync_go_button_pressed)


func _setup_camera_pan() -> void:
	_camera_pan_controller = CameraPanControllerScript.new()
	_camera_pan_controller.setup(camera, 0.05)


func _setup_input_controller() -> void:
	_input_controller = InputController.new()
	_input_controller.name = "InputController"
	add_child(_input_controller)
	_input_controller.setup(game_manager, _camera_pan_controller)


func _spawn_test_characters() -> void:
	# CT x2（Host側）
	var ct1 := _create_character("dummy_ct", Vector3(-3, 0, -3), GameCharacter.Team.COUNTER_TERRORIST)
	var ct2 := _create_character("dummy_ct", Vector3(-5, 0, -3), GameCharacter.Team.COUNTER_TERRORIST)
	_register_character(ct1, LocalNetworkBus.HOST_PEER_ID)
	_register_character(ct2, LocalNetworkBus.HOST_PEER_ID)
	ct_characters.append(ct1)
	ct_characters.append(ct2)

	# T x2（Client側）
	var t1 := _create_character("dummy_t", Vector3(3, 0, 3), GameCharacter.Team.TERRORIST)
	var t2 := _create_character("dummy_t", Vector3(5, 0, 3), GameCharacter.Team.TERRORIST)
	_register_character(t1, LocalNetworkBus.CLIENT_PEER_ID)
	_register_character(t2, LocalNetworkBus.CLIENT_PEER_ID)
	t_characters.append(t1)
	t_characters.append(t2)

	_force_all_characters_visible()


func _create_character(preset_id: String, pos: Vector3, team: GameCharacter.Team) -> GameCharacter:
	var character: GameCharacter = CharacterRegistry.create_character(preset_id, pos)
	if character:
		character.team = team
		map_container.add_child(character)
	return character


func _register_character(character: GameCharacter, owner_peer_id: int) -> void:
	var network_id := _network_id_counter
	_network_id_counter += 1
	game_manager.register_character_with_network(character, owner_peer_id, network_id)


func _setup_debug_ui() -> void:
	# デバッグパネル（左上）
	_debug_panel = VBoxContainer.new()
	_debug_panel.name = "DebugPanel"
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_panel.position = Vector2(10, 10)
	_debug_panel.custom_minimum_size = Vector2(210, 0)
	ui_layer.add_child(_debug_panel)

	# ステータスラベル
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.add_theme_font_size_override("font_size", 14)
	_debug_panel.add_child(_status_label)

	# ビュー切り替えボタン
	_view_button = Button.new()
	_view_button.text = "HOST/CT (TAB)"
	_view_button.pressed.connect(_toggle_view)
	_debug_panel.add_child(_view_button)

	# 手動同期ボタン
	var sync_btn := Button.new()
	sync_btn.text = "Send Sync (S)"
	sync_btn.pressed.connect(_manual_sync)
	_debug_panel.add_child(sync_btn)

	# ログパネル
	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(200, 150)
	_debug_panel.add_child(log_panel)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.custom_minimum_size = Vector2(190, 140)
	log_panel.add_child(_log_label)

	_update_status_display()


## ========================================
## ビュー切り替え
## ========================================

func _toggle_view() -> void:
	if current_view == ViewMode.HOST:
		current_view = ViewMode.CLIENT
	else:
		current_view = ViewMode.HOST

	_apply_view_state()
	_log_message("[color=yellow]Switched to %s[/color]" % ("HOST/CT" if current_view == ViewMode.HOST else "CLIENT/T"))


func _apply_view_state() -> void:
	if current_view == ViewMode.HOST:
		_view_button.text = "HOST/CT (TAB)"
		PlayerState.set_local_peer_id(LocalNetworkBus.HOST_PEER_ID)
		PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	else:
		_view_button.text = "CLIENT/T (TAB)"
		PlayerState.set_local_peer_id(LocalNetworkBus.CLIENT_PEER_ID)
		PlayerState.set_player_team(GameCharacter.Team.TERRORIST)

	# 選択解除
	game_manager.selection_manager.deselect_all()
	_update_status_display()


## ========================================
## アクション
## ========================================

func _on_execute_button_pressed() -> void:
	var count := game_manager.execute_all_paths(false)
	if count > 0:
		_log_message("[color=green]Executed %d paths[/color]" % count)
		# 同期メッセージ送信
		sync_controller.send_path_execute(false)


func _on_clear_paths_button_pressed() -> void:
	game_manager.clear_all_pending_paths()
	_log_message("[color=orange]Paths cleared[/color]")


func _on_sync_go_button_pressed() -> void:
	game_manager.release_all_sync_waiting_characters()
	if _hud:
		_hud.hide_sync_go_button()
	_log_message("[color=cyan]Sync waiting characters released[/color]")


func _manual_sync() -> void:
	sync_controller.send_state_sync()
	_log_message("[color=cyan]Sync sent[/color]")


## ========================================
## 入力処理
## ========================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_toggle_view()
			KEY_S:
				_manual_sync()


## ========================================
## ユーティリティ
## ========================================

func _force_all_characters_visible() -> void:
	for character in ct_characters:
		if is_instance_valid(character):
			character.visible = true
	for character in t_characters:
		if is_instance_valid(character):
			character.visible = true


func _update_status_display() -> void:
	var view_name := "HOST (CT)" if current_view == ViewMode.HOST else "CLIENT (T)"
	var my_chars := ct_characters if current_view == ViewMode.HOST else t_characters

	var status := "=== %s ===\n" % view_name
	status += "操作可能: %d体\n" % my_chars.size()
	status += "選択中: %d\n" % game_manager.selection_manager.get_selection_count()
	status += "確定パス: %d\n" % game_manager.path_execution_manager.get_pending_path_count()

	_status_label.text = status


func _log_message(msg: String) -> void:
	if _log_label:
		var time_str := "%.1f" % (Time.get_ticks_msec() / 1000.0)
		_log_label.text += "[%s] %s\n" % [time_str, msg]


## ========================================
## シグナルハンドラ
## ========================================

func _on_network_message(_from: int, _to: int, msg_type: int, _data: Dictionary) -> void:
	var type_name := network_bus.get_message_type_name(msg_type)
	_log_message("[color=white]MSG: %s[/color]" % type_name)
