extends Area3D

## 支持率を表すコインアイテム

@export_group("コイン設定")
@export var point_value: int = 10
@export var rotation_speed: float = 100.0
@export var bob_speed: float = 2.0
@export var bob_height: float = 0.3

var start_position: Vector3
var time_offset: float = 0.0


func _ready() -> void:
	start_position = global_position
	time_offset = randf() * TAU  # ランダムな開始位相
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# コインを回転させる
	rotate_y(deg_to_rad(rotation_speed) * delta)

	# 上下にふわふわ動かす
	var new_y := start_position.y + sin(Time.get_ticks_msec() * 0.001 * bob_speed + time_offset) * bob_height
	global_position.y = new_y


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		# スコアを加算
		GameManager.add_score(point_value)

		# プレイヤーに通知
		if body.has_method("on_coin_collected"):
			body.on_coin_collected()

		# コインを消す
		queue_free()
