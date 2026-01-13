class_name WeaponRegistry
extends RefCounted

## 武器ID → WeaponResourceの明示的マッピング
## パス推測を排除し、明確なエラーメッセージを提供

## 武器ID定数（CharacterSetupから移動）
enum WeaponId {
	NONE = 0,
	AK47 = 1,
	M4A1 = 2
}

## 武器タイプ定数
enum WeaponType {
	NONE = 0,
	RIFLE = 1,
	PISTOL = 2
}

static var _cache: Dictionary = {}

## 武器ID → リソースパスのマッピング
## 新しい武器を追加する場合はここに登録
const WEAPON_PATHS := {
	WeaponId.NONE: "",
	WeaponId.AK47: "res://assets/weapons/ak47/ak47.tres",
	WeaponId.M4A1: "res://assets/weapons/m4a1/m4a1.tres"
}


## 武器リソースを取得
## @param weapon_id: WeaponId enum値
## @return: WeaponResource、見つからない場合はnull
static func get_weapon(weapon_id: int) -> WeaponResource:
	# NONEの場合はnullを返す（エラーではない）
	if weapon_id == WeaponId.NONE:
		return null

	# キャッシュをチェック
	if _cache.has(weapon_id):
		return _cache[weapon_id]

	# パスを取得
	var path := _get_resource_path(weapon_id)
	if path.is_empty():
		push_error("[WeaponRegistry] Unknown weapon_id: %d. Add it to WEAPON_PATHS." % weapon_id)
		return null

	# リソースの存在確認
	if not ResourceLoader.exists(path):
		push_error("[WeaponRegistry] Resource not found: %s" % path)
		return null

	# リソースをロード
	var resource = load(path)
	if resource == null:
		push_error("[WeaponRegistry] Failed to load resource: %s" % path)
		return null

	# 型チェック
	if not resource is WeaponResource:
		push_error("[WeaponRegistry] Resource is not WeaponResource: %s (type: %s)" % [path, resource.get_class()])
		return null

	# キャッシュに保存
	_cache[weapon_id] = resource
	print("[WeaponRegistry] Loaded: %s (weapon_id=%d)" % [path, weapon_id])
	return resource


## 武器IDからリソースパスを取得
## @param weapon_id: WeaponId enum値
## @return: リソースパス、マッピングがない場合は空文字列
static func _get_resource_path(weapon_id: int) -> String:
	return WEAPON_PATHS.get(weapon_id, "")


## 全ての登録済み武器IDを取得
## @return: 登録済みのWeaponId配列（NONEを除く）
static func get_all_weapon_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in WEAPON_PATHS.keys():
		if id != WeaponId.NONE:
			ids.append(id)
	return ids


## 武器が登録されているかチェック
## @param weapon_id: WeaponId enum値
## @return: 登録されていればtrue
static func has_weapon(weapon_id: int) -> bool:
	if weapon_id == WeaponId.NONE:
		return true  # NONEは常に有効
	return WEAPON_PATHS.has(weapon_id) and not WEAPON_PATHS[weapon_id].is_empty()


## キャッシュをクリア（主にテスト用）
static func clear_cache() -> void:
	_cache.clear()
	print("[WeaponRegistry] Cache cleared")


## 全武器リソースをバリデート
## @return: { "valid": bool, "errors": Array[String] }
static func validate_all() -> Dictionary:
	var all_errors: Array[String] = []

	for weapon_id in get_all_weapon_ids():
		var resource = get_weapon(weapon_id)
		if resource == null:
			all_errors.append("weapon_id=%d: Failed to load resource" % weapon_id)
			continue

		if resource.has_method("validate"):
			var result = resource.validate()
			if not result.valid:
				for error in result.errors:
					all_errors.append("weapon_id=%d (%s): %s" % [weapon_id, resource.weapon_name, error])

	return {
		"valid": all_errors.is_empty(),
		"errors": all_errors
	}
