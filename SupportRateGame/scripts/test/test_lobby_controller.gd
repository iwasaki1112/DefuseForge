extends Control
## テスト用ロビーコントローラー
## サーバーなしでロビーUIをテストするためのモック機能

@onready var mock_mode_check: CheckBox = $VBoxContainer/MockModeCheck
@onready var simulate_auth_button: Button = $VBoxContainer/SimulateAuthButton
@onready var simulate_match_button: Button = $VBoxContainer/SimulateMatchButton
@onready var server_status_label: Label = $VBoxContainer/ServerStatusLabel
@onready var check_server_button: Button = $VBoxContainer/CheckServerButton

var _lobby_screen: Control = null
var _is_mock_authenticated: bool = false


func _ready() -> void:
	# ロビースクリーンを取得
	_lobby_screen = get_parent().get_node_or_null("LobbyScreen")

	# シグナル接続
	simulate_auth_button.pressed.connect(_on_simulate_auth_pressed)
	simulate_match_button.pressed.connect(_on_simulate_match_pressed)
	check_server_button.pressed.connect(_on_check_server_pressed)
	mock_mode_check.toggled.connect(_on_mock_mode_toggled)

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
