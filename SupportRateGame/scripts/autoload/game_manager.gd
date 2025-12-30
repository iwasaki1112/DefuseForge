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

# ゲームオブジェクト参照
var enemies: Array[Node3D] = []

# フラグ
var is_game_running: bool = false

# シーン内ノード参照（game.tscn内に配置）
var match_manager: Node = null
var squad_manager: Node = null
var fog_of_war_manager: Node = null


# === 後方互換性プロパティ ===
# 既存コードとの互換性のためプロパティを維持
# 実際の値はMatchManagerまたはSquadManagerから取得

var current_state: GameState:
	get:
		if match_manager:
			match match_manager.current_state:
				0: return GameState.MENU  # WAITING
				1: return GameState.BUY_PHASE
				2: return GameState.PLAYING
				3: return GameState.ROUND_END
				4: return GameState.GAME_OVER
		return GameState.MENU

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
	get_tree().change_scene_to_file("res://scenes/title.tscn")


## シーン遷移: ゲームへ
func goto_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


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


## 武器購入（後方互換性、SquadManager経由）
func buy_weapon(price: int) -> bool:
	if match_manager and not match_manager.is_buy_phase():
		return false

	var data = _get_selected_player_data()
	if data and data.money >= price:
		data.money -= price
		return true

	return false


## キル報酬（後方互換性、GameEvents経由が推奨）
func on_enemy_killed(weapon_id: int = 0) -> void:
	var selected = squad_manager.get_selected_player_node() if squad_manager else null
	if selected and has_node("/root/GameEvents"):
		# enemyは不明なのでnullを渡す
		get_node("/root/GameEvents").unit_killed.emit(selected, null, weapon_id)


## キル報酬（キラー指定版、GameEvents経由が推奨）
func on_enemy_killed_by(killer: Node3D, weapon_id: int = 0) -> void:
	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").unit_killed.emit(killer, null, weapon_id)


## 爆弾設置（GameEvents経由が推奨）
func on_bomb_planted() -> void:
	var selected = squad_manager.get_selected_player_node() if squad_manager else null
	if has_node("/root/GameEvents"):
		get_node("/root/GameEvents").bomb_planted.emit("A", selected)


## プレイヤーダメージ（特定プレイヤー）
func damage_player_node(player_node: Node3D, amount: float) -> void:
	if not squad_manager:
		return

	var data = squad_manager.get_player_data_by_node(player_node)
	if data:
		data.take_damage(amount)
		if not data.is_alive:
			squad_manager.on_player_died(player_node)

			# GameEvents経由でイベント発火
			if has_node("/root/GameEvents"):
				get_node("/root/GameEvents").unit_killed.emit(null, player_node, 0)


## プレイヤーダメージ（選択中プレイヤー、後方互換性）
func damage_player(amount: float) -> void:
	var selected = squad_manager.get_selected_player_node() if squad_manager else null
	if selected:
		damage_player_node(selected, amount)
