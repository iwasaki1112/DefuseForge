class_name TrainingModeProvider
extends GameModeProvider
## Trainingモード用プロバイダー
##
## シングルプレイヤー用。ネットワーク同期なし。


func get_mode_name() -> String:
	return "training"


func determine_player_team() -> void:
	# トレーニングはCT固定（alphaプリセットでスポーンするため）
	PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)


func register_character(game_manager: GameManager, character: GameCharacter, _network_id: int) -> void:
	game_manager.register_character(character)


func can_start_round() -> bool:
	return true
