class_name MatchManager
extends Node

## マッチマネージャー（シーン内ノード）
## ラウンド/経済/勝敗を管理
## GameEventsを介して他システムと連携

const EconomyRulesClass = preload("res://scripts/resources/economy_rules.gd")

# 列挙型
enum Team { CT, TERRORIST }
enum MatchState { WAITING, BUY_PHASE, PLAYING, ROUND_END, MATCH_OVER }

# 経済ルール（preloadしたクラスを使用）
var economy_rules = null

# マッチ状態
var current_state: MatchState = MatchState.WAITING
var current_round: int = 0
var ct_wins: int = 0
var t_wins: int = 0
var remaining_time: float = 0.0

# チーム設定
var player_team: Team = Team.CT
var loss_streak: int = 0

# フラグ
var is_bomb_planted: bool = false


func _ready() -> void:
	# 経済ルールが未設定ならデフォルトを使用
	if economy_rules == null:
		economy_rules = EconomyRulesClass.create_default()

	# GameEventsに接続
	_connect_events()


func _process(delta: float) -> void:
	if current_state == MatchState.PLAYING or current_state == MatchState.BUY_PHASE:
		_update_timer(delta)


## イベント接続
func _connect_events() -> void:
	if not has_node("/root/GameEvents"):
		return

	var events = get_node("/root/GameEvents")

	# ユニット死亡イベント
	events.unit_killed.connect(_on_unit_killed)

	# 爆弾イベント
	events.bomb_planted.connect(_on_bomb_planted)
	events.bomb_defused.connect(_on_bomb_defused)
	events.bomb_exploded.connect(_on_bomb_exploded)


## マッチ開始
func start_match() -> void:
	current_round = 0
	ct_wins = 0
	t_wins = 0
	loss_streak = 0

	# 全プレイヤーに初期資金を設定
	if SquadManager:
		for data in SquadManager.squad:
			data.money = economy_rules.starting_money

	start_new_round()


## 新しいラウンドを開始
func start_new_round() -> void:
	current_round += 1
	is_bomb_planted = false

	# SquadManagerで全員リセット
	if SquadManager:
		SquadManager.reset_for_round()

	# 購入フェーズへ
	_set_state(MatchState.BUY_PHASE)
	remaining_time = economy_rules.buy_time

	# イベント発火
	if has_node("/root/GameEvents"):
		var events = get_node("/root/GameEvents")
		events.round_started.emit(current_round)
		events.buy_phase_started.emit()


## 購入フェーズを終了してプレイ開始
func start_playing() -> void:
	_set_state(MatchState.PLAYING)
	remaining_time = economy_rules.round_time

	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").play_phase_started.emit()


## タイマー更新
func _update_timer(delta: float) -> void:
	remaining_time -= delta

	if remaining_time <= 0:
		remaining_time = 0

		if current_state == MatchState.BUY_PHASE:
			start_playing()
		elif current_state == MatchState.PLAYING:
			# 時間切れ - CTの勝利（爆弾未設置）/ Tの勝利（爆弾設置済み）
			if not is_bomb_planted:
				_end_round(Team.CT)
			else:
				_end_round(Team.TERRORIST)


## ラウンド終了
func _end_round(winner: Team) -> void:
	_set_state(MatchState.ROUND_END)

	if winner == Team.CT:
		ct_wins += 1
	else:
		t_wins += 1

	# 報酬計算
	_distribute_round_rewards(winner)

	# イベント発火
	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").round_ended.emit(winner)

	# 勝敗判定
	if ct_wins >= economy_rules.max_rounds or t_wins >= economy_rules.max_rounds:
		_match_over(Team.CT if ct_wins >= economy_rules.max_rounds else Team.TERRORIST)
	else:
		# 次ラウンドへ
		await get_tree().create_timer(3.0).timeout
		start_new_round()


## ラウンド報酬を分配
func _distribute_round_rewards(winner: Team) -> void:
	if not SquadManager:
		return

	var events = get_node_or_null("/root/GameEvents")

	if winner == player_team:
		# 勝利報酬
		SquadManager.add_money_to_all(economy_rules.win_reward)
		loss_streak = 0

		if events:
			for data in SquadManager.squad:
				events.reward_granted.emit(data.player_node, economy_rules.win_reward, "round_win")
	else:
		# 敗北報酬（連敗ボーナス）
		var loss_reward: int = economy_rules.calculate_loss_reward(loss_streak)
		SquadManager.add_money_to_all(loss_reward)
		loss_streak += 1

		if events:
			for data in SquadManager.squad:
				events.reward_granted.emit(data.player_node, loss_reward, "round_loss")


## マッチ終了
func _match_over(winner: Team) -> void:
	_set_state(MatchState.MATCH_OVER)

	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").game_over.emit(winner)


## 状態変更
func _set_state(new_state: MatchState) -> void:
	current_state = new_state


## ユニット死亡イベント処理
func _on_unit_killed(killer: Node3D, victim: Node3D, weapon_id: int) -> void:
	# 敵がキルされた場合、キル報酬
	if SquadManager and killer:
		var killer_data = SquadManager.get_player_data_by_node(killer)
		if killer_data:
			var reward: int = economy_rules.get_kill_reward(weapon_id)
			killer_data.add_money(reward)
			killer_data.record_kill()

			if has_node("/root/GameEvents"):
				get_node("/root/GameEvents").reward_granted.emit(killer, reward, "kill")

	# 全プレイヤー死亡チェック
	if SquadManager and SquadManager.get_alive_count() == 0:
		_end_round(Team.TERRORIST if player_team == Team.CT else Team.CT)

	# 全敵死亡チェック
	var enemies_alive := 0
	if GameManager:
		for enemy in GameManager.enemies:
			if enemy and is_instance_valid(enemy):
				# 敵が生きているかチェック（has_methodでis_aliveを確認）
				if enemy.has_method("is_alive") and enemy.is_alive():
					enemies_alive += 1
				elif not enemy.has_method("is_alive"):
					enemies_alive += 1  # メソッドがない場合は生存とみなす

	if enemies_alive == 0 and current_state == MatchState.PLAYING:
		_end_round(player_team)


## 爆弾設置イベント処理
func _on_bomb_planted(_site: String, planter: Node3D) -> void:
	is_bomb_planted = true
	remaining_time = economy_rules.bomb_time

	# 設置者に報酬
	if SquadManager and planter:
		var data = SquadManager.get_player_data_by_node(planter)
		if data:
			data.add_money(economy_rules.bomb_plant_reward)

			if has_node("/root/GameEvents"):
				get_node("/root/GameEvents").reward_granted.emit(
					planter, economy_rules.bomb_plant_reward, "bomb_plant"
				)


## 爆弾解除イベント処理
func _on_bomb_defused(defuser: Node3D) -> void:
	# 解除者に報酬
	if SquadManager and defuser:
		var data = SquadManager.get_player_data_by_node(defuser)
		if data:
			data.add_money(economy_rules.bomb_defuse_reward)

	# CT勝利
	_end_round(Team.CT)


## 爆弾爆発イベント処理
func _on_bomb_exploded() -> void:
	# T勝利
	_end_round(Team.TERRORIST)


## フォーマット済み時間を取得
func get_formatted_time() -> String:
	var minutes := int(remaining_time) / 60
	var seconds := int(remaining_time) % 60
	return "%d:%02d" % [minutes, seconds]


## 購入フェーズかどうか
func is_buy_phase() -> bool:
	return current_state == MatchState.BUY_PHASE


## プレイ中かどうか
func is_playing() -> bool:
	return current_state == MatchState.PLAYING
