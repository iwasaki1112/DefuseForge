class_name PlayerData
extends RefCounted

## プレイヤー個別のデータを管理するクラス
## 経済、装備、ステータス、統計を保持

# 基本情報
var player_id: int = 0
var player_name: String = ""
var player_node: Node3D = null  # シーン上のプレイヤーノード参照

# キャラクターカラー（選択リング・パス描画に使用）
var character_color: Color = Color.WHITE

# 3人分のキャラクターカラー定義（3v3）
const CHARACTER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),   # 0: 青
	Color(0.3, 0.9, 0.3),   # 1: 緑
	Color(1.0, 0.9, 0.2),   # 2: 黄
	Color(1.0, 0.5, 0.1),   # 3: オレンジ
	Color(0.7, 0.3, 0.9),   # 4: 紫
]

# 経済（初期値はEconomyRules.starting_moneyと同期すること）
# 注意: 実際の初期化はSquadManager.initialize_squad()でEconomyRulesから取得した値で上書きされる
var money: int = 800  # デフォルト値（EconomyRules.starting_money）

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
	# IDに基づいてキャラクターカラーを設定
	if id >= 0 and id < CHARACTER_COLORS.size():
		character_color = CHARACTER_COLORS[id]
	else:
		character_color = CHARACTER_COLORS[0]


## キャラクターカラーを取得（静的メソッド）
static func get_color_for_id(id: int) -> Color:
	if id >= 0 and id < CHARACTER_COLORS.size():
		return CHARACTER_COLORS[id]
	return CHARACTER_COLORS[0]


## スプリント用の濃い色を取得
func get_sprint_color() -> Color:
	# 彩度を上げ、明度を下げて濃い色にする
	return character_color.darkened(0.3)


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
	# EconomyRulesからstarting_moneyを取得
	var starting_money := 800  # デフォルト値
	if GameManager and GameManager.match_manager and GameManager.match_manager.economy_rules:
		starting_money = GameManager.match_manager.economy_rules.starting_money
	money = starting_money
	primary_weapon = CharacterSetup.WeaponId.NONE
	secondary_weapon = CharacterSetup.WeaponId.NONE
	equipment.clear()
	total_kills = 0
	total_deaths = 0
	total_damage = 0.0
	reset_for_round()


## ダメージを受ける
## 注意: 通常はPlayer.take_damage()を使用してください（CharacterBaseとPlayerDataの両方を更新）
## この関数はPlayerData単体でのダメージ処理用（フォールバック/テスト用）
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
	var max_money := 16000  # デフォルト値（EconomyRules.max_money）
	# MatchManager経由でEconomyRulesからmax_moneyを取得
	if GameManager and GameManager.match_manager and GameManager.match_manager.economy_rules:
		max_money = GameManager.match_manager.economy_rules.max_money
	money = min(money + amount, max_money)


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
