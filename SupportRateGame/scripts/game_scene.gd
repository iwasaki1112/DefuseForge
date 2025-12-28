extends Node3D

## ゲームシーンのメイン管理

@onready var player: CharacterBody3D = $Player
@onready var virtual_joystick = $GameUI/VirtualJoystick


func _ready() -> void:
	# ゲームを開始
	GameManager.start_game()

	# ジョイスティックをプレイヤーに接続
	if virtual_joystick and player:
		virtual_joystick.joystick_input.connect(_on_joystick_input)


func _exit_tree() -> void:
	# シーン終了時にゲームを停止
	GameManager.stop_game()


func _on_joystick_input(input_vector: Vector2) -> void:
	if player and player.has_method("set_joystick_input"):
		player.set_joystick_input(input_vector)
