class_name GameModeProvider
extends RefCounted
## ゲームモードのプロバイダー基底クラス
##
## TrainingモードとMultiplayerモードの差異を抽象化する

## モード名を取得
func get_mode_name() -> String:
	return "base"


## 初期化（GameScreenとGameManagerへの参照を受け取る）
func initialize(_game_screen: Node, _game_manager: GameManager) -> void:
	pass


## プレイヤーのチームを決定
func determine_player_team() -> void:
	pass


## キャラクター登録
func register_character(_game_manager: GameManager, _character: GameCharacter, _network_id: int) -> void:
	pass


## キャラクタースポーン（モードごとにオーバーライド可能）
## 戻り値: スポーンを処理した場合はtrue、GameScreenのデフォルト処理を使う場合はfalse
func spawn_characters(_game_screen: Node, _game_manager: GameManager) -> bool:
	return false  # デフォルトはGameScreenの処理を使用


## パス確定時のコールバック
func on_path_confirmed() -> void:
	pass


## パス実行時のコールバック
func on_execute_paths(_count: int) -> void:
	pass


## ラウンド終了時のコールバック
func on_round_ended(_winner: int, _reason: int) -> void:
	pass


## ラウンド開始可能か
func can_start_round() -> bool:
	return true


## クリーンアップ
func cleanup() -> void:
	pass
