class_name HealthComponent
extends Node

## HP管理コンポーネント
## ダメージ、死亡処理を担当

signal died(killer: Node3D)
signal damaged(amount: float, attacker: Node3D, is_headshot: bool)
signal healed(amount: float)

@export var max_health: float = 100.0

var health: float = 100.0
var is_alive: bool = true


func _ready() -> void:
	health = max_health
	is_alive = true


## ダメージを受ける
## @param amount: ダメージ量
## @param attacker: 攻撃者（オプション）
## @param is_headshot: ヘッドショットかどうか
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if not is_alive:
		return

	health = max(0.0, health - amount)
	damaged.emit(amount, attacker, is_headshot)

	if health <= 0.0:
		_die(attacker)


## 回復
## @param amount: 回復量
func heal(amount: float) -> void:
	if not is_alive:
		return

	var old_health = health
	health = min(max_health, health + amount)

	if health > old_health:
		healed.emit(health - old_health)


## HPをリセット
func reset() -> void:
	health = max_health
	is_alive = true


## HP割合を取得（0.0 - 1.0）
func get_health_ratio() -> float:
	return health / max_health


## 死亡処理
func _die(killer: Node3D = null) -> void:
	is_alive = false
	died.emit(killer)
