extends Node
class_name PlayerStateClass
## Player state management (Autoload)
## Manages the player's team and provides utility functions for team-based logic
## Supports multiplayer preparation with peer_id-based state management

# ============================================
# Constants
# ============================================
# ============================================
# Signals
# ============================================
signal team_changed(new_team: GameCharacter.Team)
signal player_state_changed(peer_id: int)  ## マルチプレイヤー用

# ============================================
# State
# ============================================
var _player_team: GameCharacter.Team = GameCharacter.Team.COUNTER_TERRORIST

## ローカルプレイヤーのpeer_id（マルチプレイヤー用、シングルプレイ時は0）
var _local_peer_id: int = 0

## 全プレイヤーの状態（peer_id -> SyncState.PlayerStateData）
## マルチプレイヤー時に使用
var _players: Dictionary = {}

# ============================================
# Team API
# ============================================

## Get player's current team
func get_player_team() -> GameCharacter.Team:
	return _player_team


## Set player's team
func set_player_team(team: GameCharacter.Team) -> void:
	if _player_team == team:
		return
	_player_team = team
	team_changed.emit(team)


## Get team name as string
func get_team_name(team: GameCharacter.Team = _player_team) -> String:
	match team:
		GameCharacter.Team.COUNTER_TERRORIST:
			return "CT"
		GameCharacter.Team.TERRORIST:
			return "T"
		_:
			return "NONE"


# ============================================
# Character Classification
# ============================================

## Check if a character is friendly (same team as player)
func is_friendly(character: Node) -> bool:
	var game_char := character as GameCharacter
	if not game_char:
		return false
	return game_char.team == _player_team


## Check if a character is enemy (different team from player)
func is_enemy(character: Node) -> bool:
	var game_char := character as GameCharacter
	if not game_char:
		return false
	return game_char.team != _player_team and game_char.team != GameCharacter.Team.NONE


## Get all friendly characters from a list
func filter_friendlies(characters: Array) -> Array[Node]:
	var result: Array[Node] = []
	for character in characters:
		if is_friendly(character):
			result.append(character)
	return result


## Get all enemy characters from a list
func filter_enemies(characters: Array) -> Array[Node]:
	var result: Array[Node] = []
	for character in characters:
		if is_enemy(character):
			result.append(character)
	return result


# ============================================
# Multiplayer API
# ============================================

## ローカルプレイヤーのpeer_idを設定
func set_local_peer_id(peer_id: int) -> void:
	_local_peer_id = peer_id
	# ローカルプレイヤーのエントリがなければ作成
	if peer_id != 0 and not _players.has(peer_id):
		var player_data := SyncState.PlayerStateData.new(peer_id)
		player_data.team = _player_team
		_players[peer_id] = player_data


## ローカルプレイヤーのpeer_idを取得
func get_local_peer_id() -> int:
	return _local_peer_id


## プレイヤーを登録（マルチプレイヤー用）
func register_player(peer_id: int, player_name: String = "") -> SyncState.PlayerStateData:
	if _players.has(peer_id):
		return _players[peer_id]

	var player_data := SyncState.PlayerStateData.new(peer_id, player_name)
	_players[peer_id] = player_data
	player_state_changed.emit(peer_id)
	return player_data


## プレイヤーを登録解除
func unregister_player(peer_id: int) -> void:
	if _players.has(peer_id):
		_players.erase(peer_id)
		player_state_changed.emit(peer_id)


## プレイヤー状態を取得
func get_player_state(peer_id: int) -> SyncState.PlayerStateData:
	return _players.get(peer_id, null)


## 全プレイヤー状態を取得
func get_all_player_states() -> Dictionary:
	return _players


## プレイヤーが登録済みか確認
func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)


## チーム別のプレイヤー数を取得
func get_team_player_count(team: GameCharacter.Team) -> int:
	var count := 0
	for peer_id in _players:
		var state: SyncState.PlayerStateData = _players[peer_id]
		if state.team == team:
			count += 1
	return count


## 全プレイヤーが準備完了か確認
func are_all_players_ready() -> bool:
	if _players.is_empty():
		return false
	for peer_id in _players:
		var state: SyncState.PlayerStateData = _players[peer_id]
		if not state.is_ready:
			return false
	return true


## プレイヤー状態をリセット（新規ゲーム時）
func reset_all_players() -> void:
	for peer_id in _players:
		var state: SyncState.PlayerStateData = _players[peer_id]
		state.is_ready = false
		state.wins = 0
		state.losses = 0
		state.loss_streak = 0
		player_state_changed.emit(peer_id)


# ============================================
# Serialization API
# ============================================

## ローカルプレイヤーの状態をDictionaryに変換
func to_dict() -> Dictionary:
	return {
		"player_team": _player_team,
		"local_peer_id": _local_peer_id,
	}


## Dictionaryから状態を復元
func from_dict(data: Dictionary) -> void:
	if data.has("player_team"):
		set_player_team(data.player_team)
	if data.has("local_peer_id"):
		_local_peer_id = data.local_peer_id


## ローカルプレイヤーの状態をSyncState.PlayerStateDataとして取得
func to_player_state_data() -> SyncState.PlayerStateData:
	var data := SyncState.PlayerStateData.new(_local_peer_id)
	data.team = _player_team
	return data


## SyncState.PlayerStateDataからローカル状態を更新
func from_player_state_data(data: SyncState.PlayerStateData) -> void:
	if data.peer_id == _local_peer_id or _local_peer_id == 0:
		set_player_team(data.team as GameCharacter.Team)


## マルチプレイヤーセッションをクリア（ゲーム終了時）
func clear_multiplayer_session() -> void:
	_players.clear()
	_local_peer_id = 0
