extends Node

## ゲームマネージャー（Autoload）
## 責務を限定: シーン遷移、設定、ゲームオブジェクト参照のみ
## ラウンド/経済はMatchManagerに委譲

# 列挙型（後方互換性のため維持）
enum Team { CT, TERRORIST }
enum GameState { MENU, BUY_PHASE, PLAYING, ROUND_END, GAME_OVER }
enum GameMode { DEFUSE, HOSTAGE }

# ゲームモード
var current_mode: GameMode = GameMode.DEFUSE

# フラグ
var is_game_running: bool = false

# オンラインマッチ情報
var is_online_match: bool = false
var current_match_id: String = ""
var is_host: bool = false
var assigned_team: Team = Team.CT  # オンラインマッチで割り当てられたチーム

# デバッグ用設定
var debug_spawn_nearby: bool = false  # キャラクターを近くにスポーンさせる

# シーン内ノード参照（game.tscn内に配置）
var match_manager: Node = null
var squad_manager: Node = null
var fog_of_war_manager: Node = null
var grid_manager: Node = null  # A*パスファインディング用


# === 後方互換性プロパティ ===
# 既存コードとの互換性のためプロパティを維持
# 実際の値はMatchManagerまたはSquadManagerから取得

# フォールバック状態（MatchManagerがない場合に使用）
var _fallback_state: GameState = GameState.MENU

var current_state: GameState:
	get:
		if match_manager:
			# MatchState: WAITING=0, BUY_PHASE=1, STRATEGY_PHASE=2, EXECUTION_PHASE=3, ROUND_END=4, MATCH_OVER=5
			match match_manager.current_state:
				0: return GameState.MENU  # WAITING
				1: return GameState.BUY_PHASE
				2, 3: return GameState.PLAYING  # STRATEGY_PHASE, EXECUTION_PHASE
				4: return GameState.ROUND_END
				5: return GameState.GAME_OVER
		return _fallback_state
	set(value):
		# 注意: MatchManagerが存在する場合、getterはMatchManagerの状態を返すため
		# このsetterで設定した値は無視されます。
		# このsetterはMatchManagerがないテストシーン用のフォールバックです。
		_fallback_state = value

var current_round: int:
	get: return match_manager.current_round if match_manager else 0

var ct_wins: int:
	get: return match_manager.ct_wins if match_manager else 0

var t_wins: int:
	get: return match_manager.t_wins if match_manager else 0

var remaining_time: float:
	get: return match_manager.remaining_time if match_manager else 0.0

var player_team: Team:
	get: return match_manager.player_team if match_manager else Team.CT

var is_bomb_planted: bool:
	get: return match_manager.is_bomb_planted if match_manager else false

var player: Node3D:
	get:
		if squad_manager:
			return squad_manager.get_selected_player_node()
		return null

var player_money: int:
	get:
		var data = _get_selected_player_data()
		return data.money if data else 800

var player_health: float:
	get:
		var data = _get_selected_player_data()
		return data.health if data else 100.0

var player_armor: float:
	get:
		var data = _get_selected_player_data()
		return data.armor if data else 0.0


func _ready() -> void:
	pass


## 選択中のプレイヤーデータを取得（ヘルパー）
func _get_selected_player_data() -> RefCounted:
	if squad_manager:
		return squad_manager.get_selected_player()
	return null


## MatchManagerを登録（game_scene.gdから呼ばれる）
func register_match_manager(manager: Node) -> void:
	match_manager = manager


## MatchManagerを解除
func unregister_match_manager() -> void:
	match_manager = null


## SquadManagerを登録
func register_squad_manager(manager: Node) -> void:
	squad_manager = manager


## SquadManagerを解除
func unregister_squad_manager() -> void:
	squad_manager = null


## FogOfWarManagerを登録
func register_fog_of_war_manager(manager: Node) -> void:
	fog_of_war_manager = manager


## FogOfWarManagerを解除
func unregister_fog_of_war_manager() -> void:
	fog_of_war_manager = null


## GridManagerを登録
func register_grid_manager(manager: Node) -> void:
	grid_manager = manager


## GridManagerを解除
func unregister_grid_manager() -> void:
	grid_manager = null


## ゲームを開始（MatchManagerに委譲）
func start_game(mode: GameMode = GameMode.DEFUSE) -> void:
	current_mode = mode
	is_game_running = true

	if match_manager:
		match_manager.start_match()


## ゲーム停止
func stop_game() -> void:
	is_game_running = false


## シーン遷移: タイトルへ
func goto_title() -> void:
	stop_game()
	_reset_online_state()
	get_tree().change_scene_to_file("res://scenes/title.tscn")


## シーン遷移: ロビーへ
func goto_lobby() -> void:
	stop_game()
	_reset_online_state()
	get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")


## シーン遷移: ゲームへ
func goto_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


## オンライン状態をリセット
func _reset_online_state() -> void:
	is_online_match = false
	current_match_id = ""
	is_host = false
	assigned_team = Team.CT


## フォーマット済み時間を取得（後方互換性）
func get_formatted_time() -> String:
	if match_manager:
		return match_manager.get_formatted_time()
	return "0:00"


# === 後方互換性メソッド（MatchManagerに委譲） ===

func start_new_round() -> void:
	if match_manager:
		match_manager.start_new_round()


func start_playing() -> void:
	if match_manager:
		match_manager.start_playing()


## 武器購入（武器IDベース、推奨）
## SquadManager経由でPlayerDataの武器情報も更新
func buy_weapon_for_selected(weapon_id: int, is_primary: bool = true) -> bool:
	if squad_manager:
		return squad_manager.buy_weapon_for_selected(weapon_id, is_primary)
	return false


## 武器購入（価格ベース、非推奨 - 後方互換性のためのみ維持）
## 警告: この関数はPlayerDataの武器情報を更新しません
## 代わりにbuy_weapon_for_selected()を使用してください
func buy_weapon(price: int) -> bool:
	push_warning("[GameManager] buy_weapon(price) is deprecated. Use buy_weapon_for_selected(weapon_id) instead.")
	if squad_manager:
		return squad_manager.buy_weapon_by_price(price)
	return false


## キル報酬（後方互換性、GameEventsを直接使用）
## 非推奨: GameEvents.unit_killed.emit()を直接使用してください
func on_enemy_killed(weapon_id: int = 0) -> void:
	var selected = squad_manager.get_selected_player_node() if squad_manager else null
	if selected and has_node("/root/GameEvents"):
		get_node("/root/GameEvents").unit_killed.emit(selected, null, weapon_id, false)


## キル報酬（キラー指定版）
## 非推奨: GameEvents.unit_killed.emit()を直接使用してください
func on_enemy_killed_by(killer: Node3D, weapon_id: int = 0) -> void:
	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").unit_killed.emit(killer, null, weapon_id, false)


## 爆弾設置
## 非推奨: GameEvents.bomb_planted.emit()を直接使用してください
func on_bomb_planted() -> void:
	var selected = squad_manager.get_selected_player_node() if squad_manager else null
	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").bomb_planted.emit("A", selected)


## プレイヤーダメージ（特定プレイヤー）
## 非推奨: SquadManager.damage_player_node()を直接使用してください
func damage_player_node(player_node: Node3D, amount: float) -> void:
	if squad_manager:
		squad_manager.damage_player_node(player_node, amount)


## プレイヤーダメージ（選択中プレイヤー）
## 非推奨: SquadManager.damage_selected_player()を直接使用してください
func damage_player(amount: float) -> void:
	if squad_manager:
		squad_manager.damage_selected_player(amount)


## 実行フェーズかどうか
func is_execution_phase() -> bool:
	if match_manager:
		return match_manager.is_execution_phase()
	return false


## 作戦フェーズかどうか
func is_strategy_phase() -> bool:
	if match_manager:
		return match_manager.is_strategy_phase()
	return false
