extends CanvasLayer

## ゲームUIの管理（CS1.6スタイル）

@onready var timer_label: Label = $MarginContainer/VBoxContainer/TimerLabel
@onready var money_label: Label = $MarginContainer/VBoxContainer/MoneyLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel
@onready var round_label: Label = $MarginContainer/VBoxContainer/RoundLabel
@onready var game_over_panel: Panel = $GameOverPanel
@onready var final_score_label: Label = $GameOverPanel/VBoxContainer/FinalScoreLabel
@onready var restart_button: Button = $GameOverPanel/VBoxContainer/RestartButton

# Shopping UI
@onready var shopping_panel: Panel = $ShoppingPanel
@onready var none_button: Button = $ShoppingPanel/VBoxContainer/NoneButton
@onready var ak47_button: Button = $ShoppingPanel/VBoxContainer/AK47Button
@onready var pistol_button: Button = $ShoppingPanel/VBoxContainer/PistolButton

# デバッグ用
var debug_label: Label = null

# パス残り時間表示用
var path_time_label: Label = null
var path_time_bar: ProgressBar = null
var path_time_container: Control = null


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

	# パス残り時間表示を作成（画面下部中央）
	_create_path_time_ui()

	game_over_panel.visible = false
	shopping_panel.visible = false
	restart_button.pressed.connect(_on_restart_button_pressed)

	# Shopping buttons
	none_button.pressed.connect(_on_none_button_pressed)
	ak47_button.pressed.connect(_on_ak47_button_pressed)
	pistol_button.pressed.connect(_on_pistol_button_pressed)
	
	# ボタンテキストに価格を表示
	_update_weapon_button_texts()

	# GameEventsのシグナルに接続
	if has_node("/root/GameEvents"):
		var events = get_node("/root/GameEvents")
		events.round_started.connect(_on_round_started)
		events.round_ended.connect(_on_round_ended)
		events.buy_phase_started.connect(_on_buy_phase_started)
		events.play_phase_started.connect(_on_play_phase_started)
		events.strategy_phase_started.connect(_on_strategy_phase_started)
		events.execution_phase_started.connect(_on_execution_phase_started)
		events.game_over.connect(_on_game_over)
		events.money_changed.connect(_on_money_changed_event)

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

	# MatchManagerからフェーズ名を取得
	if GameManager and GameManager.match_manager:
		var mm = GameManager.match_manager
		state_prefix = mm.get_phase_name() + " "
		if mm.current_turn > 0:
			state_prefix = "T%d %s" % [mm.current_turn, state_prefix]
	else:
		# フォールバック: GameManager.current_stateを使用
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


func _on_money_changed_event(_player: Node3D, amount: int) -> void:
	_update_money(amount)


## 購入フェーズ開始
func _on_buy_phase_started() -> void:
	print("[GameUI] Buy phase started")
	if shopping_panel:
		shopping_panel.visible = true
	else:
		print("[GameUI] ERROR: shopping_panel is null!")


## プレイフェーズ開始
func _on_play_phase_started() -> void:
	print("[GameUI] Play phase started")
	shopping_panel.visible = false


## ゲームオーバー
func _on_game_over(_winner_team: int) -> void:
	print("[GameUI] Game over")
	shopping_panel.visible = false
	_show_game_over()


func _on_round_started(_round_number: int) -> void:
	_update_round()


func _on_round_ended(winner_team: int) -> void:
	_update_round()
	# ラウンド終了メッセージを表示（オプション）
	var winner_text := "CT" if winner_team == 0 else "Terrorist"
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


## Shopping button handlers
func _on_none_button_pressed() -> void:
	_buy_weapon(CharacterSetup.WeaponId.NONE)


func _on_ak47_button_pressed() -> void:
	_buy_weapon(CharacterSetup.WeaponId.AK47)


func _on_pistol_button_pressed() -> void:
	_buy_weapon(CharacterSetup.WeaponId.USP)


func _buy_weapon(weapon_id: int) -> void:
	var weapon_data = CharacterSetup.get_weapon_data(weapon_id)

	# 購入処理（SquadManager経由で武器IDベースで購入）
	if GameManager.buy_weapon_for_selected(weapon_id):
		print("[GameUI] Bought weapon: %s for $%d" % [weapon_data.name, weapon_data.price])
	else:
		print("[GameUI] Cannot buy weapon: %s (need $%d, have $%d)" % [weapon_data.name, weapon_data.price, GameManager.player_money])


func _update_weapon_button_texts() -> void:
	var ak47_data = CharacterSetup.get_weapon_data(CharacterSetup.WeaponId.AK47)
	var usp_data = CharacterSetup.get_weapon_data(CharacterSetup.WeaponId.USP)

	none_button.text = "None"
	ak47_button.text = "AK-47 ($%d)" % ak47_data.price
	pistol_button.text = "USP ($%d)" % usp_data.price


## パス残り時間UI作成
func _create_path_time_ui() -> void:
	# コンテナ（画面下部中央）
	path_time_container = Control.new()
	path_time_container.anchors_preset = Control.PRESET_BOTTOM_WIDE
	path_time_container.anchor_top = 1.0
	path_time_container.anchor_bottom = 1.0
	path_time_container.offset_top = -60
	path_time_container.offset_bottom = -10
	path_time_container.visible = false  # 初期状態は非表示
	add_child(path_time_container)

	# VBoxで縦に配置
	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_CENTER_BOTTOM
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = -100
	vbox.offset_right = 100
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	path_time_container.add_child(vbox)

	# プログレスバー
	path_time_bar = ProgressBar.new()
	path_time_bar.custom_minimum_size = Vector2(200, 20)
	path_time_bar.max_value = 10.0
	path_time_bar.value = 10.0
	path_time_bar.show_percentage = false
	vbox.add_child(path_time_bar)

	# ラベル
	path_time_label = Label.new()
	path_time_label.add_theme_font_size_override("font_size", 14)
	path_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	path_time_label.text = "残り: 10.0秒"
	vbox.add_child(path_time_label)


## PathManagerに接続
func connect_path_manager(path_manager: Node) -> void:
	if path_manager.has_signal("path_time_changed"):
		path_manager.path_time_changed.connect(_on_path_time_changed)


## パス時間変更時
func _on_path_time_changed(current_time: float, max_time: float) -> void:
	if path_time_container == null:
		return

	var remaining := max_time - current_time

	# プログレスバーを更新
	path_time_bar.max_value = max_time
	path_time_bar.value = remaining

	# ラベルを更新
	path_time_label.text = "残り: %.1f秒" % remaining

	# 残り少なくなったら色を変更
	if remaining < max_time * 0.2:
		path_time_bar.modulate = Color.RED
	elif remaining < max_time * 0.5:
		path_time_bar.modulate = Color.YELLOW
	else:
		path_time_bar.modulate = Color.WHITE


## 戦略フェーズ開始
func _on_strategy_phase_started(turn_number: int) -> void:
	print("[GameUI] Strategy phase started (Turn %d)" % turn_number)
	shopping_panel.visible = false
	# パス時間UIを表示
	if path_time_container:
		path_time_container.visible = true
		# リセット
		if path_time_bar:
			path_time_bar.value = path_time_bar.max_value
			path_time_bar.modulate = Color.WHITE
		if path_time_label:
			path_time_label.text = "残り: %.1f秒" % path_time_bar.max_value


## 実行フェーズ開始
func _on_execution_phase_started(turn_number: int) -> void:
	print("[GameUI] Execution phase started (Turn %d)" % turn_number)
	# パス時間UIを非表示
	if path_time_container:
		path_time_container.visible = false
