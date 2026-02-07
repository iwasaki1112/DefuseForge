extends Node3D
class_name GameScreen
## ゲーム画面（TPS版）
##
## TPS直接操作モード。プレイヤー1体をWASD/ジョイスティックで操作し、
## FoW+自動攻撃で敵と戦う。
## GameModeProviderでモード固有の処理を分離。

## シーン定数
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"

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

## TPS制御
var _tps_controller: TPSPlayerController = null
var _player_character: GameCharacter = null

## TPS HUD要素
var _weapon_option: OptionButton = null
var _weapon_list: Array = []
var _timer_label: Label = null
var _money_label: Label = null
var _debug_vision_btn: Button = null

## UI要素
var _round_hud: RoundHUD = null

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
## 注意: add_child()前に呼ぶこと（_ready()で_initialize_game()を一度だけ実行するため）
func setup_multiplayer(net_manager: NetworkManager, map_id: String) -> void:
	_map_id = map_id

	# MultiplayerModeProviderをセットアップ
	var mp_provider := MultiplayerModeProvider.new()
	mp_provider.setup_network(net_manager)
	_mode_provider = mp_provider


## ゲームの初期化（共通処理）
func _initialize_game() -> void:
	_setup_environment()
	_setup_game_manager()

	# Providerを初期化（ネットワーク接続などを行う）
	_mode_provider.initialize(self, game_manager)

	# TPS: プレイヤーは常にCT（スポーンがCT固定のため）
	PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	_load_map()
	_spawn_characters()
	_setup_tps_hud()
	_setup_round_hud()
	_setup_money()
	_setup_tps_controller()

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

		# UIコンポーネントをGameScreenが作成してGameManagerに注入
		_setup_label_manager()
		_setup_path_context_menu()

		game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)

		# シグナル接続（TPS用: タイマーとラウンド終了のみ）
		SignalBus.round_timer_updated.connect(_on_round_timer_updated)
		SignalBus.round_ended.connect(_on_round_ended)


func _load_map() -> void:
	if _map_id.is_empty():
		push_warning("[GameScreen] No map selected - will be set later for multiplayer")
		return

	var map_instance := game_manager.load_map(_map_id, false)
	if not map_instance:
		push_error("[GameScreen] Failed to load map: %s" % _map_id)


func _spawn_characters() -> void:
	# モードプロバイダーがキャラクタースポーンを処理する場合はスキップ
	if _mode_provider.spawn_characters(self, game_manager):
		return

	# デフォルトのスポーン処理
	if not game_manager.has_map():
		push_warning("[GameScreen] Cannot spawn characters - no map loaded yet")
		return

	var preset = game_manager.get_current_map_preset()
	if not preset:
		push_error("[GameScreen] Cannot spawn characters - no map preset")
		return

	# CT: 1体のみ（alpha）— TPS操作対象
	var alpha_preset = CharacterRegistry.get_preset("alpha")
	var ct_spawns = preset.spawn_points_ct
	var ct_rotations = preset.spawn_rotations_ct
	if alpha_preset and ct_spawns.size() > 0:
		var character = CharacterRegistry.create_character(alpha_preset.id, ct_spawns[0])
		if character:
			character.team = GameCharacter.Team.COUNTER_TERRORIST
			character.marker_name = "alpha"
			if ct_rotations.size() > 0:
				var dir = Vector3(sin(ct_rotations[0]), 0, cos(ct_rotations[0]))
				character._facing_direction = dir
			game_manager.get_character_parent().add_child(character)
			_mode_provider.register_character(game_manager, character, _network_id_counter)
			_network_id_counter += 1
			_player_character = character

	# T: 全敵スポーン（ares preset）
	var ares_preset = CharacterRegistry.get_preset("ares")
	var t_spawns = preset.spawn_points_t
	var t_rotations = preset.spawn_rotations_t
	if ares_preset:
		for i in range(t_spawns.size()):
			var enemy = CharacterRegistry.create_character(ares_preset.id, t_spawns[i])
			if enemy:
				enemy.team = GameCharacter.Team.TERRORIST
				if i < t_rotations.size():
					var dir = Vector3(sin(t_rotations[i]), 0, cos(t_rotations[i]))
					enemy._facing_direction = dir
				game_manager.get_character_parent().add_child(enemy)
				_mode_provider.register_character(game_manager, enemy, _network_id_counter)
				_network_id_counter += 1

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)


func _setup_tps_controller() -> void:
	if not _player_character:
		push_error("[GameScreen] Cannot setup TPS controller - no player character")
		return
	_tps_controller = TPSPlayerController.new()
	_tps_controller.name = "TPSPlayerController"
	add_child(_tps_controller)
	_tps_controller.setup(_player_character, camera, ui_layer)


func _setup_tps_hud() -> void:
	# 武器セレクター（左上）
	var hbox := HBoxContainer.new()
	hbox.name = "WeaponSelector"
	hbox.position = Vector2(10, 10)
	ui_layer.add_child(hbox)

	var label := Label.new()
	label.text = "Weapon: "
	hbox.add_child(label)

	_weapon_option = OptionButton.new()
	_weapon_option.custom_minimum_size.x = 160
	hbox.add_child(_weapon_option)

	_weapon_list = WeaponRegistry.get_all()
	var default_idx := 0
	for i in range(_weapon_list.size()):
		var w: WeaponPreset = _weapon_list[i]
		_weapon_option.add_item(w.display_name, i)
		if w.id == "glock":
			default_idx = i
	_weapon_option.selected = default_idx
	_weapon_option.item_selected.connect(_on_weapon_selected)

	# タイマー（右上）
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timer_label.position = Vector2(-120, 10)
	_timer_label.add_theme_font_size_override("font_size", 24)
	_timer_label.text = "2:00"
	ui_layer.add_child(_timer_label)

	# マネー（タイマーの下）
	_money_label = Label.new()
	_money_label.name = "MoneyLabel"
	_money_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_money_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_money_label.position = Vector2(-120, 45)
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.text = "$0"
	ui_layer.add_child(_money_label)

	# アクションボタン（右中央）
	_create_action_buttons()


func _create_action_buttons() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "ActionButtons"
	vbox.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vbox.position = Vector2(-170, -80)
	vbox.add_theme_constant_override("separation", 12)
	ui_layer.add_child(vbox)

	var btn_grenade := Button.new()
	btn_grenade.text = "Grenade"
	btn_grenade.custom_minimum_size = Vector2(150, 50)
	btn_grenade.pressed.connect(_on_grenade_pressed)
	vbox.add_child(btn_grenade)

	var btn_door_kick := Button.new()
	btn_door_kick.text = "Door Kick"
	btn_door_kick.custom_minimum_size = Vector2(150, 50)
	btn_door_kick.pressed.connect(_on_door_kick_pressed)
	vbox.add_child(btn_door_kick)

	var btn_door_open := Button.new()
	btn_door_open.text = "Door Open"
	btn_door_open.custom_minimum_size = Vector2(150, 50)
	btn_door_open.pressed.connect(_on_door_open_pressed)
	vbox.add_child(btn_door_open)

	_debug_vision_btn = Button.new()
	_debug_vision_btn.text = "Debug Vision"
	_debug_vision_btn.toggle_mode = true
	_debug_vision_btn.custom_minimum_size = Vector2(150, 50)
	_debug_vision_btn.toggled.connect(_on_debug_vision_toggled)
	vbox.add_child(_debug_vision_btn)


func _setup_round_hud() -> void:
	if _round_hud == null:
		_round_hud = RoundHUD.new()
		_round_hud.name = GameConstants.NODE_ROUND_HUD
		ui_layer.add_child(_round_hud)

		SignalBus.survivor_count_changed.connect(_round_hud.update_survivor_counts)
		SignalBus.round_ended.connect(_round_hud.show_result)


func _setup_label_manager() -> void:
	var lm := CharacterLabelManager.new()
	lm.name = GameConstants.NODE_LABEL_MANAGER
	game_manager.add_child(lm)
	game_manager.set_label_manager(lm)


func _setup_path_context_menu() -> void:
	var menu := PathContextMenu.new()
	menu.name = "PathContextMenu"
	if ui_layer:
		ui_layer.add_child(menu)
	else:
		game_manager.add_child(menu)
	game_manager.set_path_context_menu(menu)


func _setup_money() -> void:
	PlayerState.reset_money()
	if not PlayerState.money_changed.is_connected(_on_money_changed):
		PlayerState.money_changed.connect(_on_money_changed)
	_update_money_display()


## ========================================
## UI更新
## ========================================

func _update_money_display() -> void:
	if _money_label:
		_money_label.text = "$%d" % PlayerState.get_money()


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	if game_manager:
		game_manager.process_frame(delta)
	if _tps_controller:
		_tps_controller.process(delta)


func _input(event: InputEvent) -> void:
	if _tps_controller:
		_tps_controller.handle_input(event)


## ========================================
## TPS HUDコールバック
## ========================================

func _on_weapon_selected(idx: int) -> void:
	if not _player_character or idx < 0 or idx >= _weapon_list.size():
		return
	var weapon: WeaponPreset = _weapon_list[idx]
	_player_character.equip_weapon(weapon)


func _on_grenade_pressed() -> void:
	if _player_character and _player_character.anim_ctrl:
		_player_character.anim_ctrl.play_throw()


func _on_door_kick_pressed() -> void:
	if _player_character and _player_character.anim_ctrl:
		_player_character.anim_ctrl.play_door_kick()


func _on_door_open_pressed() -> void:
	if _player_character and _player_character.anim_ctrl:
		_player_character.anim_ctrl.play_door_open()


func _on_debug_vision_toggled(enabled: bool) -> void:
	if game_manager and game_manager.vision_service:
		game_manager.vision_service.set_debug_draw(enabled)


## ========================================
## シグナルハンドラ
## ========================================

func _on_money_changed(_new_amount: int) -> void:
	_update_money_display()


func _on_round_timer_updated(time: float) -> void:
	if _timer_label:
		var minutes := int(time) / 60
		var seconds := int(time) % 60
		_timer_label.text = "%d:%02d" % [minutes, seconds]


func _on_round_ended(winner: int, reason: int) -> void:
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
		game_manager.unload_map(true)
		if Debug.enabled: print("[GameScreen] Map and characters cleaned up")

	# SignalBusのシグナル切断
	if SignalBus.round_timer_updated.is_connected(_on_round_timer_updated):
		SignalBus.round_timer_updated.disconnect(_on_round_timer_updated)
	if SignalBus.round_ended.is_connected(_on_round_ended):
		SignalBus.round_ended.disconnect(_on_round_ended)
	if _round_hud:
		if SignalBus.survivor_count_changed.is_connected(_round_hud.update_survivor_counts):
			SignalBus.survivor_count_changed.disconnect(_round_hud.update_survivor_counts)
		if SignalBus.round_ended.is_connected(_round_hud.show_result):
			SignalBus.round_ended.disconnect(_round_hud.show_result)

	# PlayerStateのシグナル切断
	if PlayerState.money_changed.is_connected(_on_money_changed):
		PlayerState.money_changed.disconnect(_on_money_changed)

	# HUDを明示的に削除
	if _round_hud and is_instance_valid(_round_hud):
		_round_hud.queue_free()
		_round_hud = null

	# Providerのクリーンアップ（WebSocket切断含む）
	if _mode_provider:
		_mode_provider.cleanup()
		if Debug.enabled: print("[GameScreen] Network cleanup completed")


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
			if Debug.enabled: print("[DEBUG] Vision debug draw: %s" % ("ON" if _vision_debug_enabled else "OFF"))
