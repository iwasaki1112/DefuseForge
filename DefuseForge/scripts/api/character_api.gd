class_name CharacterAPI
extends RefCounted

## CharacterAPI - キャラクター操作の統一API
## CharacterBaseインスタンスの生成、配置、アニメーション操作を提供

# ======================
# Constants
# ======================

## キャラクタープリセット（現在は未使用）
enum Preset {
	PLAYER,
	ENEMY,
	ALLY
}

## プリセットシーンパス（シーン削除済み - 現在は未使用）
const PRESET_PATHS := {}

## プリセット別チーム（現在は未使用）
const PRESET_TEAMS := {}

## アニメーション共有マッピング（同じリグを使用するキャラクター）
## All characters use vanguard's animations (same ARP rig)
const ANIMATION_SOURCE := {
	"shade": "vanguard",
	"phantom": "vanguard"
}

## キャラクターディレクトリ
const CHARACTERS_DIR := "res://assets/characters/"

## 表示するアニメーション名（優先順）
const PREFERRED_ANIMATIONS: Array[String] = [
	"idle",
	"walk",
	"run",
	"e01-walk-f-loop_remap",
	"c12-run-f-loop_remap",
]

## フォールバック用キーワード
const FALLBACK_KEYWORDS := {
	"idle": ["idle"],
	"walk": ["walk"],
	"run": ["run", "sprint"],
}


# ======================
# Character Creation
# ======================

## キャラクターをプリセットから生成
## @param preset: Preset enum値 または 文字列（"player", "enemy", "ally"）
## @param weapon_id: 武器ID（WeaponRegistry.WeaponId）
## @return: CharacterBase、失敗時はnull
static func create_from_preset(preset, weapon_id: int = WeaponRegistry.WeaponId.NONE) -> CharacterBase:
	var preset_enum: int = _resolve_preset(preset)

	if not PRESET_PATHS.has(preset_enum):
		push_error("[CharacterAPI] Unknown preset: %s" % str(preset))
		return null

	var scene_path: String = PRESET_PATHS[preset_enum]
	if not ResourceLoader.exists(scene_path):
		push_error("[CharacterAPI] Preset scene not found: %s" % scene_path)
		return null

	var scene = load(scene_path)
	if scene == null:
		push_error("[CharacterAPI] Failed to load preset scene: %s" % scene_path)
		return null

	var character: CharacterBase = scene.instantiate()
	if character == null:
		push_error("[CharacterAPI] Failed to instantiate character from: %s" % scene_path)
		return null

	# 武器を設定
	if weapon_id != WeaponRegistry.WeaponId.NONE:
		# _ready後に設定する必要があるため、call_deferredを使用
		character.set_deferred("_pending_weapon_id", weapon_id)
		character.ready.connect(func():
			if character.has_method("set_weapon"):
				character.set_weapon(weapon_id)
		, CONNECT_ONE_SHOT)

	print("[CharacterAPI] Created character from preset: %s" % PRESET_PATHS[preset_enum])
	return character


## キャラクターをカスタムモデルから生成
## @param team: チーム名（"player" or "enemies"）
## @param weapon_id: 武器ID（WeaponRegistry.WeaponId）
## @param model_path: GLBモデルパス
## @return: CharacterBase、失敗時はnull
static func create(
	team: String = "player",
	weapon_id: int = WeaponRegistry.WeaponId.NONE,
	model_path: String = ""
) -> CharacterBase:
	# プリセットを決定
	var preset_enum: int = Preset.PLAYER if team == "player" else Preset.ENEMY

	# 基本シーンをインスタンス化
	var character := create_from_preset(preset_enum, weapon_id)
	if character == null:
		return null

	# カスタムモデルが指定されている場合は差し替え
	if not model_path.is_empty():
		character.ready.connect(func():
			_replace_model(character, model_path)
		, CONNECT_ONE_SHOT)

	return character


## キャラクターをシーンに配置
## @param character: 配置するキャラクター
## @param parent: 親ノード
## @param position: 配置位置
## @param rotation_y: Y軸回転（ラジアン）
static func spawn(
	character: CharacterBase,
	parent: Node,
	position: Vector3,
	rotation_y: float = 0.0
) -> void:
	if character == null:
		push_error("[CharacterAPI] Cannot spawn null character")
		return

	if parent == null:
		push_error("[CharacterAPI] Cannot spawn to null parent")
		return

	parent.add_child(character)
	character.global_position = position
	character.rotation.y = rotation_y

	print("[CharacterAPI] Spawned character at %s" % str(position))


# ======================
# Animation API
# ======================

## 利用可能なアニメーション一覧を取得
## @param character: 対象キャラクター
## @param filtered: trueの場合、優先アニメーションのみ返す
## @return: アニメーション名の配列
static func get_available_animations(character: CharacterBase, filtered: bool = true) -> Array[String]:
	if character == null:
		return []

	var all_anims: PackedStringArray = PackedStringArray()

	# AnimationComponentから取得を試みる
	if character.animation and character.animation.has_method("get_animation_list"):
		all_anims = character.animation.get_animation_list()
	elif character.model:
		var anim_player = _find_animation_player(character.model)
		if anim_player:
			all_anims = anim_player.get_animation_list()

	if not filtered:
		var result: Array[String] = []
		for anim in all_anims:
			if anim != "RESET":
				result.append(anim)
		return result

	# フィルタリング
	return _filter_animations(all_anims)


## アニメーションを再生
## @param character: 対象キャラクター
## @param animation_name: アニメーション名
## @param blend_time: ブレンド時間（秒）
static func play_animation(
	character: CharacterBase,
	animation_name: String,
	blend_time: float = 0.3
) -> void:
	if character == null:
		push_warning("[CharacterAPI] Cannot play animation on null character")
		return

	if character.has_method("play_animation"):
		character.play_animation(animation_name, blend_time)
	else:
		push_warning("[CharacterAPI] Character does not have play_animation method")


## キャラクターのアニメーションソースを取得
## @param character_id: キャラクターID
## @return: ソースキャラクターID、マッピングがなければ空文字
static func get_animation_source(character_id: String) -> String:
	return ANIMATION_SOURCE.get(character_id, "")


## キャラクターにアニメーションをコピー（共有リグ用）
## @param character: 対象キャラクター
## @param source_character_id: ソースキャラクターID
static func copy_animations_from(character: CharacterBase, source_character_id: String) -> void:
	if character == null:
		push_warning("[CharacterAPI] Cannot copy animations to null character")
		return

	print("[CharacterAPI] Copying animations from: %s" % source_character_id)

	# ソースキャラクターのGLB/FBXをロード
	var source_path := _get_model_path(source_character_id)
	if source_path.is_empty():
		push_warning("[CharacterAPI] Source character not found: %s" % source_character_id)
		return

	var source_scene = load(source_path)
	if not source_scene:
		push_warning("[CharacterAPI] Failed to load source character: %s" % source_path)
		return

	var source_instance = source_scene.instantiate()
	var source_anim_player = _find_animation_player(source_instance)

	if not source_anim_player:
		push_warning("[CharacterAPI] No AnimationPlayer found in source character")
		source_instance.queue_free()
		return

	# ターゲットのAnimationPlayerを取得/作成
	var target_anim_player = _find_animation_player(character.model)
	if not target_anim_player:
		target_anim_player = AnimationPlayer.new()
		target_anim_player.name = "AnimationPlayer"
		character.model.add_child(target_anim_player)

	# アニメーションをコピー
	var anim_list = source_anim_player.get_animation_list()
	var copied_count := 0

	for anim_name in anim_list:
		if anim_name == "RESET":
			continue
		var anim = source_anim_player.get_animation(anim_name)
		if anim:
			var anim_copy = anim.duplicate()
			var lib_name := ""  # Default library
			if not target_anim_player.has_animation_library(lib_name):
				target_anim_player.add_animation_library(lib_name, AnimationLibrary.new())

			var lib = target_anim_player.get_animation_library(lib_name)
			if lib.has_animation(anim_name):
				lib.remove_animation(anim_name)
			lib.add_animation(anim_name, anim_copy)
			copied_count += 1

	print("[CharacterAPI] Copied %d animations" % copied_count)

	# ソースインスタンスをクリーンアップ
	source_instance.queue_free()

	# AnimationComponentを再セットアップ
	if character.animation and character.model and character.skeleton:
		character.animation.setup(character.model, character.skeleton)


## キャラクターIDに基づいてアニメーションを自動セットアップ
## アニメーションがない場合は共有元からコピー
## @param character: 対象キャラクター
## @param character_id: キャラクターID
static func setup_animations(character: CharacterBase, character_id: String) -> void:
	if character == null:
		return

	# 現在のアニメーションを確認
	var anims := get_available_animations(character, false)

	# アニメーションがない場合、共有元からコピー
	if anims.is_empty():
		var source_id := get_animation_source(character_id)
		if not source_id.is_empty():
			copy_animations_from(character, source_id)


# ======================
# Internal Helpers
# ======================

## プリセット値を解決（文字列またはenum）
static func _resolve_preset(preset) -> int:
	if preset is int:
		return preset

	if preset is String:
		match preset.to_lower():
			"player":
				return Preset.PLAYER
			"enemy", "enemies":
				return Preset.ENEMY
			"ally":
				return Preset.ALLY

	return Preset.PLAYER


## キャラクターIDからモデルパスを取得
static func _get_model_path(character_id: String) -> String:
	var glb_path := CHARACTERS_DIR + character_id + "/" + character_id + ".glb"
	var fbx_path := CHARACTERS_DIR + character_id + "/" + character_id + ".fbx"

	if ResourceLoader.exists(glb_path):
		return glb_path
	if ResourceLoader.exists(fbx_path):
		return fbx_path

	return ""


## AnimationPlayerを再帰検索
static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null

	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found = _find_animation_player(child)
		if found:
			return found
	return null


## アニメーションリストをフィルタリング
static func _filter_animations(all_anims: PackedStringArray) -> Array[String]:
	var result: Array[String] = []

	# 優先アニメーションを先に追加（完全一致）
	for pref_anim in PREFERRED_ANIMATIONS:
		for anim_name in all_anims:
			if anim_name == pref_anim:
				result.append(anim_name)
				break

	# 優先アニメーションが見つからない場合、フォールバックキーワードで検索
	if result.is_empty():
		for category in FALLBACK_KEYWORDS:
			var keywords: Array = FALLBACK_KEYWORDS[category]
			for anim_name in all_anims:
				if anim_name == "RESET":
					continue
				var anim_lower = anim_name.to_lower()
				var found := false
				for keyword in keywords:
					if keyword in anim_lower:
						result.append(anim_name)
						found = true
						break
				if found:
					break

	return result


## キャラクターのモデルを差し替え
static func _replace_model(character: CharacterBase, model_path: String) -> void:
	if not ResourceLoader.exists(model_path):
		push_warning("[CharacterAPI] Model not found: %s" % model_path)
		return

	# 古いモデルを削除
	if character.model:
		character.remove_child(character.model)
		character.model.queue_free()

	# 新しいモデルをロード
	var new_scene = load(model_path)
	if not new_scene:
		push_warning("[CharacterAPI] Failed to load model: %s" % model_path)
		return

	var new_model = new_scene.instantiate()
	new_model.name = "CharacterModel"
	character.add_child(new_model)

	# CharacterBaseを再セットアップ
	character.model = new_model
	character._find_model_and_skeleton()
	character._setup_components()

	# キャラクターIDを検出してアニメーションをセットアップ
	var character_id := CharacterRegistry.detect_character_id_from_scene_path(model_path)
	if not character_id.is_empty():
		setup_animations(character, character_id)

	print("[CharacterAPI] Replaced model with: %s" % model_path)
