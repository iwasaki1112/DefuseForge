class_name CharacterRegistry
extends RefCounted

## キャラクターID → CharacterResourceの明示的マッピング
## パス推測を排除し、明確なエラーメッセージを提供

static var _cache: Dictionary = {}

## キャラクターID → リソースパスのマッピング
## 新しいキャラクターを追加する場合はここに登録
const CHARACTER_PATHS := {
	"shade": "res://assets/characters/shade/shade.tres",
	"phantom": "res://assets/characters/phantom/phantom.tres",
	"vanguard": "res://assets/characters/vanguard/vanguard.tres"
}


## キャラクターリソースを取得
## @param character_id: キャラクターID（例: "vanguard"）
## @return: CharacterResource、見つからない場合はnull
static func get_character(character_id: String) -> CharacterResource:
	if character_id.is_empty():
		push_error("[CharacterRegistry] character_id is empty")
		return null

	# キャッシュをチェック
	if _cache.has(character_id):
		return _cache[character_id]

	# パスを取得
	var path := _get_resource_path(character_id)
	if path.is_empty():
		# 登録されていない場合、パス推測を試みる（後方互換性）
		path = "res://assets/characters/%s/%s.tres" % [character_id, character_id]
		push_warning("[CharacterRegistry] character_id '%s' not in CHARACTER_PATHS. Trying fallback: %s" % [character_id, path])

	# リソースの存在確認
	if not ResourceLoader.exists(path):
		push_error("[CharacterRegistry] Resource not found: %s" % path)
		return null

	# リソースをロード
	var resource = load(path)
	if resource == null:
		push_error("[CharacterRegistry] Failed to load resource: %s" % path)
		return null

	# 型チェック
	if not resource is CharacterResource:
		push_error("[CharacterRegistry] Resource is not CharacterResource: %s (type: %s)" % [path, resource.get_class()])
		return null

	# キャッシュに保存
	_cache[character_id] = resource
	return resource


## キャラクターIDからリソースパスを取得
## @param character_id: キャラクターID
## @return: リソースパス、マッピングがない場合は空文字列
static func _get_resource_path(character_id: String) -> String:
	return CHARACTER_PATHS.get(character_id, "")


## モデルのシーンパスからキャラクターIDを抽出
## 例: "res://assets/characters/vanguard/vanguard.glb" → "vanguard"
## @param scene_path: GLBファイルパス
## @return: キャラクターID、抽出できない場合は空文字列
static func detect_character_id_from_scene_path(scene_path: String) -> String:
	if scene_path.is_empty():
		return ""

	# パスを分割して親ディレクトリ名を取得
	# 例: res://assets/characters/vanguard/vanguard.glb
	#     → ["res:", "", "assets", "characters", "vanguard", "vanguard.glb"]
	#     → "vanguard"（インデックス -2）
	var parts = scene_path.split("/")
	if parts.size() >= 2:
		return parts[parts.size() - 2]

	return ""


## 全ての登録済みキャラクターIDを取得
## @return: 登録済みのcharacter_id配列
static func get_all_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in CHARACTER_PATHS.keys():
		ids.append(id)
	return ids


## キャラクターが登録されているかチェック
## @param character_id: キャラクターID
## @return: 登録されていればtrue
static func has_character(character_id: String) -> bool:
	return CHARACTER_PATHS.has(character_id)


## キャッシュをクリア（主にテスト用）
static func clear_cache() -> void:
	_cache.clear()


## 全キャラクターリソースをバリデート
## @return: { "valid": bool, "errors": Array[String] }
static func validate_all() -> Dictionary:
	var all_errors: Array[String] = []

	for character_id in get_all_character_ids():
		var resource = get_character(character_id)
		if resource == null:
			all_errors.append("character_id='%s': Failed to load resource" % character_id)
			continue

		# 基本的なバリデーション
		if resource.character_id.is_empty():
			all_errors.append("character_id='%s': character_id field is empty" % character_id)

		if resource.model_path.is_empty():
			all_errors.append("character_id='%s': model_path is empty" % character_id)
		elif not ResourceLoader.exists(resource.model_path):
			all_errors.append("character_id='%s': model_path does not exist: %s" % [character_id, resource.model_path])

	return {
		"valid": all_errors.is_empty(),
		"errors": all_errors
	}
