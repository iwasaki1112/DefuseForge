extends Node3D
class_name GameScreen
## ゲーム画面
##
## TrainingモードとMultiplayerモードを統合。
## GameModeProviderでモード固有の処理を分離。

## シーン定数
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const GameHUDScene := preload("res://scenes/ui/game_hud.tscn")
const CameraPanControllerScript := preload("res://scripts/utils/camera_pan_controller.gd")

## ノード参照
@onready var camera: Camera3D = $Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var team_display_label: Label = $UILayer/TeamDisplayLabel

## コアシステム
var game_manager: GameManager = null
var environment_setup: EnvironmentSetup = null

## モードプロバイダー
var _mode_provider: GameModeProvider = null

## UI要素
var _hud: GameHUD = null
var _round_hud: RoundHUD = null
var _status_label: Label = null

## カメラ移動
var _camera_pan_controller: CameraPanController = null
var _input_controller: InputController = null

## 設定
var _map_id: String = ""

## キャラクター管理
var _network_id_counter: int = 1

## デバッグ
var _vision_debug_enabled: bool = false


func _ready() -> void:
	add_to_group("game_screen")

	# Multiplayerモードでない場合、Trainingモードとして初期化
	if _mode_provider == null:
		_mode_provider = TrainingModeProvider.new()
		_map_id = SettingsManager.get_selected_map()
		_initialize_game()


## Multiplayerモードでセットアップ（LobbyScreenから呼ばれる）
func setup_multiplayer(net_manager: NetworkManager, map_id: String) -> void:
	_map_id = map_id

	# MultiplayerModeProviderをセットアップ
	var mp_provider := MultiplayerModeProvider.new()
	mp_provider.setup_network(net_manager)
	_mode_provider = mp_provider

	_initialize_game()


## ゲームの初期化（共通処理）
func _initialize_game() -> void:
	_setup_environment()
	_setup_game_manager()

	# Providerを初期化（ネットワーク接続などを行う）
	_mode_provider.initialize(self, game_manager)

	_mode_provider.determine_player_team()
	_load_map()
	_spawn_characters()
	_setup_hud()
	_setup_round_hud()
	_register_character_markers()
	_setup_status_ui()
	_update_team_display()
	_setup_money()
	_setup_camera_pan()
	_setup_input_controller()
	_setup_camera_for_player()

	# 視界システムを初期化（FoW ON）
	game_manager.set_vision_enabled(true)

	# ラウンド開始
	if _mode_provider.can_start_round() and game_manager.round_manager:
		game_manager.round_manager.start_round()


## ========================================
## 初期化処理
## ========================================

func _setup_environment() -> void:
	if environment_setup == null:
		environment_setup = EnvironmentSetup.new()
		environment_setup.name = "EnvironmentSetup"
		var preset := load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
		if preset:
			environment_setup.preset = preset
		add_child(environment_setup)


func _setup_game_manager() -> void:
	if game_manager == null:
		game_manager = GameManager.new()
		game_manager.name = "GameManager"
		add_child(game_manager)
		game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)

		# シグナル接続
		game_manager.selection_changed.connect(_on_selection_changed)
		game_manager.path_confirmed.connect(_on_path_confirmed)
		game_manager.paths_execution_started.connect(_on_paths_execution_started)
		game_manager.all_paths_completed.connect(_on_all_paths_completed)
		game_manager.paths_cleared.connect(_on_paths_cleared)
		game_manager.path_ready.connect(_on_path_ready)
		game_manager.path_mode_ended.connect(_on_path_mode_ended)
		game_manager.path_mode_cancelled.connect(_on_path_mode_cancelled)
		game_manager.round_timer_updated.connect(_on_round_timer_updated)
		game_manager.round_ended.connect(_on_round_ended)
		# 同期待機状態変更シグナル（PCビルドでの型解決問題を回避するため動的アクセス）
		var pem = game_manager.get("path_execution_manager")
		if pem:
			pem.sync_wait_state_changed.connect(_on_sync_wait_state_changed)


func _load_map() -> void:
	if _map_id.is_empty():
		push_warning("[GameScreen] No map selected - will be set later for multiplayer")
		return

	var map_instance := game_manager.load_map(_map_id, false)
	if not map_instance:
		push_error("[GameScreen] Failed to load map: %s" % _map_id)


func _spawn_characters() -> void:
	if not game_manager.has_map():
		push_warning("[GameScreen] Cannot spawn characters - no map loaded yet")
		return

	var preset = game_manager.get_current_map_preset()
	if not preset:
		push_error("[GameScreen] Cannot spawn characters - no map preset")
		return

	# CT側キャラクターをスポーン（alpha, bravo）
	var alpha_preset = CharacterRegistry.get_preset("alpha")
	var ct_spawns = preset.spawn_points_ct
	var ct_rotations = preset.spawn_rotations_ct
	var ct_marker_names := ["alpha", "bravo"]
	if alpha_preset:
		_spawn_team_characters([alpha_preset, alpha_preset], ct_spawns, ct_rotations, ct_marker_names, GameCharacter.Team.COUNTER_TERRORIST)

	# T側キャラクターをスポーン（ares, brim）
	var ares_preset = CharacterRegistry.get_preset("ares")
	var t_spawns = preset.spawn_points_t
	var t_rotations = preset.spawn_rotations_t
	var t_marker_names := ["ares", "brim"]
	if ares_preset:
		_spawn_team_characters([ares_preset, ares_preset], t_spawns, t_rotations, t_marker_names, GameCharacter.Team.TERRORIST)

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)


func _spawn_team_characters(presets: Array, spawn_points: Array, spawn_rotations: Array, marker_names: Array, team: int) -> void:
	var count := mini(presets.size(), spawn_points.size())
	for i in range(count):
		var char_preset = presets[i]
		var spawn_pos: Vector3 = spawn_points[i]
		var character = CharacterRegistry.create_character(char_preset.id, spawn_pos)
		if character:
			character.team = team
			# マーカー名を設定
			if i < marker_names.size():
				character.marker_name = marker_names[i]
			# add_child()前に向きを設定
			if i < spawn_rotations.size():
				var spawn_rot: float = spawn_rotations[i]
				var direction := Vector3(sin(spawn_rot), 0, cos(spawn_rot))
				character._facing_direction = direction
			var character_parent = game_manager.get_character_parent()
			character_parent.add_child(character)

			# モードプロバイダー経由でキャラクター登録
			var network_id := _network_id_counter
			_network_id_counter += 1
			_mode_provider.register_character(game_manager, character, network_id)


func _setup_hud() -> void:
	if _hud == null:
		_hud = GameHUDScene.instantiate()
		ui_layer.add_child(_hud)
		_hud.setup()
		_hud.execute_all_requested.connect(_on_execute_button_pressed)
		_hud.clear_paths_requested.connect(_on_clear_paths_button_pressed)
		_hud.character_marker_pressed.connect(_on_character_marker_pressed)
		_hud.point_edit_requested.connect(_on_point_edit_requested)
		_hud.point_undo_requested.connect(_on_point_undo_requested)
		_hud.point_cancel_requested.connect(_on_point_cancel_requested)
		_hud.sync_go_requested.connect(_on_sync_go_button_pressed)


func _setup_round_hud() -> void:
	if _round_hud == null:
		_round_hud = RoundHUD.new()
		_round_hud.name = GameConstants.NODE_ROUND_HUD
		ui_layer.add_child(_round_hud)

		game_manager.survivor_count_changed.connect(_round_hud.update_survivor_counts)
		game_manager.round_ended.connect(_round_hud.show_result)


func _setup_status_ui() -> void:
	# Multiplayerモードのみステータス表示
	if _mode_provider.get_mode_name() != "multiplayer":
		return

	_status_label = Label.new()
	_status_label.name = "NetworkStatus"
	_status_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status_label.position = Vector2(10, 10)
	_status_label.add_theme_font_size_override("font_size", 14)
	ui_layer.add_child(_status_label)
	_update_status()


func _setup_camera_pan() -> void:
	if _camera_pan_controller == null:
		_camera_pan_controller = CameraPanControllerScript.new()
		_camera_pan_controller.setup(camera, 0.05)


func _setup_input_controller() -> void:
	if _input_controller == null:
		_input_controller = InputController.new()
		_input_controller.name = "InputController"
		add_child(_input_controller)
		_input_controller.setup(game_manager, _camera_pan_controller)


func _setup_money() -> void:
	PlayerState.reset_money()
	if not PlayerState.money_changed.is_connected(_on_money_changed):
		PlayerState.money_changed.connect(_on_money_changed)
	_update_money_display()


func _register_character_markers() -> void:
	if not _hud or not game_manager:
		return

	var player_team: GameCharacter.Team = PlayerState.get_player_team()
	for character in game_manager.characters:
		if not is_instance_valid(character):
			continue
		if character.team == player_team and not character.marker_name.is_empty():
			_hud.register_character_marker(character)


func _setup_camera_for_player() -> void:
	if not camera:
		return

	var player_team := PlayerState.get_player_team()
	var player_character: Node3D = null

	for character in game_manager.characters:
		if character is GameCharacter and character.team == player_team:
			player_character = character
			break

	if player_character:
		var target_pos := player_character.global_position
		var camera_offset := Vector3(0, 15, 5.5)
		camera.global_position = Vector3(target_pos.x, camera_offset.y, target_pos.z + camera_offset.z)


## ========================================
## UI更新
## ========================================

func _update_team_display() -> void:
	if team_display_label:
		var team_name := PlayerState.get_team_name()
		var full_name := "Counter-Terrorist" if team_name == "CT" else "Terrorist"
		team_display_label.text = "You are: %s (%s)" % [full_name, team_name]


func _update_money_display() -> void:
	if _hud:
		_hud.update_money(PlayerState.get_money())


func _update_pending_paths_label() -> void:
	if _hud:
		_hud.set_pending_paths(game_manager.get_pending_path_count())


func _update_status() -> void:
	if not _status_label:
		return

	if _mode_provider is MultiplayerModeProvider:
		var mp := _mode_provider as MultiplayerModeProvider
		var role := "Host" if mp.is_host() else "Client"
		var player_count := mp.get_player_count()
		var team_name := PlayerState.get_team_name()
		_status_label.text = "[%s] Players: %d | Team: %s" % [role, player_count, team_name]


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	if game_manager:
		game_manager.process_frame(delta)
	if _camera_pan_controller:
		_camera_pan_controller.process(delta)


func _process(_delta: float) -> void:
	# Multiplayerモードのステータス更新（30フレームごと）
	if _status_label and Engine.get_process_frames() % 30 == 0:
		_update_status()


## ========================================
## ボタンコールバック
## ========================================

func _on_execute_button_pressed() -> void:
	# パスモード中でパスがあればモードを終了する
	if game_manager.is_path_mode() and game_manager.path_service and game_manager.path_service.has_path():
		game_manager.path_service.confirm_path()

	var count := game_manager.execute_all_paths(false)
	_mode_provider.on_execute_paths(count)


func _on_clear_paths_button_pressed() -> void:
	game_manager.clear_all_pending_paths()


func _on_sync_go_button_pressed() -> void:
	game_manager.release_all_sync_waiting_characters()
	# ボタンを非表示にする
	if _hud:
		_hud.hide_sync_go_button()


func _on_sync_wait_state_changed(has_waiting: bool) -> void:
	if _hud:
		_hud.update_sync_go_button_visibility(has_waiting)


func _on_point_edit_requested(action: String) -> void:
	if not game_manager or not game_manager.path_service:
		return

	var path_service = game_manager.path_service
	if not path_service.has_path():
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


func _on_point_undo_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.undo_last_point()


func _on_point_cancel_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.cancel_path()


func _on_path_ready() -> void:
	if _hud:
		_hud.show_point_edit_panel()


func _on_path_mode_ended() -> void:
	if _hud:
		_hud.hide_point_edit_panel()


func _on_path_mode_cancelled() -> void:
	if _hud:
		_hud.hide_point_edit_panel()


func _on_character_marker_pressed(character: Node) -> void:
	if not is_instance_valid(character) or not camera:
		return

	# キャラクターを選択状態にする
	if game_manager and game_manager.selection_manager:
		game_manager.selection_manager.add_to_selection(character)

	# カメラをキャラクター位置に移動
	var target_pos: Vector3 = character.global_position
	_pan_camera_to_position(target_pos)

	# パス描画モードを開始
	if game_manager:
		game_manager.start_move_mode()


func _pan_camera_to_position(target_pos: Vector3) -> void:
	if not camera:
		return

	var new_camera_pos := Vector3(target_pos.x, camera.global_position.y, target_pos.z + 5.0)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(camera, "global_position", new_camera_pos, 0.4)


## ========================================
## シグナルハンドラ
## ========================================

func _on_selection_changed(_selected: Array[Node], _primary: Node) -> void:
	pass


func _on_path_confirmed(_count: int) -> void:
	_update_pending_paths_label()
	_mode_provider.on_path_confirmed()


func _on_paths_execution_started(_count: int) -> void:
	pass


func _on_all_paths_completed() -> void:
	_update_pending_paths_label()


func _on_paths_cleared() -> void:
	_update_pending_paths_label()


func _on_money_changed(_new_amount: int) -> void:
	_update_money_display()


func _on_round_timer_updated(time: float) -> void:
	if _hud:
		_hud.update_timer(time)


func _on_round_ended(winner: int, reason: int) -> void:
	if game_manager:
		game_manager.cancel_all_path_following()

	_mode_provider.on_round_ended(winner, reason)

	# 3秒後に遷移
	await get_tree().create_timer(3.0).timeout

	# クリーンアップ
	_cleanup_before_transition()

	# モードによって遷移先を変える
	if _mode_provider.get_mode_name() == "multiplayer":
		get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/screens/map_selection.tscn")


## ========================================
## 外部API
## ========================================

func get_smoke_area_manager() -> SmokeAreaManager:
	if game_manager:
		return game_manager.smoke_area_manager
	return null


func get_vision_service() -> VisionService:
	if game_manager:
		return game_manager.vision_service
	return null


func cleanup() -> void:
	_cleanup_before_transition()


var _cleanup_done: bool = false

func _cleanup_before_transition() -> void:
	if _cleanup_done:
		return
	_cleanup_done = true

	# マップとキャラクターのクリーンアップ
	if game_manager:
		game_manager.unload_map(true)  # キャラクターも含めてクリーンアップ
		print("[GameScreen] Map and characters cleaned up")

	# PlayerStateのシグナル切断
	if PlayerState.money_changed.is_connected(_on_money_changed):
		PlayerState.money_changed.disconnect(_on_money_changed)

	# HUDを明示的に削除
	if _hud and is_instance_valid(_hud):
		_hud.queue_free()
		_hud = null

	if _round_hud and is_instance_valid(_round_hud):
		_round_hud.queue_free()
		_round_hud = null

	if _status_label and is_instance_valid(_status_label):
		_status_label.queue_free()
		_status_label = null

	# Providerのクリーンアップ（WebSocket切断含む）
	if _mode_provider:
		_mode_provider.cleanup()
		print("[GameScreen] Network cleanup completed")


func _exit_tree() -> void:
	_cleanup_before_transition()


## ========================================
## デバッグ入力
## ========================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_vision_debug_enabled = not _vision_debug_enabled
			game_manager.set_vision_debug_draw(_vision_debug_enabled)
			print("[DEBUG] Vision debug draw: %s" % ("ON" if _vision_debug_enabled else "OFF"))
