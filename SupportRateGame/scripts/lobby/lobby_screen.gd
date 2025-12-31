extends Control
## ロビー画面（シンプル版）
## 認証、公開ルーム作成/参加のみ（1v1固定）

# =====================================
# ノード参照
# =====================================
@onready var auth_panel: Control = $AuthPanel
@onready var main_panel: Control = $MainPanel
@onready var room_list_panel: Control = $RoomListPanel
@onready var waiting_panel: Control = $WaitingPanel

# Auth Panel
@onready var username_input: LineEdit = $AuthPanel/VBoxContainer/UsernameInput
@onready var guest_login_button: Button = $AuthPanel/VBoxContainer/GuestLoginButton
@onready var auth_status_label: Label = $AuthPanel/VBoxContainer/StatusLabel

# Main Panel
@onready var welcome_label: Label = $MainPanel/VBoxContainer/WelcomeLabel
@onready var create_room_button: Button = $MainPanel/VBoxContainer/CreateRoomButton
@onready var browse_rooms_button: Button = $MainPanel/VBoxContainer/BrowseRoomsButton

# Room List Panel
@onready var room_list_container: VBoxContainer = $RoomListPanel/ScrollContainer/RoomListContainer
@onready var room_list_back_button: Button = $RoomListPanel/BackButton
@onready var room_list_refresh_button: Button = $RoomListPanel/RefreshButton

# Waiting Panel
@onready var waiting_status_label: Label = $WaitingPanel/VBoxContainer/StatusLabel
@onready var waiting_cancel_button: Button = $WaitingPanel/VBoxContainer/CancelButton

# =====================================
# 定数
# =====================================
const TEAM_SIZE: int = 1  # 1v1固定

# =====================================
# 変数
# =====================================
var _created_match_id: String = ""

# =====================================
# 初期化
# =====================================
func _ready() -> void:
	_connect_signals()
	_show_auth_panel()

func _connect_signals() -> void:
	# 認証シグナル
	NakamaClient.authenticated.connect(_on_authenticated)
	NakamaClient.authentication_failed.connect(_on_authentication_failed)
	NakamaClient.socket_connected.connect(_on_socket_connected)
	NakamaClient.socket_disconnected.connect(_on_socket_disconnected)

	# マッチシグナル
	NakamaClient.match_joined.connect(_on_match_joined)
	NakamaClient.room_created.connect(_on_room_created)
	NakamaClient.rooms_listed.connect(_on_rooms_listed)
	NakamaClient.match_presence_joined.connect(_on_match_presence_joined)

	# UIシグナル
	if guest_login_button:
		guest_login_button.pressed.connect(_on_guest_login_pressed)
	if create_room_button:
		create_room_button.pressed.connect(_on_create_room_pressed)
	if browse_rooms_button:
		browse_rooms_button.pressed.connect(_on_browse_rooms_pressed)
	if room_list_back_button:
		room_list_back_button.pressed.connect(_on_room_list_back_pressed)
	if room_list_refresh_button:
		room_list_refresh_button.pressed.connect(_on_refresh_rooms_pressed)
	if waiting_cancel_button:
		waiting_cancel_button.pressed.connect(_on_waiting_cancel_pressed)

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
	if waiting_panel:
		waiting_panel.visible = false

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

func _show_waiting_panel() -> void:
	_hide_all_panels()
	if waiting_panel:
		waiting_panel.visible = true
		if waiting_status_label:
			waiting_status_label.text = "対戦相手を待っています..."

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

func _on_authenticated(_session) -> void:
	if auth_status_label:
		auth_status_label.text = "認証成功！"

	NakamaClient.connect_socket()

func _on_authentication_failed(error: String) -> void:
	if auth_status_label:
		auth_status_label.text = "認証失敗: " + error

	if guest_login_button:
		guest_login_button.disabled = false

func _on_socket_connected() -> void:
	var session = NakamaClient.get_session()
	var display_name = session.username if session else "Player"

	if welcome_label:
		welcome_label.text = "ようこそ、%s さん" % display_name

	_show_main_panel()

func _on_socket_disconnected() -> void:
	_show_auth_panel()

	if auth_status_label:
		auth_status_label.text = "接続が切断されました"

	if guest_login_button:
		guest_login_button.disabled = false

# =====================================
# ルーム作成
# =====================================
func _on_create_room_pressed() -> void:
	if create_room_button:
		create_room_button.disabled = true

	# 公開ルーム作成（1v1固定）
	NakamaClient.create_room(TEAM_SIZE, false)

func _on_room_created(match_id: String, _room_code: String) -> void:
	print("Room created: %s" % match_id)
	_created_match_id = match_id
	GameManager.is_host = true

	if create_room_button:
		create_room_button.disabled = false

	# マッチに参加
	NakamaClient.join_match(match_id)

# =====================================
# ルーム検索・参加
# =====================================
func _on_browse_rooms_pressed() -> void:
	_show_room_list_panel()
	_refresh_room_list()

func _on_room_list_back_pressed() -> void:
	_show_main_panel()

func _on_refresh_rooms_pressed() -> void:
	_refresh_room_list()

func _refresh_room_list() -> void:
	if room_list_container:
		for child in room_list_container.get_children():
			child.queue_free()

	NakamaClient.list_rooms(TEAM_SIZE)

func _on_rooms_listed(rooms: Array) -> void:
	if not room_list_container:
		return

	for child in room_list_container.get_children():
		child.queue_free()

	if rooms.is_empty():
		var label = Label.new()
		label.text = "部屋がありません"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		room_list_container.add_child(label)
		return

	for room in rooms:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(400, 50)
		var player_count = room.get("player_count", 0)
		var match_id = room.get("match_id", "")
		btn.text = "1v1 - %d/2 プレイヤー" % player_count
		btn.pressed.connect(_on_room_button_pressed.bind(match_id))
		room_list_container.add_child(btn)

func _on_room_button_pressed(match_id: String) -> void:
	NakamaClient.join_match(match_id)

# =====================================
# 待機
# =====================================
func _on_waiting_cancel_pressed() -> void:
	# マッチから離脱
	NakamaClient.leave_match()
	GameManager.is_host = false
	_show_main_panel()

# =====================================
# マッチ参加
# =====================================
func _on_match_joined(match_id: String) -> void:
	GameManager.current_match_id = match_id

	# ホストの場合は待機画面
	if GameManager.is_host:
		_show_waiting_panel()
		return

	# 参加者はゲームへ
	_transition_to_game(match_id)

func _on_match_presence_joined(presences: Array) -> void:
	# ホストの場合、他のプレイヤーが参加したらゲームに遷移
	if not GameManager.is_host:
		return

	if presences.size() == 0:
		return

	var my_session_id = NakamaClient.get_session_id()
	var my_user_id = NakamaClient.get_user_id()

	for presence in presences:
		var session_id = presence.get("session_id", "")
		var user_id = presence.get("user_id", "")

		# 自分自身のプレゼンスはスキップ
		var is_me = false
		if not my_session_id.is_empty() and session_id == my_session_id:
			is_me = true
		elif not my_user_id.is_empty() and user_id == my_user_id:
			is_me = true

		if not is_me and (not session_id.is_empty() or not user_id.is_empty()):
			print("[LobbyScreen] Other player joined, transitioning to game")
			_transition_to_game(GameManager.current_match_id)
			return

func _transition_to_game(match_id: String) -> void:
	GameManager.current_match_id = match_id
	GameManager.is_online_match = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")
