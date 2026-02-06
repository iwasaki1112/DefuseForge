class_name MainMenuScreen
extends Control
## メインメニュー画面
##
## ゲーム起動時に表示されるメインメニュー。
## Training、Optionボタンでシーン遷移する。

const MAP_SELECTION_SCENE := "res://scenes/screens/map_selection.tscn"
const OPTION_SCENE := "res://scenes/screens/option.tscn"
const LOBBY_SCENE := "res://scenes/screens/lobby.tscn"
var LOGO_TEXTURE: Texture2D
var TRAINING_BUTTON_TEXTURE: Texture2D
var MULTIPLAYER_BUTTON_TEXTURE: Texture2D
var OPTION_BUTTON_TEXTURE: Texture2D


func _init() -> void:
	LOGO_TEXTURE = load("res://assets/images/logo.png")
	TRAINING_BUTTON_TEXTURE = load("res://assets/ui/main_menu/training-button.png")
	MULTIPLAYER_BUTTON_TEXTURE = load("res://assets/ui/main_menu/multiplayer-button.png")
	OPTION_BUTTON_TEXTURE = load("res://assets/ui/main_menu/option-button.png")


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# ロゴ（上部中央に配置）
	var logo := TextureRect.new()
	logo.texture = LOGO_TEXTURE
	logo.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(logo)
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	logo.anchor_top = 0.0
	logo.anchor_bottom = 0.0
	logo.offset_left = -logo.texture.get_width() / 2.0
	logo.offset_right = logo.texture.get_width() / 2.0
	logo.offset_top = 20
	logo.offset_bottom = logo.texture.get_height() + 20

	# ボタンコンテナ（画面中央に配置）
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var button_container := VBoxContainer.new()
	button_container.add_theme_constant_override("separation", 0)
	center.add_child(button_container)

	# スペーサー（この値を大きくするとボタンが下に移動）
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 200)
	button_container.add_child(spacer)

	# Trainingボタン（画像）
	var training_btn := _create_texture_button(TRAINING_BUTTON_TEXTURE)
	training_btn.custom_minimum_size = Vector2(500, 150)
	training_btn.pressed.connect(_on_training_pressed)
	button_container.add_child(training_btn)

	# Multiplayerボタン（画像）
	var multiplayer_btn := _create_texture_button(MULTIPLAYER_BUTTON_TEXTURE)
	multiplayer_btn.custom_minimum_size = Vector2(500, 150)
	multiplayer_btn.pressed.connect(_on_multiplayer_pressed)
	button_container.add_child(multiplayer_btn)

	# Optionボタン（右上に配置、最後に追加して最前面に）
	var option_btn := _create_texture_button(OPTION_BUTTON_TEXTURE)
	option_btn.pressed.connect(_on_option_pressed)
	option_btn.custom_minimum_size = Vector2(48, 48)
	add_child(option_btn)
	# 右上に固定（画面可変対応）
	option_btn.anchor_left = 1.0
	option_btn.anchor_right = 1.0
	option_btn.anchor_top = 0.0
	option_btn.anchor_bottom = 0.0
	option_btn.offset_left = -68
	option_btn.offset_right = -20
	option_btn.offset_top = 20
	option_btn.offset_bottom = 68


func _create_texture_button(texture: Texture2D) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = texture
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(250, 60)
	return btn


func _on_training_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SELECTION_SCENE)


func _on_option_pressed() -> void:
	get_tree().change_scene_to_file(OPTION_SCENE)


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
