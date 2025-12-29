extends CanvasLayer

## ゲームUIの管理（CS1.6スタイル）

@onready var timer_label: Label = $MarginContainer/VBoxContainer/TimerLabel
@onready var money_label: Label = $MarginContainer/VBoxContainer/MoneyLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel
@onready var round_label: Label = $MarginContainer/VBoxContainer/RoundLabel
@onready var game_over_panel: Panel = $GameOverPanel
@onready var final_score_label: Label = $GameOverPanel/VBoxContainer/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/VBoxContainer/RestartButton

# デバッグ用
var debug_label: Label = null


func _ready() -> void:
	# デバッグラベルを作成（右下）
	debug_label = Label.new()
	debug_label.add_theme_font_size_override("font_size", 16)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	debug_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	debug_label.anchor_left = 1.0
	debug_label.anchor_top = 1.0
	debug_label.anchor_right = 1.0
	debug_label.anchor_bottom = 1.0
	debug_label.offset_left = -250
	debug_label.offset_top = -80
	debug_label.offset_right = -10
	debug_label.offset_bottom = -10
	add_child(debug_label)
	game_over_panel.visible = false
	restart_button.pressed.connect(_on_restart_button_pressed)

	# GameManagerのシグナルに接続
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)

	# 初期値を設定
	_update_money(GameManager.player_money)
	_update_health(GameManager.player_health)
	_update_round()


func _process(_delta: float) -> void:
	if GameManager.is_game_running:
		_update_timer()
		_update_health(GameManager.player_health)
		_update_debug_info()


func _update_timer() -> void:
	var state_prefix := ""
	match GameManager.current_state:
		GameManager.GameState.BUY_PHASE:
			state_prefix = "BUY "
		GameManager.GameState.PLAYING:
			if GameManager.is_bomb_planted:
				state_prefix = "💣 "
			else:
				state_prefix = ""

	timer_label.text = state_prefix + GameManager.get_formatted_time()


func _update_money(amount: int) -> void:
	money_label.text = "$%d" % amount


func _update_health(health: float) -> void:
	health_label.text = "HP: %d" % int(health)
	if GameManager.player_armor > 0:
		health_label.text += " | Armor: %d" % int(GameManager.player_armor)


func _update_round() -> void:
	round_label.text = "CT %d - %d T | Round %d" % [
		GameManager.ct_wins,
		GameManager.t_wins,
		GameManager.current_round
	]


func _on_money_changed(amount: int) -> void:
	_update_money(amount)


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	match new_state:
		GameManager.GameState.GAME_OVER:
			_show_game_over()
		_:
			pass


func _on_round_started(_round_number: int) -> void:
	_update_round()


func _on_round_ended(winner: GameManager.Team) -> void:
	_update_round()
	# ラウンド終了メッセージを表示（オプション）
	var winner_text := "CT" if winner == GameManager.Team.CT else "Terrorist"
	print("%s wins the round!" % winner_text)


func _show_game_over() -> void:
	game_over_panel.visible = true

	var winner := "CT" if GameManager.ct_wins > GameManager.t_wins else "Terrorist"
	final_score_label.text = "Game Over\n%s Wins!\n\nCT %d - %d T" % [
		winner,
		GameManager.ct_wins,
		GameManager.t_wins
	]


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()


func _update_debug_info() -> void:
	if debug_label == null:
		return

	var player_pos := Vector3.ZERO
	var on_floor := false

	# プレイヤー情報を取得
	if GameManager.player:
		player_pos = GameManager.player.global_position
		on_floor = GameManager.player.is_on_floor()

	debug_label.text = "Player: (%.1f, %.1f, %.1f)\nOn Floor: %s" % [
		player_pos.x, player_pos.y, player_pos.z,
		"Yes" if on_floor else "No"
	]
