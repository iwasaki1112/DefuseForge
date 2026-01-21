class_name GameHUD
extends Control
## ゲーム画面の操作パネルUI

signal execute_all_requested()
signal clear_paths_requested()

var _pending_paths_label: Label


func setup() -> void:
	_build_control_panel()


func set_pending_paths(count: int) -> void:
	if _pending_paths_label:
		_pending_paths_label.text = "Pending: %d paths" % count


func _build_control_panel() -> void:
	var control_panel := VBoxContainer.new()
	control_panel.name = "ControlPanel"
	control_panel.anchor_left = 0.0
	control_panel.anchor_top = 0.0
	control_panel.anchor_right = 0.0
	control_panel.anchor_bottom = 0.0
	control_panel.offset_left = 10
	control_panel.offset_top = 80
	control_panel.offset_right = 200
	control_panel.add_theme_constant_override("separation", 10)
	add_child(control_panel)

	# 保留パス数ラベル
	_pending_paths_label = Label.new()
	_pending_paths_label.text = "Pending: 0 paths"
	_pending_paths_label.add_theme_font_size_override("font_size", 18)
	control_panel.add_child(_pending_paths_label)

	# 実行ボタン
	var execute_button := Button.new()
	execute_button.text = "Execute All"
	execute_button.custom_minimum_size = Vector2(180, 45)
	execute_button.add_theme_font_size_override("font_size", 18)
	execute_button.pressed.connect(_on_execute_pressed)
	control_panel.add_child(execute_button)

	# クリアボタン
	var clear_button := Button.new()
	clear_button.text = "Clear All Paths"
	clear_button.custom_minimum_size = Vector2(180, 45)
	clear_button.add_theme_font_size_override("font_size", 18)
	clear_button.pressed.connect(_on_clear_pressed)
	control_panel.add_child(clear_button)

	# 操作説明ラベル
	var help_label := Label.new()
	help_label.text = "Right-drag: Move camera"
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	control_panel.add_child(help_label)


func _on_execute_pressed() -> void:
	execute_all_requested.emit()


func _on_clear_pressed() -> void:
	clear_paths_requested.emit()
