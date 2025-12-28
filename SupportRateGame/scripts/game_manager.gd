extends Node

## ゲーム全体を管理するシングルトン
## スコア、時間制限、ゲーム状態を管理

signal score_changed(new_score: int)
signal time_changed(remaining_time: float)
signal support_rate_changed(rate: float)
signal game_over(final_score: int, coins_collected: int, support_rate: float)

# ゲーム設定
const GAME_DURATION: float = 60.0  # 制限時間（秒）
const TOTAL_COINS: int = 20
const BASE_SUPPORT_RATE: float = 30.0  # 基本支持率
const RATE_PER_COIN: float = 3.0  # コイン1個あたりの支持率上昇

var current_score: int = 0
var coins_collected: int = 0
var remaining_time: float = GAME_DURATION
var is_game_over: bool = false
var is_game_running: bool = false


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if is_game_running and not is_game_over:
		_update_timer(delta)


func start_game() -> void:
	current_score = 0
	coins_collected = 0
	remaining_time = GAME_DURATION
	is_game_over = false
	is_game_running = true

	score_changed.emit(current_score)
	time_changed.emit(remaining_time)
	support_rate_changed.emit(calculate_support_rate())


func stop_game() -> void:
	is_game_running = false


func _update_timer(delta: float) -> void:
	remaining_time -= delta

	if remaining_time <= 0:
		remaining_time = 0
		_game_over()

	time_changed.emit(remaining_time)


func add_score(points: int) -> void:
	if is_game_over:
		return

	current_score += points
	coins_collected += 1

	score_changed.emit(current_score)
	support_rate_changed.emit(calculate_support_rate())

	# 全コイン収集でボーナス
	if coins_collected >= TOTAL_COINS:
		_add_bonus()


func _add_bonus() -> void:
	current_score += 100
	score_changed.emit(current_score)


func calculate_support_rate() -> float:
	var bonus_rate: float = coins_collected * RATE_PER_COIN
	return minf(BASE_SUPPORT_RATE + bonus_rate, 100.0)


func _game_over() -> void:
	is_game_over = true
	is_game_running = false
	game_over.emit(current_score, coins_collected, calculate_support_rate())


func get_result_message() -> String:
	var support_rate: float = calculate_support_rate()

	if support_rate >= 70:
		return "素晴らしい！圧倒的支持を獲得しました！\n日本の未来は明るい！"
	elif support_rate >= 50:
		return "良い結果です！\n過半数の支持を獲得しました！"
	elif support_rate >= 40:
		return "まずまずの結果です。\nもう少し頑張りましょう！"
	else:
		return "もっと支持を集めましょう！\n再チャレンジ！"
