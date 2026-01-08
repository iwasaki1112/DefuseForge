extends Node

## リソースバリデーター（Autoload）
## デバッグビルド時にゲーム起動時の全リソースをバリデート
## 設定ミスを早期に検出して明確なエラーメッセージを表示

# レジストリを明示的にpreload（class_nameの読み込み順序問題を回避）
const WeaponRegistryClass = preload("res://scripts/registries/weapon_registry.gd")
const CharacterRegistryClass = preload("res://scripts/registries/character_registry.gd")

func _ready() -> void:
	if OS.is_debug_build():
		# 少し遅延させて他のAutoloadが初期化されるのを待つ
		call_deferred("_validate_all_resources")


## 全リソースをバリデート
func _validate_all_resources() -> void:
	print("[ResourceValidator] Validating resources...")
	var total_issues: int = 0

	# 武器リソースをバリデート
	var weapon_result = _validate_weapons()
	total_issues += weapon_result.issue_count

	# キャラクターリソースをバリデート
	var character_result = _validate_characters()
	total_issues += character_result.issue_count

	# 結果サマリー
	if total_issues == 0:
		print("[ResourceValidator] All resources valid")
	else:
		push_warning("[ResourceValidator] Found %d issue(s). Check warnings above." % total_issues)


## 武器リソースをバリデート
func _validate_weapons() -> Dictionary:
	var issues: int = 0

	for weapon_id in WeaponRegistryClass.get_all_weapon_ids():
		var resource = WeaponRegistryClass.get_weapon(weapon_id)
		if resource == null:
			push_warning("[ResourceValidator] Weapon %d: Failed to load resource" % weapon_id)
			issues += 1
			continue

		var result = resource.validate()
		if not result.valid:
			for error in result.errors:
				push_warning("[ResourceValidator] Weapon '%s' (id=%d): %s" % [resource.weapon_name, weapon_id, error])
				issues += 1

	return { "issue_count": issues }


## キャラクターリソースをバリデート
func _validate_characters() -> Dictionary:
	var issues: int = 0

	var result = CharacterRegistryClass.validate_all()
	if not result.valid:
		for error in result.errors:
			push_warning("[ResourceValidator] Character: %s" % error)
			issues += 1

	return { "issue_count": issues }
