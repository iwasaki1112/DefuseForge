extends Control
## ロビー画面
## 認証、ルーム作成/参加、マッチメイキングを管理

# =====================================
# ノード参照
# =====================================
@onready var auth_panel: Control = $AuthPanel
@onready var main_panel: Control = $MainPanel
@onready var room_list_panel: Control = $RoomListPanel
@onready var create_room_panel: Control = $CreateRoomPanel
@onready var matchmaking_panel: Control = $MatchmakingPanel

# Auth Panel
@onready var username_input: LineEdit = $AuthPanel/VBoxContainer/UsernameInput
@onready var guest_login_button: Button = $AuthPanel/VBoxContainer/GuestLoginButton
@onready var auth_status_label: Label = $AuthPanel/VBoxContainer/StatusLabel

# Main Panel
@onready var welcome_label: Label = $MainPanel/VBoxContainer/WelcomeLabel
@onready var quick_match_button: Button = $MainPanel/VBoxContainer/QuickMatchButton
@onready var create_room_button: Button = $MainPanel/VBoxContainer/CreateRoomButton
@onready var join_room_button: Button = $MainPanel/VBoxContainer/RoomCodeContainer/JoinRoomButton
@onready var room_code_input: LineEdit = $MainPanel/VBoxContainer/RoomCodeContainer/RoomCodeInput
@onready var browse_rooms_button: Button = $MainPanel/VBoxContainer/BrowseRoomsButton

# Room List Panel
@onready var room_list_container: VBoxContainer = $RoomListPanel/ScrollContainer/RoomListContainer
@onready var room_list_back_button: Button = $RoomListPanel/BackButton
@onready var room_list_refresh_button: Button = $RoomListPanel/RefreshButton

# Create Room Panel
@onready var team_size_option: OptionButton = $CreateRoomPanel/VBoxContainer/TeamSizeOption
@onready var private_room_check: CheckBox = $CreateRoomPanel/VBoxContainer/PrivateRoomCheck
@onready var create_confirm_button: Button = $CreateRoomPanel/VBoxContainer/CreateConfirmButton
@onready var create_back_button: Button = $CreateRoomPanel/VBoxContainer/BackButton
@onready var room_code_label: Label = $CreateRoomPanel/VBoxContainer/RoomCodeLabel

# Matchmaking Panel
@onready var matchmaking_status_label: Label = $MatchmakingPanel/VBoxContainer/StatusLabel
@onready var matchmaking_cancel_button: Button = $MatchmakingPanel/VBoxContainer/CancelButton
@onready var matchmaking_team_size_option: OptionButton = $MatchmakingPanel/VBoxContainer/TeamSizeOption

# =====================================
# 変数
# =====================================
var _matchmaker_ticket: String = ""
var _current_room_code: String = ""
var _created_match_id: String = ""

# =====================================
# 初期化
# =====================================
func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_show_auth_panel()

func _setup_ui() -> void:
	# チームサイズオプション設定
	for option in [team_size_option, matchmaking_team_size_option]:
		if option:
			option.clear()
			option.add_item("1v1", 1)
			option.add_item("2v2", 2)
			option.add_item("3v3", 3)
			option.add_item("5v5", 5)
			option.select(3)  # デフォルト5v5

func _connect_signals() -> void:
	# 認証シグナル
	NakamaClient.authenticated.connect(_on_authenticated)
	NakamaClient.authentication_failed.connect(_on_authentication_failed)
	NakamaClient.socket_connected.connect(_on_socket_connected)
	NakamaClient.socket_disconnected.connect(_on_socket_disconnected)

	# マッチシグナル
	NakamaClient.match_joined.connect(_on_match_joined)
	NakamaClient.matchmaker_matched.connect(_on_matchmaker_matched)

	# UIシグナル
	if guest_login_button:
		guest_login_button.pressed.connect(_on_guest_login_pressed)
	if quick_match_button:
		quick_match_button.pressed.connect(_on_quick_match_pressed)
	if create_room_button:
		create_room_button.pressed.connect(_on_create_room_pressed)
	if join_room_button:
		join_room_button.pressed.connect(_on_join_room_pressed)
	if browse_rooms_button:
		browse_rooms_button.pressed.connect(_on_browse_rooms_pressed)
	if room_list_back_button:
		room_list_back_button.pressed.connect(_on_room_list_back_pressed)
	if room_list_refresh_button:
		room_list_refresh_button.pressed.connect(_on_refresh_rooms_pressed)
	if create_confirm_button:
		create_confirm_button.pressed.connect(_on_create_confirm_pressed)
	if create_back_button:
		create_back_button.pressed.connect(_on_create_back_pressed)
	if matchmaking_cancel_button:
		matchmaking_cancel_button.pressed.connect(_on_matchmaking_cancel_pressed)

# =====================================
# パネル切り替え
# =====================================
func _hide_all_panels() -> void:
	if auth_panel:
		auth_panel.visible = false
	if main_panel:
		main_panel.visible = false
	if room_list_panel:
		room_list_panel.visible = false
	if create_room_panel:
		create_room_panel.visible = false
	if matchmaking_panel:
		matchmaking_panel.visible = false

func _show_auth_panel() -> void:
	_hide_all_panels()
	if auth_panel:
		auth_panel.visible = true

func _show_main_panel() -> void:
	_hide_all_panels()
	if main_panel:
		main_panel.visible = true

func _show_room_list_panel() -> void:
	_hide_all_panels()
	if room_list_panel:
		room_list_panel.visible = true

func _show_create_room_panel() -> void:
	_hide_all_panels()
	if create_room_panel:
		create_room_panel.visible = true
		if room_code_label:
			room_code_label.text = ""

func _show_matchmaking_panel() -> void:
	_hide_all_panels()
	if matchmaking_panel:
		matchmaking_panel.visible = true
		if matchmaking_status_label:
			matchmaking_status_label.text = "マッチング中..."

# =====================================
# 認証
# =====================================
func _on_guest_login_pressed() -> void:
	var username = ""
	if username_input and not username_input.text.strip_edges().is_empty():
		username = username_input.text.strip_edges()

	if auth_status_label:
		auth_status_label.text = "接続中..."

	if guest_login_button:
		guest_login_button.disabled = true

	NakamaClient.authenticate_device("", true, username)

func _on_authenticated(session) -> void:
	print("Authenticated: ", session.username, " (", session.user_id, ")")

	if auth_status_label:
		auth_status_label.text = "認証成功！ソケット接続中..."

	# ソケット接続
	NakamaClient.connect_socket()

func _on_authentication_failed(error: String) -> void:
	push_error("Authentication failed: ", error)

	if auth_status_label:
		auth_status_label.text = "認証失敗: " + error

	if guest_login_button:
		guest_login_button.disabled = false

func _on_socket_connected() -> void:
	print("Socket connected")

	var session = NakamaClient.get_session()
	var display_name = session.username if session else "Player"

	if welcome_label:
		welcome_label.text = "ようこそ、%s さん" % display_name

	_show_main_panel()

func _on_socket_disconnected() -> void:
	print("Socket disconnected")
	_show_auth_panel()

	if auth_status_label:
		auth_status_label.text = "接続が切断されました"

	if guest_login_button:
		guest_login_button.disabled = false

# =====================================
# クイックマッチ
# =====================================
func _on_quick_match_pressed() -> void:
	var team_size = _get_selected_team_size(matchmaking_team_size_option)
	_show_matchmaking_panel()
	NakamaClient.join_matchmaking(team_size)

func _on_matchmaking_cancel_pressed() -> void:
	if not _matchmaker_ticket.is_empty():
		NakamaClient.cancel_matchmaking(_matchmaker_ticket)
		_matchmaker_ticket = ""
	_show_main_panel()

func _on_matchmaker_matched(match_id: String, token: String, users: Array) -> void:
	print("Matched! Match ID: ", match_id)
	_matchmaker_ticket = ""

	if matchmaking_status_label:
		matchmaking_status_label.text = "マッチング成功！参加中..."

	# マッチに参加
	NakamaClient.join_match(match_id)

# =====================================
# ルーム作成
# =====================================
func _on_create_room_pressed() -> void:
	_show_create_room_panel()

func _on_create_confirm_pressed() -> void:
	var team_size = _get_selected_team_size(team_size_option)
	var is_private = private_room_check.button_pressed if private_room_check else false

	if create_confirm_button:
		create_confirm_button.disabled = true

	# RPCでルーム作成（シグナル追加が必要）
	NakamaClient.create_room(team_size, is_private)

	# 仮の処理（後でシグナルベースに変更）
	await get_tree().create_timer(1.0).timeout

	if create_confirm_button:
		create_confirm_button.disabled = false

	# TODO: ルーム作成成功後の処理

func _on_create_back_pressed() -> void:
	_show_main_panel()

# =====================================
# ルーム参加
# =====================================
func _on_join_room_pressed() -> void:
	if not room_code_input:
		return

	var room_code = room_code_input.text.strip_edges().to_upper()
	if room_code.is_empty():
		return

	NakamaClient.join_by_code(room_code)

func _on_browse_rooms_pressed() -> void:
	_show_room_list_panel()
	_refresh_room_list()

func _on_room_list_back_pressed() -> void:
	_show_main_panel()

func _on_refresh_rooms_pressed() -> void:
	_refresh_room_list()

func _refresh_room_list() -> void:
	# ルーム一覧をクリア
	if room_list_container:
		for child in room_list_container.get_children():
			child.queue_free()

	# ルーム一覧取得
	NakamaClient.list_rooms()

	# TODO: シグナルで受け取ってUIを更新

# =====================================
# マッチ参加
# =====================================
func _on_match_joined(match_id: String) -> void:
	print("Joined match: ", match_id)
	# ゲームシーンに遷移
	_transition_to_game(match_id)

func _transition_to_game(match_id: String) -> void:
	# GameManagerに情報を渡してゲームシーンに遷移
	GameManager.current_match_id = match_id
	GameManager.is_online_match = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")

# =====================================
# ユーティリティ
# =====================================
func _get_selected_team_size(option_button: OptionButton) -> int:
	if not option_button:
		return 5
	var selected_id = option_button.get_selected_id()
	return selected_id if selected_id > 0 else 5
