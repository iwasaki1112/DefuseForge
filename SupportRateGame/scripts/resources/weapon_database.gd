class_name WeaponDatabase
extends Resource

## 武器データベース
## 全武器データを一元管理し、ランタイムでの取得・調整を可能にする

## 武器リソースの配列
@export var weapons: Array[WeaponResource] = []

## 武器IDからインデックスへのマッピング（高速検索用）
var _id_to_index: Dictionary = {}


## 初期化（ロード後に呼び出す）
func initialize() -> void:
	_id_to_index.clear()
	for i in range(weapons.size()):
		_id_to_index[weapons[i].weapon_id] = i


## 武器データを取得
func get_weapon(weapon_id: int) -> WeaponResource:
	if _id_to_index.is_empty():
		initialize()

	var index = _id_to_index.get(weapon_id, -1)
	if index >= 0 and index < weapons.size():
		return weapons[index]
	return null


## 武器データを辞書形式で取得（後方互換性用）
func get_weapon_dict(weapon_id: int) -> Dictionary:
	var weapon = get_weapon(weapon_id)
	if weapon:
		return weapon.to_dict()
	return {}


## 全武器IDを取得
func get_all_weapon_ids() -> Array[int]:
	if _id_to_index.is_empty():
		initialize()

	var ids: Array[int] = []
	for weapon in weapons:
		ids.append(weapon.weapon_id)
	return ids


## 武器タイプでフィルタして取得
func get_weapons_by_type(weapon_type: int) -> Array[WeaponResource]:
	var result: Array[WeaponResource] = []
	for weapon in weapons:
		if weapon.weapon_type == weapon_type:
			result.append(weapon)
	return result


## 武器データを追加
func add_weapon(weapon: WeaponResource) -> void:
	weapons.append(weapon)
	_id_to_index[weapon.weapon_id] = weapons.size() - 1


## 武器データを更新
func update_weapon(weapon_id: int, updates: Dictionary) -> bool:
	var weapon = get_weapon(weapon_id)
	if not weapon:
		return false

	# 各プロパティを更新
	if updates.has("damage"):
		weapon.damage = updates.damage
	if updates.has("fire_rate"):
		weapon.fire_rate = updates.fire_rate
	if updates.has("accuracy"):
		weapon.accuracy = updates.accuracy
	if updates.has("effective_range"):
		weapon.effective_range = updates.effective_range
	if updates.has("headshot_multiplier"):
		weapon.headshot_multiplier = updates.headshot_multiplier
	if updates.has("bodyshot_multiplier"):
		weapon.bodyshot_multiplier = updates.bodyshot_multiplier
	if updates.has("price"):
		weapon.price = updates.price
	if updates.has("kill_reward"):
		weapon.kill_reward = updates.kill_reward

	return true


## CharacterSetup.WEAPON_DATAからWeaponDatabaseを作成
static func create_from_legacy_data() -> WeaponDatabase:
	var db = WeaponDatabase.new()

	for weapon_id in CharacterSetup.WEAPON_DATA.keys():
		var data = CharacterSetup.WEAPON_DATA[weapon_id]
		var weapon = WeaponResource.from_dict(data, weapon_id)
		db.weapons.append(weapon)

	db.initialize()
	return db
