class_name MainMenuScreen
extends Control
## メインメニュー画面
##
## ゲーム起動時に表示されるメインメニュー。
## Training、Optionボタンでシーン遷移する。

const MAP_SELECTION_SCENE := "res://scenes/screens/map_selection.tscn"
const OPTION_SCENE := "res://scenes/screens/option.tscn"
const ScreenLayoutScript := preload("res://scripts/ui/screen_layout.gd")
const LOGO_TEXTURE := preload("res://assets/images/logo.png")

var _welcome_label: Label


func _ready() -> void:
	_setup_ui()
	_update_welcome_message()
	SettingsManager.settings_changed.connect(_update_welcome_message)


func _setup_ui() -> void:
	# 中央配置の共通レイアウト（背景はシーンのTextureRectで設定）
	var vbox := ScreenLayoutScript.create_centered_vbox(self, 30)

	# ロゴ
	var logo := TextureRect.new()
	logo.texture = LOGO_TEXTURE
	logo.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(logo)

	# Welcome メッセージ
	_welcome_label = Label.new()
	_welcome_label.add_theme_font_size_override("font_size", 24)
	_welcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_welcome_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_welcome_label)

	# スペーサー
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)

	# ボタンコンテナ
	var button_container := VBoxContainer.new()
	button_container.add_theme_constant_override("separation", 15)
	vbox.add_child(button_container)

	# Trainingボタン
	var training_btn := _create_menu_button("Training")
	training_btn.pressed.connect(_on_training_pressed)
	button_container.add_child(training_btn)

	# Optionボタン
	var option_btn := _create_menu_button("Option")
	option_btn.pressed.connect(_on_option_pressed)
	button_container.add_child(option_btn)


func _create_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(250, 60)
	btn.add_theme_font_size_override("font_size", 28)
	return btn


func _update_welcome_message() -> void:
	if _welcome_label:
		var player_name := SettingsManager.get_player_name()
		_welcome_label.text = "Welcome, %s" % player_name


func _on_training_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SELECTION_SCENE)


func _on_option_pressed() -> void:
	get_tree().change_scene_to_file(OPTION_SCENE)
