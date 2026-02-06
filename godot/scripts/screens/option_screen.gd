class_name OptionScreen
extends Control
## オプション画面
##
## プレイヤー名などの設定を変更する画面。

const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"
var _name_input: LineEdit


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# 背景と中央配置の共通レイアウト
	ScreenLayout.add_solid_background(self)
	var vbox := ScreenLayout.create_centered_vbox(self, 30)

	# タイトル
	var title := Label.new()
	title.text = "Option"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# スペーサー
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	# プレイヤー名設定
	var name_container := HBoxContainer.new()
	name_container.add_theme_constant_override("separation", 15)
	vbox.add_child(name_container)

	var name_label := Label.new()
	name_label.text = "Player Name:"
	name_label.add_theme_font_size_override("font_size", 24)
	name_container.add_child(name_label)

	_name_input = LineEdit.new()
	_name_input.custom_minimum_size = Vector2(250, 40)
	_name_input.add_theme_font_size_override("font_size", 24)
	_name_input.text = SettingsManager.get_player_name()
	_name_input.text_submitted.connect(_on_name_submitted)
	name_container.add_child(_name_input)

	# スペーサー
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer2)

	# Backボタン
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 50)
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(back_btn)


func _on_name_submitted(_new_text: String) -> void:
	_save_name()


func _on_back_pressed() -> void:
	_save_name()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _save_name() -> void:
	SettingsManager.set_player_name(_name_input.text)
