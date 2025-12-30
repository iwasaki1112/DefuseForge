class_name PlayerData
extends RefCounted

## プレイヤー個別のデータを管理するクラス
## 経済、装備、ステータス、統計を保持

# 基本情報
var player_id: int = 0
var player_name: String = ""
var player_node: Node3D = null  # シーン上のプレイヤーノード参照

# 経済
var money: int = 800

# ステータス
var health: float = 100.0
var armor: float = 0.0
var is_alive: bool = true

# 装備
var primary_weapon: int = CharacterSetup.WeaponId.NONE
var secondary_weapon: int = CharacterSetup.WeaponId.NONE
var equipment: Array[int] = []  # グレネードなど

# 統計（ラウンド内）
var kills_this_round: int = 0
var damage_this_round: float = 0.0

# 統計（ゲーム全体）
var total_kills: int = 0
var total_deaths: int = 0
var total_damage: float = 0.0


## 初期化
func _init(id: int = 0, pname: String = "") -> void:
	player_id = id
	player_name = pname


## ラウンド開始時のリセット
func reset_for_round() -> void:
	health = 100.0
	armor = 0.0
	is_alive = true
	kills_this_round = 0
	damage_this_round = 0.0

	# プレイヤーノードも同期
	if player_node and player_node.has_method("reset_stats"):
		player_node.reset_stats()


## ゲーム開始時のフルリセット
func reset_for_game() -> void:
	money = 800
	primary_weapon = CharacterSetup.WeaponId.NONE
	secondary_weapon = CharacterSetup.WeaponId.NONE
	equipment.clear()
	total_kills = 0
	total_deaths = 0
	total_damage = 0.0
	reset_for_round()


## ダメージを受ける
func take_damage(amount: float) -> void:
	# アーマー計算（アーマーは50%のダメージを吸収）
	var actual_damage := amount
	if armor > 0:
		var armor_damage := amount * 0.5
		if armor_damage <= armor:
			armor -= armor_damage
			actual_damage -= armor_damage
		else:
			actual_damage -= armor
			armor = 0

	health -= actual_damage

	if health <= 0:
		health = 0
		is_alive = false
		total_deaths += 1


## 回復
func heal(amount: float) -> void:
	health = min(health + amount, 100.0)


## アーマー追加
func add_armor(amount: float) -> void:
	armor = min(armor + amount, 100.0)


## キル記録
func record_kill() -> void:
	kills_this_round += 1
	total_kills += 1


## ダメージ記録
func record_damage(amount: float) -> void:
	damage_this_round += amount
	total_damage += amount


## お金を追加
func add_money(amount: int) -> void:
	money = min(money + amount, 16000)


## 武器購入
func buy_weapon(weapon_id: int, is_primary: bool = true) -> bool:
	var weapon_data = CharacterSetup.get_weapon_data(weapon_id)
	if money < weapon_data.price:
		return false

	money -= weapon_data.price

	if is_primary:
		primary_weapon = weapon_id
	else:
		secondary_weapon = weapon_id

	return true


## 装備購入
func buy_equipment(equipment_id: int, price: int) -> bool:
	if money < price:
		return false

	money -= price
	equipment.append(equipment_id)
	return true


## 現在の武器IDを取得
func get_current_weapon() -> int:
	if primary_weapon != CharacterSetup.WeaponId.NONE:
		return primary_weapon
	return secondary_weapon


## デバッグ用文字列
func get_debug_string() -> String:
	return "[%d] %s: $%d HP:%.0f Armor:%.0f Alive:%s" % [
		player_id, player_name, money, health, armor, is_alive
	]
