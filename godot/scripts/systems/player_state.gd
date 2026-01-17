extends Node
class_name PlayerStateClass
## Player state management (Autoload)
## Manages the player's team and provides utility functions for team-based logic

# ============================================
# Signals
# ============================================
signal team_changed(new_team: GameCharacter.Team)

# ============================================
# State
# ============================================
var _player_team: GameCharacter.Team = GameCharacter.Team.COUNTER_TERRORIST

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
	print("[PlayerState] Team changed to: %s" % get_team_name(team))


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
