class_name TrainingModeProvider
extends GameModeProvider
## Trainingモード用プロバイダー
##
## シングルプレイヤー用。ネットワーク同期なし。


func get_mode_name() -> String:
	return "training"


func determine_player_team() -> void:
	var teams = [GameCharacter.Team.COUNTER_TERRORIST, GameCharacter.Team.TERRORIST]
	var random_team = teams[randi() % 2]
	PlayerState.set_player_team(random_team)


func register_character(game_manager: GameManager, character: GameCharacter, _network_id: int) -> void:
	game_manager.register_character(character)


func can_start_round() -> bool:
	return true
