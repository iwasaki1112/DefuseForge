extends "res://scripts/characters/character_base.gd"

## プレイヤークラス
## プレイヤー固有の機能を提供
## PlayerDataと連携して個別のステータスを管理

signal player_died

# チーム
var team: GameManager.Team = GameManager.Team.CT

# PlayerDataへの参照
var player_data: RefCounted = null


func _ready() -> void:
	super._ready()

	# 死亡シグナルを接続
	died.connect(_on_player_died)


## PlayerDataを設定（SquadManagerから呼ばれる）
func set_player_data(data: RefCounted) -> void:
	player_data = data


## プレイヤー死亡時の処理
func _on_player_died() -> void:
	player_died.emit()
	if player_data:
		player_data.is_alive = false
		player_data.health = 0.0
	# SquadManagerに死亡を通知（GameManagerは経由しない）
	if SquadManager:
		SquadManager.on_player_died(self)


## チームを設定
func set_team(new_team: GameManager.Team) -> void:
	team = new_team


## チームを取得
func get_team() -> GameManager.Team:
	return team


## プレイヤーかどうか（敵との区別用）
func is_player() -> bool:
	return true


## ダメージを受ける（PlayerDataと同期）
func take_damage(amount: float) -> void:
	super.take_damage(amount)
	# PlayerDataの値を同期
	if player_data:
		player_data.health = health
		player_data.armor = armor


## 回復（PlayerDataと同期）
func heal(amount: float) -> void:
	super.heal(amount)
	if player_data:
		player_data.health = health


## アーマー追加（PlayerDataと同期）
func add_armor(amount: float) -> void:
	super.add_armor(amount)
	if player_data:
		player_data.armor = armor


## ステータスをリセット（ラウンド開始時）
func reset_stats() -> void:
	health = 100.0
	armor = 0.0
	is_alive = true
	visible = true
	if player_data:
		player_data.health = health
		player_data.armor = armor
		player_data.is_alive = true


## 武器を装備（SquadManagerから呼ばれる）
func equip_weapon(weapon_id: int) -> void:
	set_weapon(weapon_id)
