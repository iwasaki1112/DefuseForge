class_name SquadManagerNode
extends Node

## 分隊（5体のプレイヤー）を管理するシーンノード
## 各プレイヤーの経済、装備、ステータスを個別管理
## ゲームシーン内に配置して使用（Autoloadではない）

const PlayerDataClass = preload("res://scripts/data/player_data.gd")

# シグナル
signal player_selected(player_data: RefCounted, index: int)
signal player_died(player_data: RefCounted, index: int)
signal all_players_died
signal squad_money_changed(total: int)

# 分隊データ
var squad: Array = []  # Array of PlayerData
var selected_index: int = 0

# 分隊サイズ
const SQUAD_SIZE: int = 5


func _ready() -> void:
	pass


## 分隊を初期化（ゲーム開始時に呼び出す）
func initialize_squad(player_nodes: Array[CharacterBody3D]) -> void:
	squad.clear()

	for i in range(player_nodes.size()):
		var player_node = player_nodes[i]
		var player_data = PlayerDataClass.new(i, player_node.name)
		player_data.player_node = player_node
		squad.append(player_data)

		# プレイヤーノードにデータ参照を設定
		if player_node.has_method("set_player_data"):
			player_node.set_player_data(player_data)

	# 最初のプレイヤーを選択
	if squad.size() > 0:
		select_player(0)

	print("[SquadManager] Initialized with %d players" % squad.size())


## プレイヤーを選択
func select_player(index: int) -> void:
	if index < 0 or index >= squad.size():
		return

	# 死亡したプレイヤーは選択できない
	if not squad[index].is_alive:
		# 次の生存プレイヤーを探す
		var alive_index = _find_next_alive_player(index)
		if alive_index == -1:
			return
		index = alive_index

	selected_index = index
	player_selected.emit(squad[index], index)

	print("[SquadManager] Selected player: %s" % squad[index].player_name)


## 次のプレイヤーを選択
func select_next_player() -> void:
	var next_index = _find_next_alive_player(selected_index)
	if next_index != -1:
		select_player(next_index)


## 前のプレイヤーを選択
func select_previous_player() -> void:
	var prev_index = _find_previous_alive_player(selected_index)
	if prev_index != -1:
		select_player(prev_index)


## 現在選択中のプレイヤーデータを取得
func get_selected_player() -> RefCounted:
	if selected_index >= 0 and selected_index < squad.size():
		return squad[selected_index]
	return null


## 現在選択中のプレイヤーノードを取得
func get_selected_player_node() -> Node3D:
	var data = get_selected_player()
	if data:
		return data.player_node
	return null


## インデックスでプレイヤーデータを取得
func get_player_data(index: int) -> RefCounted:
	if index >= 0 and index < squad.size():
		return squad[index]
	return null


## プレイヤーノードからデータを取得
func get_player_data_by_node(node: Node3D) -> RefCounted:
	for data in squad:
		if data.player_node == node:
			return data
	return null


## プレイヤー死亡処理
func on_player_died(player_node: Node3D) -> void:
	var data = get_player_data_by_node(player_node)
	if data == null:
		return

	data.is_alive = false
	data.health = 0.0
	data.total_deaths += 1

	var index = squad.find(data)
	player_died.emit(data, index)

	print("[SquadManager] Player died: %s" % data.player_name)

	# 全員死亡チェック
	if get_alive_count() == 0:
		all_players_died.emit()
	elif index == selected_index:
		# 選択中のプレイヤーが死亡した場合、次のプレイヤーを選択
		select_next_player()


## 生存プレイヤー数を取得
func get_alive_count() -> int:
	var count := 0
	for data in squad:
		if data.is_alive:
			count += 1
	return count


## 分隊全体のお金を取得
func get_total_money() -> int:
	var total := 0
	for data in squad:
		total += data.money
	return total


## 全員にお金を追加（ラウンド報酬など）
func add_money_to_all(amount: int) -> void:
	for data in squad:
		data.add_money(amount)
	squad_money_changed.emit(get_total_money())


## ラウンド開始時のリセット
func reset_for_round() -> void:
	for data in squad:
		data.reset_for_round()

	# 最初の生存プレイヤーを選択
	selected_index = 0
	select_player(0)

	print("[SquadManager] Reset for round - %d players alive" % get_alive_count())


## ゲーム開始時のフルリセット
func reset_for_game() -> void:
	for data in squad:
		data.reset_for_game()

	selected_index = 0
	if squad.size() > 0:
		select_player(0)

	print("[SquadManager] Reset for game")


## 武器購入（選択中のプレイヤー）
func buy_weapon_for_selected(weapon_id: int, is_primary: bool = true) -> bool:
	var data = get_selected_player()
	if data == null:
		return false

	var success = data.buy_weapon(weapon_id, is_primary)
	if success:
		# プレイヤーノードに武器を反映
		if data.player_node and data.player_node.has_method("equip_weapon"):
			data.player_node.equip_weapon(weapon_id)
		squad_money_changed.emit(get_total_money())

	return success


## 特定プレイヤーの武器購入
func buy_weapon_for_player(index: int, weapon_id: int, is_primary: bool = true) -> bool:
	var data = get_player_data(index)
	if data == null:
		return false

	var success = data.buy_weapon(weapon_id, is_primary)
	if success:
		if data.player_node and data.player_node.has_method("equip_weapon"):
			data.player_node.equip_weapon(weapon_id)
		squad_money_changed.emit(get_total_money())

	return success


## キル報酬を付与
func award_kill(killer_node: Node3D, weapon_id: int) -> void:
	var data = get_player_data_by_node(killer_node)
	if data == null:
		return

	data.record_kill()

	var weapon_data = CharacterSetup.get_weapon_data(weapon_id)
	data.add_money(weapon_data.kill_reward)
	squad_money_changed.emit(get_total_money())


## 次の生存プレイヤーを探す
func _find_next_alive_player(from_index: int) -> int:
	for i in range(1, squad.size() + 1):
		var check_index = (from_index + i) % squad.size()
		if squad[check_index].is_alive:
			return check_index
	return -1


## 前の生存プレイヤーを探す
func _find_previous_alive_player(from_index: int) -> int:
	for i in range(1, squad.size() + 1):
		var check_index = (from_index - i + squad.size()) % squad.size()
		if squad[check_index].is_alive:
			return check_index
	return -1


## 全プレイヤーのノード配列を取得
func get_all_player_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for data in squad:
		if data.player_node:
			nodes.append(data.player_node)
	return nodes


## 生存プレイヤーのノード配列を取得
func get_alive_player_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for data in squad:
		if data.is_alive and data.player_node:
			nodes.append(data.player_node)
	return nodes


## デバッグ情報を出力
func print_squad_status() -> void:
	print("[SquadManager] === Squad Status ===")
	for i in range(squad.size()):
		var marker = " * " if i == selected_index else "   "
		print("%s%s" % [marker, squad[i].get_debug_string()])
	print("[SquadManager] Total money: $%d, Alive: %d/%d" % [
		get_total_money(), get_alive_count(), squad.size()
	])
