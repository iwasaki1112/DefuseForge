extends Control

## タイトル画面の管理

@export var game_scene_path: String = "res://scenes/game.tscn"

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var start_button: Button = $VBoxContainer/StartButton

var tween: Tween


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	_start_title_animation()


func _start_title_animation() -> void:
	if title_label == null:
		return

	# 脈動アニメーション
	tween = create_tween()
	tween.set_loops()
	tween.tween_property(title_label, "scale", Vector2(1.05, 1.05), 0.5)
	tween.tween_property(title_label, "scale", Vector2(1.0, 1.0), 0.5)


func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file(game_scene_path)
