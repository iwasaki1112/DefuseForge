class_name MatchManager
extends Node

## マッチマネージャー（シーン内ノード）
## ラウンド/経済/勝敗を管理
## GameEventsを介して他システムと連携

# 列挙型
enum Team { CT, TERRORIST }
enum MatchState { WAITING, BUY_PHASE, STRATEGY_PHASE, EXECUTION_PHASE, ROUND_END, MATCH_OVER }

# デフォルト経済ルール（リソースファイル）
const DEFAULT_ECONOMY_RULES = preload("res://resources/economy_rules.tres")

# 経済ルール
var economy_rules: Resource = null

# マッチ状態
var current_state: MatchState = MatchState.WAITING
var current_round: int = 0
var current_turn: int = 0  # ラウンド内のターン番号
var ct_wins: int = 0
var t_wins: int = 0
var remaining_time: float = 0.0

# チーム設定
var player_team: Team = Team.CT
var loss_streak: int = 0

# フラグ
var is_bomb_planted: bool = false


func _ready() -> void:
	# 経済ルールが未設定ならデフォルトリソースを使用
	if economy_rules == null:
		economy_rules = DEFAULT_ECONOMY_RULES

	# GameEventsに接続
	_connect_events()


func _process(delta: float) -> void:
	if current_state in [MatchState.BUY_PHASE, MatchState.STRATEGY_PHASE, MatchState.EXECUTION_PHASE]:
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


## SquadManagerへの参照を取得
func _get_squad_manager() -> Node:
	return GameManager.squad_manager if GameManager else null


## マッチ開始
func start_match() -> void:
	current_round = 0
	ct_wins = 0
	t_wins = 0
	loss_streak = 0

	# 全プレイヤーに初期資金を設定
	var sm = _get_squad_manager()
	if sm:
		for data in sm.squad:
			data.money = economy_rules.starting_money

	start_new_round()


## 新しいラウンドを開始
func start_new_round() -> void:
	current_round += 1
	current_turn = 0
	is_bomb_planted = false

	# SquadManagerで全員リセット
	var sm = _get_squad_manager()
	if sm:
		sm.reset_for_round()

	# 購入フェーズへ
	_set_state(MatchState.BUY_PHASE)
	remaining_time = economy_rules.buy_time

	# イベント発火
	if has_node("/root/GameEvents"):
		var events = get_node("/root/GameEvents")
		events.round_started.emit(current_round)
		events.buy_phase_started.emit()


## 購入フェーズを終了して戦略フェーズ開始
func start_strategy_phase() -> void:
	current_turn += 1
	_set_state(MatchState.STRATEGY_PHASE)
	remaining_time = economy_rules.strategy_time

	if has_node("/root/GameEvents"):
		var events = get_node("/root/GameEvents")
		events.strategy_phase_started.emit(current_turn)
		# 後方互換: 最初のターンでplay_phase_startedも発火
		if current_turn == 1:
			events.play_phase_started.emit()


## 戦略フェーズを終了して実行フェーズ開始
func start_execution_phase() -> void:
	_set_state(MatchState.EXECUTION_PHASE)
	remaining_time = economy_rules.execution_time

	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").execution_phase_started.emit(current_turn)


## 購入フェーズを終了してプレイ開始（後方互換用）
func start_playing() -> void:
	start_strategy_phase()


## タイマー更新
func _update_timer(delta: float) -> void:
	remaining_time -= delta

	if remaining_time <= 0:
		remaining_time = 0

		match current_state:
			MatchState.BUY_PHASE:
				start_strategy_phase()
			MatchState.STRATEGY_PHASE:
				start_execution_phase()
			MatchState.EXECUTION_PHASE:
				# ラウンド終了条件をチェック
				if _check_round_end_conditions():
					return
				# 次の戦略フェーズへ
				start_strategy_phase()


## ラウンド終了条件をチェック
func _check_round_end_conditions() -> bool:
	var sm = _get_squad_manager()

	# 全プレイヤー死亡
	if sm and sm.get_alive_count() == 0:
		_end_round(Team.TERRORIST if player_team == Team.CT else Team.CT)
		return true

	# 全敵死亡
	var enemies_alive := 0
	if GameManager:
		for enemy in GameManager.enemies:
			if enemy and is_instance_valid(enemy):
				if enemy.has_method("is_alive") and enemy.is_alive():
					enemies_alive += 1
				elif not enemy.has_method("is_alive"):
					enemies_alive += 1

	if enemies_alive == 0:
		_end_round(player_team)
		return true

	# 爆弾関連
	if is_bomb_planted:
		# 爆弾タイマーは別途管理
		pass

	return false


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
	var sm = _get_squad_manager()
	if not sm:
		return

	var events = get_node_or_null("/root/GameEvents")

	if winner == player_team:
		# 勝利報酬
		sm.add_money_to_all(economy_rules.win_reward)
		loss_streak = 0

		if events:
			for data in sm.squad:
				events.reward_granted.emit(data.player_node, economy_rules.win_reward, "round_win")
	else:
		# 敗北報酬（連敗ボーナス）
		var loss_reward: int = economy_rules.calculate_loss_reward(loss_streak)
		sm.add_money_to_all(loss_reward)
		loss_streak += 1

		if events:
			for data in sm.squad:
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
func _on_unit_killed(killer: Node3D, _victim: Node3D, weapon_id: int) -> void:
	var sm = _get_squad_manager()

	# 敵がキルされた場合、キル報酬
	if sm and killer:
		var killer_data = sm.get_player_data_by_node(killer)
		if killer_data:
			var reward: int = economy_rules.get_kill_reward(weapon_id)
			killer_data.add_money(reward)
			killer_data.record_kill()

			if has_node("/root/GameEvents"):
				get_node("/root/GameEvents").reward_granted.emit(killer, reward, "kill")

	# 全プレイヤー死亡チェック
	if sm and sm.get_alive_count() == 0:
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

	if enemies_alive == 0 and is_playing():
		_end_round(player_team)


## 爆弾設置イベント処理
func _on_bomb_planted(_site: String, planter: Node3D) -> void:
	is_bomb_planted = true
	remaining_time = economy_rules.bomb_time

	# 設置者に報酬
	var sm = _get_squad_manager()
	if sm and planter:
		var data = sm.get_player_data_by_node(planter)
		if data:
			data.add_money(economy_rules.bomb_plant_reward)

			if has_node("/root/GameEvents"):
				get_node("/root/GameEvents").reward_granted.emit(
					planter, economy_rules.bomb_plant_reward, "bomb_plant"
				)


## 爆弾解除イベント処理
func _on_bomb_defused(defuser: Node3D) -> void:
	# 解除者に報酬
	var sm = _get_squad_manager()
	if sm and defuser:
		var data = sm.get_player_data_by_node(defuser)
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


## 戦略フェーズかどうか
func is_strategy_phase() -> bool:
	return current_state == MatchState.STRATEGY_PHASE


## 実行フェーズかどうか
func is_execution_phase() -> bool:
	return current_state == MatchState.EXECUTION_PHASE


## プレイ中かどうか（戦略or実行フェーズ）
func is_playing() -> bool:
	return current_state in [MatchState.STRATEGY_PHASE, MatchState.EXECUTION_PHASE]


## パス描画が可能かどうか
func can_draw_path() -> bool:
	return current_state == MatchState.STRATEGY_PHASE


## 移動実行が可能かどうか
func can_execute_movement() -> bool:
	return current_state == MatchState.EXECUTION_PHASE


## 現在のフェーズ名を取得
func get_phase_name() -> String:
	match current_state:
		MatchState.WAITING:
			return "待機中"
		MatchState.BUY_PHASE:
			return "購入"
		MatchState.STRATEGY_PHASE:
			return "戦略"
		MatchState.EXECUTION_PHASE:
			return "実行"
		MatchState.ROUND_END:
			return "終了"
		MatchState.MATCH_OVER:
			return "試合終了"
		_:
			return ""
