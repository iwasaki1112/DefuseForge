extends Control
class_name LobbyScreen
## ロビー画面
## WebSocketリレーサーバー経由のルーム作成・参加・プレイヤー一覧・準備状態を管理

const GAME_SCENE := "res://scenes/screens/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"


## 状態
enum LobbyState {
	MENU,           # 初期メニュー
	ROOM_NAME_INPUT, # ルーム名入力（ホスト用）
	ROOM_LIST,      # ルーム一覧（参加用）
	CONNECTING,     # 接続中
	IN_LOBBY,       # ロビー内
}

var _state: LobbyState = LobbyState.MENU
var _network_manager: NetworkManager = null

## カウントダウン
var _countdown_active: bool = false
var _countdown_time: float = 5.0
var _countdown_label: Label = null

## UI参照
var _menu_panel: VBoxContainer
var _host_button: Button
var _join_button: Button
var _back_button: Button

var _room_name_panel: VBoxContainer
var _room_name_input: LineEdit
var _create_button: Button
var _room_name_cancel_button: Button

var _room_list_panel: VBoxContainer
var _room_list_container: VBoxContainer
var _refresh_button: Button
var _room_list_back_button: Button
var _room_list_status: Label

var _lobby_panel: VBoxContainer
var _info_label: Label
var _player_list: VBoxContainer
var _ready_button: Button
var _leave_button: Button

var _status_label: Label


func _ready() -> void:
	_setup_ui()
	_setup_network_manager()
	_show_menu()


func _process(delta: float) -> void:
	if not _countdown_active:
		return

	# ホストのみカウントダウンを進める（クライアントは同期メッセージで更新）
	if _network_manager.is_host():
		_countdown_time -= delta

		if _countdown_time <= 0:
			_countdown_active = false
			# ゲーム開始を全員に通知
			_network_manager.broadcast_message(
				NetworkConstants.MessageType.ROUND_STATE,
				{"action": "start_game", "map_id": "home"}
			)
			_start_game("home")
		else:
			# カウントダウン表示更新
			var seconds := ceili(_countdown_time)
			_countdown_label.text = "ゲーム開始まで %d 秒" % seconds
			_countdown_label.visible = true
			# クライアントにカウントダウン同期
			_network_manager.broadcast_message(
				NetworkConstants.MessageType.ROUND_STATE,
				{"action": "countdown_sync", "time": seconds}
			)


func _setup_network_manager() -> void:
	_network_manager = NetworkManager.new()
	_network_manager.name = "NetworkManager"
	add_child(_network_manager)

	_network_manager.connection_state_changed.connect(_on_connection_state_changed)
	_network_manager.peer_connected.connect(_on_peer_connected)
	_network_manager.peer_disconnected.connect(_on_peer_disconnected)
	_network_manager.connection_failed.connect(_on_connection_failed)
	_network_manager.all_peers_ready.connect(_on_all_peers_ready)
	_network_manager.message_received.connect(_on_network_message)
	_network_manager.players_updated.connect(_on_players_updated)
	_network_manager.room_list_received.connect(_on_room_list_received)
	_network_manager.room_created.connect(_on_room_created)
	_network_manager.room_joined.connect(_on_room_joined)


func _setup_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 中央配置用コンテナ
	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)

	# メインコンテナ
	var main_container := VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(400, 500)
	main_container.add_theme_constant_override("separation", 20)
	center_container.add_child(main_container)

	# タイトル
	var title := Label.new()
	title.text = "Multiplayer Lobby"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)

	# ステータスラベル
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	main_container.add_child(_status_label)

	# カウントダウンラベル
	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 28)
	_countdown_label.add_theme_color_override("font_color", Color.YELLOW)
	_countdown_label.visible = false
	main_container.add_child(_countdown_label)

	# メニューパネル
	_menu_panel = _create_menu_panel()
	main_container.add_child(_menu_panel)

	# ルーム名入力パネル
	_room_name_panel = _create_room_name_panel()
	main_container.add_child(_room_name_panel)

	# ルームリストパネル
	_room_list_panel = _create_room_list_panel()
	main_container.add_child(_room_list_panel)

	# ロビーパネル
	_lobby_panel = _create_lobby_panel()
	main_container.add_child(_lobby_panel)


func _create_menu_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 15)

	_host_button = Button.new()
	_host_button.text = "ホストとして開始"
	_host_button.custom_minimum_size = Vector2(300, 50)
	_host_button.pressed.connect(_on_host_pressed)
	panel.add_child(_host_button)

	_join_button = Button.new()
	_join_button.text = "ゲームに参加"
	_join_button.custom_minimum_size = Vector2(300, 50)
	_join_button.pressed.connect(_on_join_pressed)
	panel.add_child(_join_button)

	_back_button = Button.new()
	_back_button.text = "戻る"
	_back_button.custom_minimum_size = Vector2(300, 50)
	_back_button.pressed.connect(_on_back_pressed)
	panel.add_child(_back_button)

	return panel


func _create_room_name_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 15)

	var label := Label.new()
	label.text = "ルーム名を入力:"
	panel.add_child(label)

	_room_name_input = LineEdit.new()
	_room_name_input.placeholder_text = "My Room"
	_room_name_input.custom_minimum_size = Vector2(300, 40)
	panel.add_child(_room_name_input)

	var btn_container := HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 10)
	panel.add_child(btn_container)

	_create_button = Button.new()
	_create_button.text = "作成"
	_create_button.custom_minimum_size = Vector2(145, 50)
	_create_button.pressed.connect(_on_create_room_pressed)
	btn_container.add_child(_create_button)

	_room_name_cancel_button = Button.new()
	_room_name_cancel_button.text = "キャンセル"
	_room_name_cancel_button.custom_minimum_size = Vector2(145, 50)
	_room_name_cancel_button.pressed.connect(_on_room_name_cancel_pressed)
	btn_container.add_child(_room_name_cancel_button)

	return panel


func _create_room_list_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 15)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	panel.add_child(header)

	var header_label := Label.new()
	header_label.text = "ルーム一覧"
	header_label.add_theme_font_size_override("font_size", 20)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_label)

	_refresh_button = Button.new()
	_refresh_button.text = "更新"
	_refresh_button.custom_minimum_size = Vector2(80, 35)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	header.add_child(_refresh_button)

	# スクロールコンテナ
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 200)
	panel.add_child(scroll)

	_room_list_container = VBoxContainer.new()
	_room_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_list_container.add_theme_constant_override("separation", 5)
	scroll.add_child(_room_list_container)

	_room_list_status = Label.new()
	_room_list_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_list_status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	panel.add_child(_room_list_status)

	_room_list_back_button = Button.new()
	_room_list_back_button.text = "戻る"
	_room_list_back_button.custom_minimum_size = Vector2(300, 50)
	_room_list_back_button.pressed.connect(_on_room_list_back_pressed)
	panel.add_child(_room_list_back_button)

	return panel


func _create_lobby_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 15)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(_info_label)

	var player_label := Label.new()
	player_label.text = "プレイヤー:"
	panel.add_child(player_label)

	_player_list = VBoxContainer.new()
	_player_list.custom_minimum_size = Vector2(300, 150)
	panel.add_child(_player_list)

	_ready_button = Button.new()
	_ready_button.text = "準備完了"
	_ready_button.custom_minimum_size = Vector2(300, 50)
	_ready_button.pressed.connect(_on_ready_pressed)
	panel.add_child(_ready_button)

	_leave_button = Button.new()
	_leave_button.text = "退出"
	_leave_button.custom_minimum_size = Vector2(300, 50)
	_leave_button.pressed.connect(_on_leave_pressed)
	panel.add_child(_leave_button)

	return panel


## ========================================
## 状態切り替え
## ========================================

func _show_menu() -> void:
	_state = LobbyState.MENU
	_menu_panel.visible = true
	_room_name_panel.visible = false
	_room_list_panel.visible = false
	_lobby_panel.visible = false
	_status_label.text = ""


func _show_room_name_input() -> void:
	_state = LobbyState.ROOM_NAME_INPUT
	_menu_panel.visible = false
	_room_name_panel.visible = true
	_room_list_panel.visible = false
	_lobby_panel.visible = false
	_status_label.text = ""
	_room_name_input.text = ""
	_room_name_input.grab_focus()


func _show_room_list() -> void:
	_state = LobbyState.ROOM_LIST
	_menu_panel.visible = false
	_room_name_panel.visible = false
	_room_list_panel.visible = true
	_lobby_panel.visible = false
	_status_label.text = ""
	_room_list_status.text = "読み込み中..."
	_refresh_room_list()


func _show_connecting() -> void:
	_state = LobbyState.CONNECTING
	_menu_panel.visible = false
	_room_name_panel.visible = false
	_room_list_panel.visible = false
	_lobby_panel.visible = false
	_status_label.text = "接続中..."


func _show_lobby() -> void:
	_state = LobbyState.IN_LOBBY
	_menu_panel.visible = false
	_room_name_panel.visible = false
	_room_list_panel.visible = false
	_lobby_panel.visible = true

	_ready_button.visible = true

	if _network_manager.is_host():
		var room_id := _network_manager.get_room_id()
		var room_name := _network_manager.get_room_name()
		_info_label.text = "ホスト中\nルーム: %s\nID: %s" % [room_name, room_id]
		# ホストのチームをPlayerStateに設定
		PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	else:
		var room_id := _network_manager.get_room_id()
		_info_label.text = "参加中\nルームID: %s" % room_id

	_status_label.text = ""
	_countdown_label.visible = false
	_countdown_active = false
	_update_player_list()


## ========================================
## UI更新
## ========================================

func _update_player_list() -> void:
	# クリア
	for child in _player_list.get_children():
		child.queue_free()

	# プレイヤー追加
	var players := _network_manager.get_players()
	for peer_id in players:
		var info: Dictionary = players[peer_id]
		var label := Label.new()
		var ready_mark := "✓" if info["ready"] else "○"
		var host_mark := " (Host)" if peer_id == 1 else ""
		var you_mark := " ← You" if peer_id == _network_manager.get_local_peer_id() else ""
		var team_mark := _get_team_name(info.get("team", GameCharacter.Team.NONE))
		label.text = "%s [%s] %s%s%s" % [ready_mark, team_mark, info["name"], host_mark, you_mark]
		_player_list.add_child(label)


func _get_team_name(team: int) -> String:
	match team:
		GameCharacter.Team.COUNTER_TERRORIST:
			return "CT"
		GameCharacter.Team.TERRORIST:
			return "T"
		_:
			return "--"


func _refresh_room_list() -> void:
	_room_list_status.text = "読み込み中..."
	_network_manager.request_room_list()


func _update_room_list(rooms: Array) -> void:
	# クリア
	for child in _room_list_container.get_children():
		child.queue_free()

	if rooms.is_empty():
		_room_list_status.text = "利用可能なルームがありません"
		return

	_room_list_status.text = "%d 件のルーム" % rooms.size()

	for room in rooms:
		var room_item := _create_room_item(room)
		_room_list_container.add_child(room_item)


func _create_room_item(room: Dictionary) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)

	var info_label := Label.new()
	var room_name: String = room.get("name", "Unknown")
	var player_count: int = room.get("player_count", 0)
	var max_players: int = room.get("max_players", 4)
	info_label.text = "%s (%d/%d)" % [room_name, player_count, max_players]
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(info_label)

	var join_btn := Button.new()
	join_btn.text = "参加"
	join_btn.custom_minimum_size = Vector2(70, 35)
	join_btn.disabled = player_count >= max_players
	var room_id: String = room.get("id", "")
	join_btn.pressed.connect(_on_room_join_pressed.bind(room_id))
	container.add_child(join_btn)

	return container


## ========================================
## ボタンハンドラ
## ========================================

func _on_host_pressed() -> void:
	_show_room_name_input()


func _on_join_pressed() -> void:
	_show_room_list()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_create_room_pressed() -> void:
	var room_name := _room_name_input.text.strip_edges()
	if room_name.is_empty():
		room_name = "Room"

	var player_name := SettingsManager.get_player_name()
	if player_name.is_empty():
		player_name = "Host"

	_show_connecting()
	if not _network_manager.create_room(room_name, player_name):
		_show_room_name_input()


func _on_room_name_cancel_pressed() -> void:
	_show_menu()


func _on_refresh_pressed() -> void:
	_refresh_room_list()


func _on_room_list_back_pressed() -> void:
	_network_manager.disconnect_from_game()
	_show_menu()


func _on_room_join_pressed(room_id: String) -> void:
	var player_name := SettingsManager.get_player_name()
	if player_name.is_empty():
		player_name = "Player"

	_show_connecting()
	if not _network_manager.join_room(room_id, player_name):
		_show_room_list()


func _on_ready_pressed() -> void:
	var players := _network_manager.get_players()
	var local_id := _network_manager.get_local_peer_id()
	var is_ready: bool = players.get(local_id, {}).get("ready", false)

	_network_manager.set_ready(not is_ready)
	_ready_button.text = "準備解除" if not is_ready else "準備完了"
	_update_player_list()


func _on_leave_pressed() -> void:
	_network_manager.disconnect_from_game()
	_show_menu()


## ========================================
## ネットワークイベントハンドラ
## ========================================

func _on_connection_state_changed(state: NetworkManager.ConnectionState) -> void:
	match state:
		NetworkManager.ConnectionState.CONNECTED:
			_show_lobby()
		NetworkManager.ConnectionState.HOST:
			_show_lobby()
		NetworkManager.ConnectionState.DISCONNECTED:
			if _state != LobbyState.MENU and _state != LobbyState.ROOM_LIST:
				_status_label.text = "切断されました"
				_show_menu()


func _on_peer_connected(_peer_id: int) -> void:
	_update_player_list()


func _on_peer_disconnected(_peer_id: int) -> void:
	_update_player_list()


func _on_connection_failed(reason: String) -> void:
	_status_label.text = reason
	if _state == LobbyState.CONNECTING:
		_show_menu()


func _on_all_peers_ready() -> void:
	_status_label.text = "全員準備完了！"
	# ホストがカウントダウン開始
	if _network_manager.is_host():
		_start_countdown()
		# クライアントにもカウントダウン開始を通知
		_network_manager.broadcast_message(
			NetworkConstants.MessageType.ROUND_STATE,
			{"action": "countdown_start"}
		)


func _on_players_updated() -> void:
	if _state == LobbyState.IN_LOBBY:
		_update_player_list()
		# 自分のチームをPlayerStateに反映
		var players := _network_manager.get_players()
		var local_id := _network_manager.get_local_peer_id()
		var my_team: int = players.get(local_id, {}).get("team", GameCharacter.Team.NONE)
		if my_team != GameCharacter.Team.NONE:
			PlayerState.set_player_team(my_team)


func _on_room_list_received(rooms: Array) -> void:
	if _state == LobbyState.ROOM_LIST:
		_update_room_list(rooms)


func _on_room_created(_room_id: String) -> void:
	_show_lobby()


func _on_room_joined(_room_id: String) -> void:
	_show_lobby()


func _on_network_message(_from_peer: int, msg_type: int, data: Dictionary) -> void:
	if msg_type == NetworkConstants.MessageType.ROUND_STATE:
		var action: String = data.get("action", "")
		match action:
			"start_game":
				var map_id: String = data.get("map_id", "home")
				_start_game(map_id)
			"countdown_start":
				_start_countdown()
			"countdown_sync":
				# クライアント側のカウントダウン表示を同期
				var seconds: int = data.get("time", 5)
				_countdown_label.text = "ゲーム開始まで %d 秒" % seconds
				_countdown_label.visible = true
			"countdown_cancel":
				_cancel_countdown()


## ========================================
## 外部API
## ========================================

## NetworkManagerを取得
func get_network_manager() -> NetworkManager:
	return _network_manager


## カウントダウン開始
func _start_countdown() -> void:
	_countdown_active = true
	_countdown_time = 5.0
	_countdown_label.text = "ゲーム開始まで 5 秒"
	_countdown_label.visible = true
	_ready_button.disabled = true


## カウントダウンキャンセル
func _cancel_countdown() -> void:
	_countdown_active = false
	_countdown_label.visible = false
	_ready_button.disabled = false
	_status_label.text = "準備待ち..."


## ゲームを開始（シーン遷移）
func _start_game(map_id: String) -> void:
	# NetworkManagerを親から切り離して保持
	remove_child(_network_manager)

	# ゲームシーンをロード（統合されたGameScreenを使用）
	var game_scene := load(GAME_SCENE).instantiate() as GameScreen

	# Multiplayerモードをadd_child前にセットアップ（_ready()で正しいProviderで初期化するため）
	game_scene.setup_multiplayer(_network_manager, map_id)

	get_tree().root.add_child(game_scene)
	game_scene.add_child(_network_manager)

	# このシーンを削除
	queue_free()
