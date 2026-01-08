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
var _waiting_for_team_assignment: bool = false  # ゲストがチーム割り当て待ち

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
	NakamaClient.match_data_received.connect(_on_match_data_received)

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

	# ホストはランダムでチームを割り当て（0=CT, 1=TERRORIST）
	var random_team = randi() % 2
	GameManager.assigned_team = random_team as GameManager.Team
	print("[LobbyScreen] Host assigned team: %s" % ("CT" if random_team == 0 else "TERRORIST"))

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

	# ゲストはチーム割り当てを待つ
	_waiting_for_team_assignment = true
	_show_waiting_panel()
	if waiting_status_label:
		waiting_status_label.text = "チーム割り当て待ち..."

func _on_match_presence_joined(presences: Array) -> void:
	# ホストの場合、他のプレイヤーが参加したらチーム割り当てを送信
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
			print("[LobbyScreen] Other player joined, sending team assignment")
			# チーム割り当てをゲストに送信
			_send_team_assignment_to_guest()
			return

# =====================================
# チーム割り当て（ロビー内で完了）
# =====================================
const OPCODE_TEAM_ASSIGNMENT: int = 5  # NetworkSyncManager.OpCode.TEAM_ASSIGNMENTと同じ

## ホストがチーム割り当てをゲストに送信
func _send_team_assignment_to_guest() -> void:
	# ゲストがマッチに完全に参加するまで待つ（長めに設定）
	await get_tree().create_timer(1.0).timeout

	# ホストのチームはすでにランダムで決定済み（room作成時）
	var host_team = GameManager.assigned_team
	var guest_team = 1 - host_team  # 反対のチーム

	var data = {
		"host_team": host_team,
		"guest_team": guest_team
	}

	print("[LobbyScreen] Sending team assignment - Host: %s, Guest: %s" % [
		"CT" if host_team == 0 else "TERRORIST",
		"CT" if guest_team == 0 else "TERRORIST"
	])

	# 複数回送信してゲストが確実に受け取れるようにする
	for i in range(3):
		NakamaClient.send_match_data(OPCODE_TEAM_ASSIGNMENT, data)
		print("[LobbyScreen] Team assignment sent (attempt %d)" % (i + 1))
		await get_tree().create_timer(0.3).timeout

	# ホストもゲームに遷移
	await get_tree().create_timer(0.5).timeout
	_transition_to_game(GameManager.current_match_id)

## マッチデータ受信（ゲスト側でチーム割り当てを受信）
func _on_match_data_received(op_code: int, data: Dictionary, _sender_id: String) -> void:
	print("[LobbyScreen] Received match data - op_code: %d, waiting: %s" % [op_code, _waiting_for_team_assignment])

	if op_code != OPCODE_TEAM_ASSIGNMENT:
		print("[LobbyScreen] Ignoring op_code %d (expected %d)" % [op_code, OPCODE_TEAM_ASSIGNMENT])
		return

	if not _waiting_for_team_assignment:
		print("[LobbyScreen] Not waiting for team assignment, ignoring")
		return

	# ゲストはguest_teamを自分のチームとして設定
	var my_team = data.get("guest_team", 0)
	GameManager.assigned_team = my_team as GameManager.Team
	_waiting_for_team_assignment = false

	print("[LobbyScreen] Received team assignment: %s" % ("CT" if my_team == 0 else "TERRORIST"))

	# ゲームに遷移
	_transition_to_game(GameManager.current_match_id)

func _transition_to_game(match_id: String) -> void:
	GameManager.current_match_id = match_id
	GameManager.is_online_match = true

	print("[LobbyScreen] Transitioning to game - My team: %s" % (
		"CT" if GameManager.assigned_team == GameManager.Team.CT else "TERRORIST"
	))

	get_tree().change_scene_to_file("res://scenes/game.tscn")
