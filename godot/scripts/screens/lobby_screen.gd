extends Control
class_name LobbyScreen
## ロビー画面
## ルーム作成・参加・プレイヤー一覧・準備状態を管理

const MULTIPLAYER_GAME_SCENE := "res://scenes/screens/multiplayer_game.tscn"
const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"

## シグナル
signal game_started()
signal back_requested()

## 状態
enum LobbyState {
	MENU,       # 初期メニュー
	HOSTING,    # ホスト中
	JOINING,    # 参加中（入力）
	CONNECTING, # 接続中
	IN_LOBBY,   # ロビー内
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

var _join_panel: VBoxContainer
var _ip_input: LineEdit
var _connect_button: Button
var _cancel_button: Button

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
				{"action": "start_game", "map_id": "park"}
			)
			_start_game("park")
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


func _setup_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# メインコンテナ
	var main_container := VBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_CENTER)
	main_container.custom_minimum_size = Vector2(400, 500)
	main_container.add_theme_constant_override("separation", 20)
	add_child(main_container)

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

	# 参加パネル
	_join_panel = _create_join_panel()
	main_container.add_child(_join_panel)

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


func _create_join_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 15)

	var ip_label := Label.new()
	ip_label.text = "ホストのIPアドレス:"
	panel.add_child(ip_label)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "192.168.x.x"
	_ip_input.custom_minimum_size = Vector2(300, 40)
	panel.add_child(_ip_input)

	var btn_container := HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 10)
	panel.add_child(btn_container)

	_connect_button = Button.new()
	_connect_button.text = "接続"
	_connect_button.custom_minimum_size = Vector2(145, 50)
	_connect_button.pressed.connect(_on_connect_pressed)
	btn_container.add_child(_connect_button)

	_cancel_button = Button.new()
	_cancel_button.text = "キャンセル"
	_cancel_button.custom_minimum_size = Vector2(145, 50)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	btn_container.add_child(_cancel_button)

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
	_join_panel.visible = false
	_lobby_panel.visible = false
	_status_label.text = ""


func _show_join_input() -> void:
	_state = LobbyState.JOINING
	_menu_panel.visible = false
	_join_panel.visible = true
	_lobby_panel.visible = false
	_status_label.text = "ホストのIPアドレスを入力"
	_ip_input.text = ""
	_ip_input.grab_focus()


func _show_connecting() -> void:
	_state = LobbyState.CONNECTING
	_menu_panel.visible = false
	_join_panel.visible = false
	_lobby_panel.visible = false
	_status_label.text = "接続中..."


func _show_lobby() -> void:
	_state = LobbyState.IN_LOBBY
	_menu_panel.visible = false
	_join_panel.visible = false
	_lobby_panel.visible = true

	_ready_button.visible = true

	if _network_manager.is_host():
		var ip := _network_manager.get_local_ip()
		var port := _network_manager.get_port()
		_info_label.text = "ホスト中\nIP: %s\nPort: %d" % [ip, port]
		# ホストのチームをPlayerStateに設定
		PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)
	else:
		_info_label.text = "接続済み"

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


## ========================================
## ボタンハンドラ
## ========================================

func _on_host_pressed() -> void:
	var player_name := SettingsManager.get_player_name()
	if player_name.is_empty():
		player_name = "Host"

	if _network_manager.host_game(NetworkManager.DEFAULT_PORT, player_name):
		_show_lobby()


func _on_join_pressed() -> void:
	_show_join_input()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_connect_pressed() -> void:
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		_status_label.text = "IPアドレスを入力してください"
		return

	var player_name := SettingsManager.get_player_name()
	if player_name.is_empty():
		player_name = "Client"

	_show_connecting()
	if not _network_manager.join_game(ip, NetworkManager.DEFAULT_PORT, player_name):
		_show_join_input()


func _on_cancel_pressed() -> void:
	_show_menu()


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
		NetworkManager.ConnectionState.DISCONNECTED:
			if _state != LobbyState.MENU:
				_status_label.text = "切断されました"
				_show_menu()


func _on_peer_connected(_peer_id: int) -> void:
	_update_player_list()


func _on_peer_disconnected(_peer_id: int) -> void:
	_update_player_list()


func _on_connection_failed(reason: String) -> void:
	_status_label.text = reason
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


func _on_network_message(_from_peer: int, msg_type: int, data: Dictionary) -> void:
	if msg_type == NetworkConstants.MessageType.ROUND_STATE:
		var action: String = data.get("action", "")
		match action:
			"start_game":
				var map_id: String = data.get("map_id", "park")
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

	# ゲームシーンをロード
	var game_scene := load(MULTIPLAYER_GAME_SCENE).instantiate() as MultiplayerGameScreen
	get_tree().root.add_child(game_scene)

	# NetworkManagerをゲームシーンにセットアップ
	game_scene.add_child(_network_manager)
	game_scene.setup_with_network(_network_manager, map_id)

	# このシーンを削除
	queue_free()
