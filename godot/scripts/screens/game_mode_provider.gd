class_name GameModeProvider
extends RefCounted
## ゲームモードのプロバイダー基底クラス
##
## TrainingモードとMultiplayerモードの差異を抽象化する

## モード名を取得
func get_mode_name() -> String:
	return "base"


## プレイヤーのチームを決定
func determine_player_team() -> void:
	pass


## キャラクター登録
func register_character(_game_manager: GameManager, _character: GameCharacter, _network_id: int) -> void:
	pass


## パス確定時のコールバック
func on_path_confirmed() -> void:
	pass


## パス実行時のコールバック
func on_execute_paths(_count: int) -> void:
	pass


## ラウンド終了時のコールバック
func on_round_ended(_winner: int, _reason: int) -> void:
	pass


## グレネード投擲イベント
func on_grenade_thrown(_start_pos: Vector3, _velocity: Vector3, _is_smoke: bool, _grenade_id: int) -> void:
	pass


## グレネード爆発イベント
func on_grenade_exploded(_grenade_id: int, _position: Vector3, _is_smoke: bool) -> void:
	pass


## ラウンド開始可能か
func can_start_round() -> bool:
	return true


## クリーンアップ
func cleanup() -> void:
	pass
