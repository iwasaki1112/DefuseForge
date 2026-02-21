extends Control
class_name LobbyScreen
## ロビー画面
## オートマッチング方式：画面表示と同時にマッチング開始、2人揃ったら即ゲーム開始

const GAME_SCENE := "res://scenes/screens/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"


## 状態
enum LobbyState {
	MATCHING,   # マッチング中
	IDLE,       # 初期/キャンセル後
}

var _state: LobbyState = LobbyState.IDLE
var _network_manager: NetworkManager = null

## ドットアニメーション用
var _dot_timer: float = 0.0
var _dot_count: int = 0

## UI参照
var _status_label: Label
var _matching_label: Label
var _cancel_button: Button


func _ready() -> void:
	_setup_ui()
	_setup_network_manager()
	_start_matching()


func _process(delta: float) -> void:
	if _state != LobbyState.MATCHING:
		return

	# ドットアニメーション更新
	_dot_timer += delta
	if _dot_timer >= 0.5:
		_dot_timer = 0.0
		_dot_count = (_dot_count + 1) % 4
		var dots := ".".repeat(_dot_count)
		_matching_label.text = "マッチング中%s" % dots


func _setup_network_manager() -> void:
	_network_manager = NetworkManager.new()
	_network_manager.name = "NetworkManager"
	add_child(_network_manager)

	_network_manager.connection_state_changed.connect(_on_connection_state_changed)
	_network_manager.connection_failed.connect(_on_connection_failed)
	_network_manager.match_found.connect(_on_match_found)
	_network_manager.message_received.connect(_on_network_message)
	_network_manager.players_updated.connect(_on_players_updated)


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
	main_container.custom_minimum_size = Vector2(400, 300)
	main_container.add_theme_constant_override("separation", 30)
	center_container.add_child(main_container)

	# タイトル（モードに合わせて表示）
	var title := Label.new()
	if SettingsManager.get_game_mode() == "coop":
		title.text = "COOP"
	else:
		title.text = "Multiplayer"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)

	# マッチング中ラベル
	_matching_label = Label.new()
	_matching_label.text = "マッチング中..."
	_matching_label.add_theme_font_size_override("font_size", 24)
	_matching_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(_matching_label)

	# ステータスラベル（エラー表示用）
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
	main_container.add_child(_status_label)

	# キャンセルボタン
	_cancel_button = Button.new()
	_cancel_button.text = "キャンセル"
	_cancel_button.custom_minimum_size = Vector2(300, 50)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	main_container.add_child(_cancel_button)


## ========================================
## マッチング
## ========================================

func _start_matching() -> void:
	_state = LobbyState.MATCHING
	_status_label.text = ""
	_matching_label.visible = true
	_cancel_button.disabled = false
	_dot_timer = 0.0
	_dot_count = 0

	var player_name := SettingsManager.get_player_name()
	if player_name.is_empty():
		player_name = "Player"

	if not _network_manager.find_match(player_name):
		_status_label.text = "サーバーに接続できません"
		_state = LobbyState.IDLE
		_matching_label.text = "マッチング失敗"


## ========================================
## ボタンハンドラ
## ========================================

func _on_cancel_pressed() -> void:
	_network_manager.cancel_match()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## ========================================
## ネットワークイベントハンドラ
## ========================================

func _on_connection_state_changed(_conn_state: NetworkManager.ConnectionState) -> void:
	pass


func _on_connection_failed(reason: String) -> void:
	_status_label.text = reason
	_state = LobbyState.IDLE
	_matching_label.text = "接続失敗"


func _on_match_found(_room_id: String, map_id: String) -> void:
	# チームをPlayerStateに反映
	var players := _network_manager.get_players()
	var local_id := _network_manager.get_local_peer_id()
	var my_team: int = players.get(local_id, {}).get("team", GameCharacter.Team.NONE)
	if my_team != GameCharacter.Team.NONE:
		PlayerState.set_player_team(my_team)

	# 即座にゲーム開始
	_start_game(map_id)


func _on_network_message(_from_peer: int, msg_type: int, data: Dictionary) -> void:
	if msg_type == NetworkConstants.MessageType.ROUND_STATE:
		var action: String = data.get("action", "")
		if action == "start_game":
			var map_id: String = data.get("map_id", "office")
			_start_game(map_id)


func _on_players_updated() -> void:
	# 自分のチームをPlayerStateに反映
	var players := _network_manager.get_players()
	var local_id := _network_manager.get_local_peer_id()
	var my_team: int = players.get(local_id, {}).get("team", GameCharacter.Team.NONE)
	if my_team != GameCharacter.Team.NONE:
		PlayerState.set_player_team(my_team)


## ========================================
## 外部API
## ========================================

## NetworkManagerを取得
func get_network_manager() -> NetworkManager:
	return _network_manager


## ゲームを開始（シーン遷移）
func _start_game(map_id: String) -> void:
	# NetworkManagerを親から切り離して保持
	remove_child(_network_manager)

	# ゲームシーンをロード（統合されたGameScreenを使用）
	var game_scene := load(GAME_SCENE).instantiate() as GameScreen

	# モードに応じてセットアップ（add_child前に呼ぶ）
	if SettingsManager.get_game_mode() == "coop":
		game_scene.setup_coop(_network_manager, map_id)
	else:
		game_scene.setup_multiplayer(_network_manager, map_id)

	get_tree().root.add_child(game_scene)
	game_scene.add_child(_network_manager)

	# このシーンを削除
	queue_free()
