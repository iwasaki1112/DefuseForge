class_name WeaponDatabase
extends Resource

## 武器データベース
## 全武器データを一元管理し、ランタイムでの取得・調整を可能にする
##
## 使用方法:
## 1. .tres ファイルとして保存し、weapons 配列に WeaponResource を追加
## 2. または load_from_directory() で指定ディレクトリから自動読み込み

## 武器リソースの配列
@export var weapons: Array[WeaponResource] = []

## 武器IDからインデックスへのマッピング（高速検索用）
var _id_to_index: Dictionary = {}

## デフォルトの武器リソースディレクトリ
const DEFAULT_WEAPONS_DIR: String = "res://resources/weapons/"


## 初期化（ロード後に呼び出す）
func initialize() -> void:
	_id_to_index.clear()
	for i in range(weapons.size()):
		_id_to_index[weapons[i].weapon_id] = i


## 武器データを取得（文字列ID）
func get_weapon(weapon_id: String) -> WeaponResource:
	if _id_to_index.is_empty():
		initialize()

	var index = _id_to_index.get(weapon_id, -1)
	if index >= 0 and index < weapons.size():
		return weapons[index]
	return null


## 武器データを取得（整数ID - 後方互換性用）
func get_weapon_by_int_id(weapon_id: int) -> WeaponResource:
	# CharacterSetup.WeaponId enumから文字列IDへの変換
	var id_map := {
		0: "",  # NONE
		1: "ak47",
		2: "usp"
	}
	var str_id = id_map.get(weapon_id, "")
	if str_id.is_empty():
		return null
	return get_weapon(str_id)


## 武器データを辞書形式で取得（後方互換性用）
func get_weapon_dict(weapon_id: String) -> Dictionary:
	var weapon = get_weapon(weapon_id)
	if weapon:
		return weapon.to_dict()
	return {}


## 全武器IDを取得
func get_all_weapon_ids() -> Array[String]:
	if _id_to_index.is_empty():
		initialize()

	var ids: Array[String] = []
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
func update_weapon(weapon_id: String, updates: Dictionary) -> bool:
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


## 武器データを更新（整数ID - 後方互換性用）
func update_weapon_by_int_id(weapon_id: int, updates: Dictionary) -> bool:
	var id_map := {
		0: "",  # NONE
		1: "ak47",
		2: "usp"
	}
	var str_id = id_map.get(weapon_id, "")
	if str_id.is_empty():
		return false
	return update_weapon(str_id, updates)


## 指定ディレクトリから武器リソースを読み込み
## @param dir_path: 武器リソースディレクトリ（デフォルト: res://resources/weapons/）
## @return: 読み込んだ武器数
func load_from_directory(dir_path: String = DEFAULT_WEAPONS_DIR) -> int:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_warning("[WeaponDatabase] Cannot open directory: %s" % dir_path)
		return 0

	var loaded_count := 0
	dir.list_dir_begin()
	var folder_name = dir.get_next()

	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			# 各武器フォルダ内の .tres ファイルを探す
			var weapon_dir = dir_path + folder_name + "/"
			var tres_path = weapon_dir + folder_name + ".tres"

			if ResourceLoader.exists(tres_path):
				var weapon_res = load(tres_path) as WeaponResource
				if weapon_res:
					add_weapon(weapon_res)
					loaded_count += 1
		folder_name = dir.get_next()

	dir.list_dir_end()
	return loaded_count


## CharacterSetup.WEAPON_DATAからWeaponDatabaseを作成（後方互換性用）
static func create_from_legacy_data() -> WeaponDatabase:
	var db = WeaponDatabase.new()

	# CharacterSetup.WeaponId enumの値と対応する文字列ID
	var id_map := {
		0: "",  # NONE
		1: "ak47",
		2: "usp"
	}

	for weapon_id in CharacterSetup.WEAPON_DATA.keys():
		var data = CharacterSetup.WEAPON_DATA[weapon_id]
		var str_id = id_map.get(weapon_id, "weapon_%d" % weapon_id)
		var weapon = WeaponResource.from_dict(data, str_id)
		db.weapons.append(weapon)

	db.initialize()
	return db


## シングルトンインスタンス（オプション：Autoloadで使用する場合）
static var _instance: WeaponDatabase = null


## グローバルインスタンスを取得
static func get_instance() -> WeaponDatabase:
	if _instance == null:
		# デフォルトパスから読み込みを試みる
		var default_path = "res://resources/weapon_database.tres"
		if ResourceLoader.exists(default_path):
			_instance = load(default_path) as WeaponDatabase
		if _instance == null:
			_instance = WeaponDatabase.new()
		_instance.initialize()
	return _instance
