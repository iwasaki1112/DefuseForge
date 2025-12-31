extends Control

## タイトル画面の管理

@export var game_scene_path: String = "res://scenes/game.tscn"
@export var lobby_scene_path: String = "res://scenes/lobby/lobby.tscn"
@export var test_anim_scene_path: String = "res://scenes/test_animation.tscn"

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var online_button: Button = $VBoxContainer/OnlineButton
@onready var test_anim_button: Button = $VBoxContainer/TestAnimButton

var tween: Tween


func _ready() -> void:
	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)
	if online_button:
		online_button.pressed.connect(_on_online_button_pressed)
	if test_anim_button:
		test_anim_button.pressed.connect(_on_test_anim_button_pressed)
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
	GameManager.is_online_match = false
	get_tree().change_scene_to_file(game_scene_path)


func _on_online_button_pressed() -> void:
	get_tree().change_scene_to_file(lobby_scene_path)


func _on_test_anim_button_pressed() -> void:
	get_tree().change_scene_to_file(test_anim_scene_path)
