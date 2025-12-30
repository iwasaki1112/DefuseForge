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

# プレイヤー選択の判定半径（タップ/クリック時）
const PLAYER_SELECTION_RADIUS: float = 1.5


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
	# 購入フェーズかどうかをMatchManagerに確認
	if GameManager and GameManager.match_manager:
		if not GameManager.match_manager.is_buy_phase():
			return false

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
	# 購入フェーズかどうかをMatchManagerに確認
	if GameManager and GameManager.match_manager:
		if not GameManager.match_manager.is_buy_phase():
			return false

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


## 位置からプレイヤーを検索して選択（成功時true）
## 既に選択中のプレイヤーがその位置にいる場合はfalseを返す（選択変更なし）
func find_and_select_player_at_position(world_pos: Vector3) -> bool:
	var closest_index: int = -1
	var closest_distance: float = PLAYER_SELECTION_RADIUS

	for i in range(squad.size()):
		var data = squad[i]
		if not data.is_alive or not data.player_node:
			continue
		var dist := world_pos.distance_to(data.player_node.global_position)
		if dist < closest_distance:
			closest_distance = dist
			closest_index = i

	if closest_index >= 0 and closest_index != selected_index:
		select_player(closest_index)
		return true

	return false


## 位置にプレイヤーがいるか確認（選択せずに確認のみ）
func get_player_at_position(world_pos: Vector3) -> Node3D:
	var closest_player: Node3D = null
	var closest_distance: float = PLAYER_SELECTION_RADIUS

	for data in squad:
		if not data.is_alive or not data.player_node:
			continue
		var dist := world_pos.distance_to(data.player_node.global_position)
		if dist < closest_distance:
			closest_distance = dist
			closest_player = data.player_node

	return closest_player


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


## 武器購入（価格ベース、非推奨 - 後方互換性のためのみ維持）
## 警告: この関数はPlayerDataの武器情報を更新しません
## 代わりにbuy_weapon_for_selected()またはbuy_weapon_for_player()を使用してください
func buy_weapon_by_price(price: int) -> bool:
	push_warning("[SquadManager] buy_weapon_by_price(price) is deprecated. Use buy_weapon_for_selected(weapon_id) instead.")
	# 購入フェーズかどうかをMatchManagerに確認
	if GameManager and GameManager.match_manager:
		if not GameManager.match_manager.is_buy_phase():
			return false

	var data = get_selected_player()
	if data and data.money >= price:
		data.money -= price
		squad_money_changed.emit(get_total_money())
		return true

	return false


## プレイヤーダメージ（特定プレイヤー）
## プレイヤーノードのtake_damage()を呼び出す（CharacterBaseとPlayerDataの両方が更新される）
func damage_player_node(player_node: Node3D, amount: float) -> void:
	if player_node == null:
		return

	# プレイヤーノードのtake_damage()を呼ぶ（CharacterBase→Player.take_damage()がPlayerDataも同期）
	if player_node.has_method("take_damage"):
		player_node.take_damage(amount)
		# 注: 死亡処理はPlayer._on_player_died()経由でon_player_died()が呼ばれる
	else:
		# フォールバック: PlayerDataのみ更新（非推奨パス）
		push_warning("[SquadManager] player_node has no take_damage method, falling back to PlayerData only")
		var data = get_player_data_by_node(player_node)
		if data == null:
			return
		data.take_damage(amount)
		if not data.is_alive:
			on_player_died(player_node)
			# GameEvents経由でイベント発火
			if has_node("/root/GameEvents"):
				get_node("/root/GameEvents").unit_killed.emit(null, player_node, 0)


## プレイヤーダメージ（選択中プレイヤー）
func damage_selected_player(amount: float) -> void:
	var selected = get_selected_player_node()
	if selected:
		damage_player_node(selected, amount)


## デバッグ情報を出力
func print_squad_status() -> void:
	print("[SquadManager] === Squad Status ===")
	for i in range(squad.size()):
		var marker = " * " if i == selected_index else "   "
		print("%s%s" % [marker, squad[i].get_debug_string()])
	print("[SquadManager] Total money: $%d, Alive: %d/%d" % [
		get_total_money(), get_alive_count(), squad.size()
	])
