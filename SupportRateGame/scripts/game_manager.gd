extends Node

## ゲーム全体を管理するシングルトン
## ラウンド、経済、ゲーム状態を管理（CS1.6スタイル）

# シグナル
signal round_started(round_number: int)
signal round_ended(winner: Team)
signal player_died(player: Node3D)
signal enemy_died(enemy: Node3D)
signal money_changed(amount: int)
signal game_state_changed(new_state: GameState)

# 列挙型
enum Team { CT, TERRORIST }
enum GameState { MENU, BUY_PHASE, PLAYING, ROUND_END, GAME_OVER }
enum GameMode { DEFUSE, HOSTAGE }

# ゲーム設定
const ROUND_TIME: float = 105.0  # 1分45秒
const BUY_TIME: float = 1.0  # デバッグ用（本番は15.0）
const BOMB_TIME: float = 40.0
const MAX_ROUNDS: int = 15  # 勝利に必要なラウンド数（MR15）
const STARTING_MONEY: int = 800

# 経済設定
const WIN_REWARD: int = 3250
const LOSS_REWARD_BASE: int = 1400
const LOSS_REWARD_INCREMENT: int = 500
const MAX_LOSS_BONUS: int = 3400
const BOMB_PLANT_REWARD: int = 300
const KILL_REWARD_DEFAULT: int = 300
const KILL_REWARD_AWP: int = 100
const KILL_REWARD_KNIFE: int = 1500

# ゲーム状態
var current_state: GameState = GameState.MENU
var current_mode: GameMode = GameMode.DEFUSE
var current_round: int = 0
var ct_wins: int = 0
var t_wins: int = 0
var remaining_time: float = 0.0

# プレイヤー情報
var player_team: Team = Team.CT
var player_money: int = STARTING_MONEY
var player_health: float = 100.0
var player_armor: float = 0.0
var loss_streak: int = 0

# ゲームオブジェクト参照
var player: Node3D = null
var enemies: Array[Node3D] = []

# フラグ
var is_game_running: bool = false
var is_bomb_planted: bool = false


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING or current_state == GameState.BUY_PHASE:
		_update_timer(delta)


## ゲームを開始
func start_game(mode: GameMode = GameMode.DEFUSE) -> void:
	current_mode = mode
	current_round = 0
	ct_wins = 0
	t_wins = 0
	player_money = STARTING_MONEY
	loss_streak = 0
	is_game_running = true

	start_new_round()


## 新しいラウンドを開始
func start_new_round() -> void:
	current_round += 1
	player_health = 100.0
	is_bomb_planted = false

	# 購入フェーズへ
	_set_state(GameState.BUY_PHASE)
	remaining_time = BUY_TIME

	round_started.emit(current_round)


## 購入フェーズを終了してプレイ開始
func start_playing() -> void:
	_set_state(GameState.PLAYING)
	remaining_time = ROUND_TIME


## タイマー更新
func _update_timer(delta: float) -> void:
	remaining_time -= delta

	if remaining_time <= 0:
		remaining_time = 0

		if current_state == GameState.BUY_PHASE:
			start_playing()
		elif current_state == GameState.PLAYING:
			# 時間切れ - CTの勝利（爆弾解除モード）/ Tの勝利（人質モード）
			if current_mode == GameMode.DEFUSE:
				_end_round(Team.CT if not is_bomb_planted else Team.TERRORIST)
			else:
				_end_round(Team.TERRORIST)


## ラウンド終了
func _end_round(winner: Team) -> void:
	_set_state(GameState.ROUND_END)

	if winner == Team.CT:
		ct_wins += 1
	else:
		t_wins += 1

	# 報酬計算
	if winner == player_team:
		_add_money(WIN_REWARD)
		loss_streak = 0
	else:
		var loss_reward: int = mini(LOSS_REWARD_BASE + (loss_streak * LOSS_REWARD_INCREMENT), MAX_LOSS_BONUS)
		_add_money(loss_reward)
		loss_streak += 1

	round_ended.emit(winner)

	# 勝敗判定
	if ct_wins >= MAX_ROUNDS or t_wins >= MAX_ROUNDS:
		_game_over()
	else:
		# 次ラウンドへ（実際はUIで確認後）
		await get_tree().create_timer(3.0).timeout
		start_new_round()


## ゲーム終了
func _game_over() -> void:
	_set_state(GameState.GAME_OVER)
	is_game_running = false


## 状態変更
func _set_state(new_state: GameState) -> void:
	current_state = new_state
	game_state_changed.emit(new_state)


## お金を追加
func _add_money(amount: int) -> void:
	player_money = min(player_money + amount, 16000)  # 上限$16000
	money_changed.emit(player_money)


## 武器購入
func buy_weapon(price: int) -> bool:
	if current_state != GameState.BUY_PHASE:
		return false

	if player_money >= price:
		player_money -= price
		money_changed.emit(player_money)
		return true

	return false


## キル報酬
func on_enemy_killed(weapon_type: String = "default") -> void:
	var reward: int
	match weapon_type:
		"awp":
			reward = KILL_REWARD_AWP
		"knife":
			reward = KILL_REWARD_KNIFE
		_:
			reward = KILL_REWARD_DEFAULT

	_add_money(reward)


## 爆弾設置
func on_bomb_planted() -> void:
	is_bomb_planted = true
	remaining_time = BOMB_TIME
	_add_money(BOMB_PLANT_REWARD)


## プレイヤーダメージ
func damage_player(amount: float) -> void:
	# アーマー計算（アーマーは50%のダメージを吸収）
	if player_armor > 0:
		var armor_damage := amount * 0.5
		if armor_damage <= player_armor:
			player_armor -= armor_damage
			amount -= armor_damage
		else:
			amount -= player_armor
			player_armor = 0

	player_health -= amount

	if player_health <= 0:
		player_health = 0
		_on_player_died()


## プレイヤー死亡
func _on_player_died() -> void:
	if player:
		player_died.emit(player)

	# プレイヤーが死亡したらラウンド終了（シングルプレイヤーの場合）
	_end_round(Team.TERRORIST if player_team == Team.CT else Team.CT)


## ゲーム停止
func stop_game() -> void:
	is_game_running = false
	current_state = GameState.MENU


## フォーマット済み時間を取得
func get_formatted_time() -> String:
	var minutes := int(remaining_time) / 60
	var seconds := int(remaining_time) % 60
	return "%d:%02d" % [minutes, seconds]
