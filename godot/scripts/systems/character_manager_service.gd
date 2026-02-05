extends Node
class_name CharacterManagerService

## キャラクター管理サービス
## キャラクターの登録・検索・フィルタリングを一元管理
## GameManagerから抽出されたコンポーネント

## シグナル
signal character_registered(character: Node)
signal character_unregistered(character: Node)

## キャラクターリスト
var characters: Array[Node] = []

## マルチプレイヤー状態（外部から設定）
var _is_multiplayer_mode: bool = false
var _local_peer_id: int = 0


## マルチプレイヤーモードを設定
func set_multiplayer_mode(enabled: bool, local_peer_id: int = 0) -> void:
	_is_multiplayer_mode = enabled
	_local_peer_id = local_peer_id


## キャラクターを登録
func register_character(character: Node) -> bool:
	if characters.has(character):
		return false

	characters.append(character)
	character_registered.emit(character)
	return true


## キャラクターを登録解除
func unregister_character(character: Node) -> bool:
	if not characters.has(character):
		return false

	characters.erase(character)
	character_unregistered.emit(character)
	return true


## キャラクターを登録（マルチプレイヤー対応）
func register_character_with_network(
	character: Node,
	owner_peer_id: int = 0,
	network_id: int = 0
) -> bool:
	var game_char := character as GameCharacter
	if game_char:
		game_char.owner_peer_id = owner_peer_id
		game_char.network_id = network_id

	return register_character(character)


## キャラクターがローカルプレイヤーのものか判定
func is_local_character(character: Node) -> bool:
	if not _is_multiplayer_mode:
		return true  # シングルプレイヤーモードでは全てローカル

	var game_char := character as GameCharacter
	if game_char:
		return game_char.is_local()

	return true  # GameCharacterでない場合はローカル扱い


## キャラクターに対する操作権限があるか判定
func has_control_permission(character: Node) -> bool:
	# ローカルキャラクターでなければ操作不可
	if not is_local_character(character):
		return false

	# 敵キャラクターは操作不可
	if PlayerState.is_enemy(character):
		return false

	return true


## ネットワークIDからキャラクターを検索
func find_character_by_network_id(network_id: int) -> GameCharacter:
	for character in characters:
		var game_char := character as GameCharacter
		if game_char and game_char.network_id == network_id:
			return game_char
	return null


## peer_idからキャラクターを検索（複数可）
func find_characters_by_owner(owner_peer_id: int) -> Array[GameCharacter]:
	var result: Array[GameCharacter] = []
	for character in characters:
		var game_char := character as GameCharacter
		if game_char and game_char.owner_peer_id == owner_peer_id:
			result.append(game_char)
	return result


## ローカルキャラクターのみをフィルタリング
func filter_local_characters(chars: Array = []) -> Array[Node]:
	var source := chars if chars.size() > 0 else characters
	var result: Array[Node] = []
	for character in source:
		if is_local_character(character):
			result.append(character)
	return result


## リモートキャラクターのみをフィルタリング
func filter_remote_characters(chars: Array = []) -> Array[Node]:
	var source := chars if chars.size() > 0 else characters
	var result: Array[Node] = []
	for character in source:
		if not is_local_character(character):
			result.append(character)
	return result


## ローカルプレイヤーの味方キャラクター一覧を取得
func get_local_friendly_characters() -> Array[Node]:
	var result: Array[Node] = []
	for character in characters:
		if is_local_character(character) and PlayerState.is_friendly(character):
			result.append(character)
	return result


## リモートプレイヤーのキャラクター一覧を取得
func get_remote_characters() -> Array[Node]:
	return filter_remote_characters()


## 全キャラクターの状態をスナップショットとして取得
func get_all_character_snapshots() -> Array[SyncState.CharacterSnapshot]:
	var result: Array[SyncState.CharacterSnapshot] = []
	for character in characters:
		var game_char := character as GameCharacter
		if game_char:
			result.append(game_char.to_character_snapshot())
	return result


## キャラクター数を取得
func get_character_count() -> int:
	return characters.size()


## 全キャラクターを取得
func get_all_characters() -> Array[Node]:
	return characters.duplicate()


## キャラクターを含むか判定
func has_character(character: Node) -> bool:
	return characters.has(character)


## 全キャラクターをクリア（登録解除シグナルは発火しない）
func clear_all() -> void:
	characters.clear()
