class_name GameHUD
extends Control
## ゲーム画面の操作パネルUI
##
## シーンファイル: res://scenes/ui/game_hud.tscn

signal execute_all_requested()
signal clear_paths_requested()

@onready var _pending_paths_label: Label = $ControlPanel/PendingPathsLabel

var _timeline_bar_ui: TimelineBarUI = null


func setup() -> void:
	_build_timeline_bar()


func set_pending_paths(count: int) -> void:
	if _pending_paths_label:
		_pending_paths_label.text = "Pending: %d paths" % count


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
	smoke_grenade_markers: Array[Dictionary] = [],
	label_text: String = "A",
	color: Color = Color.CYAN
) -> void:
	if _timeline_bar_ui:
		_timeline_bar_ui.set_character_timeline(
			character, path, run_segments, wait_markers, door_markers,
			vision_markers, clear_markers, grenade_markers, smoke_grenade_markers, label_text, color
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
