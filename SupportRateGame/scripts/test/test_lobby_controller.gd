extends Control
## テスト用ロビーコントローラー
## サーバーなしでロビーUIをテストするためのモック機能
## 自動マッチング機能でデバッグを容易に

@onready var mock_mode_check: CheckBox = $VBoxContainer/MockModeCheck
@onready var simulate_auth_button: Button = $VBoxContainer/SimulateAuthButton
@onready var simulate_match_button: Button = $VBoxContainer/SimulateMatchButton
@onready var server_status_label: Label = $VBoxContainer/ServerStatusLabel
@onready var check_server_button: Button = $VBoxContainer/CheckServerButton
@onready var auto_test_button: Button = $VBoxContainer/AutoTestButton
@onready var debug_spawn_check: CheckBox = $VBoxContainer/DebugSpawnCheck

var _lobby_screen: Control = null
var _is_mock_authenticated: bool = false
var _auto_test_in_progress: bool = false


func _ready() -> void:
	# ロビースクリーンを取得
	_lobby_screen = get_parent().get_node_or_null("LobbyScreen")

	# シグナル接続
	simulate_auth_button.pressed.connect(_on_simulate_auth_pressed)
	simulate_match_button.pressed.connect(_on_simulate_match_pressed)
	check_server_button.pressed.connect(_on_check_server_pressed)
	mock_mode_check.toggled.connect(_on_mock_mode_toggled)

	# 自動テストボタン
	if auto_test_button:
		auto_test_button.pressed.connect(_on_auto_test_pressed)

	# デバッグスポーン設定
	if debug_spawn_check:
		debug_spawn_check.toggled.connect(_on_debug_spawn_toggled)

	# Nakamaシグナル接続
	NakamaClient.authenticated.connect(_on_nakama_authenticated)
	NakamaClient.socket_connected.connect(_on_nakama_socket_connected)
	NakamaClient.match_joined.connect(_on_nakama_match_joined)
	NakamaClient.rooms_listed.connect(_on_nakama_rooms_listed)
	NakamaClient.room_created.connect(_on_nakama_room_created)
	NakamaClient.match_presence_joined.connect(_on_nakama_presence_joined)
	NakamaClient.match_data_received.connect(_on_nakama_match_data)

	# 初期状態
	_update_button_states()

	print("[TestController] Ready - Mock mode enabled by default")


func _on_mock_mode_toggled(enabled: bool) -> void:
	_update_button_states()
	if enabled:
		print("[TestController] Mock mode enabled")
	else:
		print("[TestController] Mock mode disabled - will use real server")


func _update_button_states() -> void:
	var is_mock = mock_mode_check.button_pressed
	simulate_auth_button.disabled = not is_mock
	simulate_match_button.disabled = not is_mock or not _is_mock_authenticated


func _on_simulate_auth_pressed() -> void:
	if not _lobby_screen:
		return

	print("[TestController] Simulating authentication...")

	# モック認証を実行
	_is_mock_authenticated = true
	_update_button_states()

	# ロビースクリーンの認証成功をシミュレート
	# welcome_labelを更新
	var welcome_label = _lobby_screen.get_node_or_null("MainPanel/VBoxContainer/WelcomeLabel")
	if welcome_label:
		welcome_label.text = "ようこそ、TestPlayer さん"

	# パネルを切り替え（MainPanelを表示）
	var auth_panel = _lobby_screen.get_node_or_null("AuthPanel")
	var main_panel = _lobby_screen.get_node_or_null("MainPanel")

	if auth_panel:
		auth_panel.visible = false
	if main_panel:
		main_panel.visible = true

	print("[TestController] Mock authentication completed")


func _on_simulate_match_pressed() -> void:
	if not _lobby_screen or not _is_mock_authenticated:
		return

	print("[TestController] Simulating match found...")

	# マッチ参加をシミュレート
	GameManager.is_online_match = true
	GameManager.current_match_id = "mock-match-" + str(randi())
	GameManager.is_host = true

	print("[TestController] Mock match ID: ", GameManager.current_match_id)
	print("[TestController] Transitioning to game scene...")

	# ゲームシーンに遷移
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_check_server_pressed() -> void:
	print("[TestController] Checking server status...")

	# HTTPでサーバーの状態を確認
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_server_check_completed.bind(http))

	var url = "http://127.0.0.1:7350/healthcheck"
	var err = http.request(url)

	if err != OK:
		server_status_label.text = "サーバー: 接続エラー"
		server_status_label.modulate = Color(1, 0.5, 0.5)
		http.queue_free()


func _on_server_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		server_status_label.text = "サーバー: 接続OK"
		server_status_label.modulate = Color(0.5, 1, 0.5)
		print("[TestController] Server is running!")
	else:
		server_status_label.text = "サーバー: 未接続"
		server_status_label.modulate = Color(1, 0.5, 0.5)
		print("[TestController] Server not available (code: %d, result: %d)" % [response_code, result])


# =====================================
# 自動テスト機能
# =====================================
func _on_auto_test_pressed() -> void:
	if _auto_test_in_progress:
		return

	_auto_test_in_progress = true
	print("[TestController] === AUTO TEST START ===")

	# デバッグスポーンを有効化
	if debug_spawn_check:
		debug_spawn_check.button_pressed = true
	GameManager.debug_spawn_nearby = true

	# 自動認証開始
	if auto_test_button:
		auto_test_button.text = "接続中..."
		auto_test_button.disabled = true

	# デバイス認証（ユニークIDで複数インスタンス区別）
	var unique_id = str(randi())
	NakamaClient.authenticate_device(unique_id, true, "TestPlayer_" + unique_id.substr(0, 4))


func _on_nakama_authenticated(_session) -> void:
	if not _auto_test_in_progress:
		return
	print("[TestController] Auto-test: Authenticated, connecting socket...")
	NakamaClient.connect_socket()


func _on_nakama_socket_connected() -> void:
	if not _auto_test_in_progress:
		return
	print("[TestController] Auto-test: Socket connected, listing rooms...")
	if auto_test_button:
		auto_test_button.text = "ルーム検索中..."

	# 既存の部屋を探す
	await get_tree().create_timer(0.5).timeout
	NakamaClient.list_rooms(1)  # 1v1


func _on_nakama_rooms_listed(rooms: Array) -> void:
	if not _auto_test_in_progress:
		return

	print("[TestController] Auto-test: Found %d rooms" % rooms.size())

	if rooms.size() > 0:
		# 既存の部屋に参加（ゲストになる）
		var room = rooms[0]
		var match_id = room.get("match_id", "")
		print("[TestController] Auto-test: Joining existing room as GUEST: %s" % match_id)
		if auto_test_button:
			auto_test_button.text = "参加中..."
		GameManager.is_host = false
		# ゲストのチームはホストから割り当てられるまで待つ
		NakamaClient.join_match(match_id)
	else:
		# 新規部屋作成（ホストになる）
		print("[TestController] Auto-test: No rooms found, creating new room as HOST...")
		if auto_test_button:
			auto_test_button.text = "部屋作成中..."
		GameManager.is_host = true
		GameManager.assigned_team = GameManager.Team.CT  # ホストはCT
		NakamaClient.create_room(1, false)


func _on_nakama_room_created(match_id: String, _room_code: String) -> void:
	if not _auto_test_in_progress:
		return
	print("[TestController] Auto-test: Room created: %s" % match_id)
	# 部屋に参加
	NakamaClient.join_match(match_id)


func _on_nakama_match_joined(match_id: String) -> void:
	if not _auto_test_in_progress:
		return

	print("[TestController] Auto-test: Joined match: %s, is_host: %s" % [match_id, GameManager.is_host])
	GameManager.current_match_id = match_id
	GameManager.is_online_match = true
	GameManager.debug_spawn_nearby = true

	if GameManager.is_host:
		# ホストは相手を待つ
		if auto_test_button:
			auto_test_button.text = "相手待ち..."
	else:
		# ゲストはチーム割り当てを待つ
		if auto_test_button:
			auto_test_button.text = "チーム割当待ち..."


## 他プレイヤーがマッチに参加（ホスト側で受信）
func _on_nakama_presence_joined(presences: Array) -> void:
	if not _auto_test_in_progress:
		return
	if not GameManager.is_host:
		return

	var my_user_id = NakamaClient.get_user_id()

	for presence in presences:
		var user_id = presence.get("user_id", "")
		if user_id != my_user_id and not user_id.is_empty():
			print("[TestController] Auto-test: Guest joined, sending team assignment")
			# チーム割り当てを送信
			await get_tree().create_timer(0.5).timeout
			_send_team_assignment()
			return


## チーム割り当て送信（ホスト）
const OPCODE_TEAM_ASSIGNMENT: int = 5

func _send_team_assignment() -> void:
	var host_team = GameManager.assigned_team
	var guest_team = 1 - host_team

	var data = {
		"host_team": host_team,
		"guest_team": guest_team
	}

	print("[TestController] Sending team assignment: host=%s, guest=%s" % [
		"CT" if host_team == 0 else "T",
		"CT" if guest_team == 0 else "T"
	])

	# 複数回送信
	for i in range(3):
		NakamaClient.send_match_data(OPCODE_TEAM_ASSIGNMENT, data)
		await get_tree().create_timer(0.3).timeout

	# ホストもゲームに遷移
	await get_tree().create_timer(0.5).timeout
	if auto_test_button:
		auto_test_button.text = "ゲーム開始..."
	get_tree().change_scene_to_file("res://scenes/game.tscn")


## マッチデータ受信（ゲスト側でチーム割り当て受信）
func _on_nakama_match_data(op_code: int, data: Dictionary, _sender_id: String) -> void:
	if not _auto_test_in_progress:
		return
	if GameManager.is_host:
		return

	if op_code != OPCODE_TEAM_ASSIGNMENT:
		return

	# ゲストのチームを設定
	var my_team = data.get("guest_team", 0)
	GameManager.assigned_team = my_team as GameManager.Team

	print("[TestController] Auto-test: Received team assignment: %s" % ("CT" if my_team == 0 else "T"))

	if auto_test_button:
		auto_test_button.text = "ゲーム開始..."

	# ゲームに遷移
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_debug_spawn_toggled(enabled: bool) -> void:
	GameManager.debug_spawn_nearby = enabled
	print("[TestController] Debug spawn nearby: %s" % enabled)
