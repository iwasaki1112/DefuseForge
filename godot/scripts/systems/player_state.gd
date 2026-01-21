extends Node
class_name PlayerStateClass
## Player state management (Autoload)
## Manages the player's team and provides utility functions for team-based logic

# ============================================
# Constants
# ============================================
const INITIAL_MONEY: int = 99999  ## 初期資金（ゲーム開始時）※デバッグ用

# ============================================
# Signals
# ============================================
signal team_changed(new_team: GameCharacter.Team)
signal money_changed(new_amount: int)

# ============================================
# State
# ============================================
var _player_team: GameCharacter.Team = GameCharacter.Team.COUNTER_TERRORIST
var _money: int = INITIAL_MONEY

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


# ============================================
# Money API
# ============================================

## Get current money
func get_money() -> int:
	return _money


## Set money directly
func set_money(amount: int) -> void:
	var clamped := maxi(0, amount)
	if _money == clamped:
		return
	_money = clamped
	money_changed.emit(_money)
	print("[PlayerState] Money set to: $%d" % _money)


## Add money (e.g., round reward, kill reward)
func add_money(amount: int) -> void:
	if amount <= 0:
		return
	set_money(_money + amount)


## Spend money if sufficient funds available
## Returns true if successful, false if insufficient funds
func spend_money(amount: int) -> bool:
	if amount <= 0:
		return true
	if _money < amount:
		print("[PlayerState] Insufficient funds: have $%d, need $%d" % [_money, amount])
		return false
	set_money(_money - amount)
	return true


## Check if player can afford amount
func can_afford(amount: int) -> bool:
	return _money >= amount


## Reset money to initial amount (e.g., game start)
func reset_money() -> void:
	set_money(INITIAL_MONEY)
	print("[PlayerState] Money reset to initial: $%d" % INITIAL_MONEY)


## Add round reward
func add_round_reward(won: bool, loss_streak: int = 0) -> void:
	var reward: int
	if won:
		reward = 3250  # 勝利報酬
	else:
		# 敗北報酬（連敗ボーナス）
		match loss_streak:
			0: reward = 1400
			1: reward = 1900
			2: reward = 2400
			3: reward = 2900
			_: reward = 3400  # 最大
	add_money(reward)
	print("[PlayerState] Round reward: $%d (won=%s, loss_streak=%d)" % [reward, won, loss_streak])
