class_name MuzzleFlash
extends Node3D

## マズルフラッシュエフェクト
## 発砲時に短時間表示される視覚効果

@onready var flash_sprite: MeshInstance3D = $FlashSprite
@onready var timer: Timer = $Timer

# フラッシュの表示時間
@export var flash_duration: float = 0.05


func _ready() -> void:
	timer.wait_time = flash_duration
	timer.timeout.connect(_on_timer_timeout)
	flash_sprite.visible = false


## フラッシュを表示
func flash() -> void:
	flash_sprite.visible = true
	# ランダムに少し回転させてバリエーションを出す
	flash_sprite.rotation.z = randf() * TAU
	timer.start()


## タイマー終了時にフラッシュを非表示
func _on_timer_timeout() -> void:
	flash_sprite.visible = false
