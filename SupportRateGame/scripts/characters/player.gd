extends "res://scripts/characters/character_base.gd"

## プレイヤークラス
## プレイヤー固有の機能を提供

signal player_died

# チーム
var team: GameManager.Team = GameManager.Team.CT


func _ready() -> void:
	super._ready()

	# 死亡シグナルを接続
	died.connect(_on_player_died)


## プレイヤー死亡時の処理
func _on_player_died() -> void:
	player_died.emit()
	GameManager.player_died.emit(self)


## チームを設定
func set_team(new_team: GameManager.Team) -> void:
	team = new_team


## チームを取得
func get_team() -> GameManager.Team:
	return team


## プレイヤーかどうか（敵との区別用）
func is_player() -> bool:
	return true
