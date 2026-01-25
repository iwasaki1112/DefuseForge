class_name GameHUD
extends Control
## ゲーム画面の操作パネルUI

const TimelineBarUIScript = preload("res://scripts/ui/timeline_bar_ui.gd")

signal execute_all_requested()
signal clear_paths_requested()

var _pending_paths_label: Label
var _timeline_bar_ui: TimelineBarUI = null


func setup() -> void:
	# GameHUDを画面全体に広げる
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0

	# GameHUD自体はマウスイベントを通過させる（子要素のボタンは個別に受け取る）
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_control_panel()
	_build_timeline_bar()


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


## タイムラインバーを構築
func _build_timeline_bar() -> void:
	_timeline_bar_ui = TimelineBarUI.new()
	_timeline_bar_ui.name = "TimelineBarUI"
	add_child(_timeline_bar_ui)

	# 画面下部に配置
	_timeline_bar_ui.anchor_left = 0.1
	_timeline_bar_ui.anchor_right = 0.9
	_timeline_bar_ui.anchor_top = 1.0
	_timeline_bar_ui.anchor_bottom = 1.0
	_timeline_bar_ui.offset_top = -100
	_timeline_bar_ui.offset_bottom = 0
	_timeline_bar_ui.offset_left = 0
	_timeline_bar_ui.offset_right = 0


## ========================================
## タイムラインバーAPI
## ========================================

## キャラクターのタイムラインを設定
func set_character_timeline(
	character: Node,
	path: Array[Vector3],
	run_segments: Array[Dictionary] = [],
	wait_markers: Array[Dictionary] = [],
	door_markers: Array[Dictionary] = [],
	vision_markers: Array[Dictionary] = [],
	clear_markers: Array[Dictionary] = [],
	grenade_markers: Array[Dictionary] = [],
	label_text: String = "A",
	color: Color = Color.CYAN
) -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.set_character_timeline(
			character, path, run_segments, wait_markers, door_markers,
			vision_markers, clear_markers, grenade_markers, label_text, color
		)


## キャラクターのタイムラインを削除
func remove_character_timeline(character: Node) -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.remove_character_timeline(character)


## 全タイムラインをクリア
func clear_all_timelines() -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.clear_all()


## 実行モードを開始
func start_timeline_execution() -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.start_execution()


## 実行モードを終了
func stop_timeline_execution() -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.stop_execution()


## キャラクターの進行率を更新
func update_timeline_progress(character: Node, progress: float) -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.update_character_progress(character, progress)


## キャラクターの進行率をパス比率から更新
func update_timeline_progress_from_ratio(character: Node, ratio: float) -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.update_character_progress_from_ratio(character, ratio)


## 経過時間でプログレスラインを更新
func update_execution_time(elapsed_time: float) -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.update_execution_time(elapsed_time)


## タイムラインバーUIを取得
func get_timeline_bar_ui() -> TimelineBarUI:
	return _timeline_bar_ui
