class_name GameHUD
extends Control
## ゲーム画面の操作パネルUI
##
## シーンファイル: res://scenes/ui/game_hud.tscn

signal execute_all_requested()
signal clear_paths_requested()

const TIMER_WARNING_THRESHOLD := 10.0
const TIMER_WARNING_COLOR := Color(1.0, 0.3, 0.3)
const TIMER_NORMAL_COLOR := Color.WHITE

@onready var _pending_paths_label: Label = $ControlPanel/PendingPathsLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _execute_button: TextureButton = %ExecuteButton

var _timeline_bar_ui: TimelineBarUI = null


func setup() -> void:
	_build_timeline_bar()


func set_pending_paths(count: int) -> void:
	if _pending_paths_label:
		_pending_paths_label.text = "Pending: %d paths" % count


## タイマーを更新
func update_timer(remaining: float) -> void:
	if not _timer_label:
		return
	var total_seconds := int(remaining)
	@warning_ignore("integer_division")
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]

	if remaining <= TIMER_WARNING_THRESHOLD:
		_timer_label.add_theme_color_override("font_color", TIMER_WARNING_COLOR)
	else:
		_timer_label.add_theme_color_override("font_color", TIMER_NORMAL_COLOR)


func _on_execute_pressed() -> void:
	_play_button_press_animation()
	execute_all_requested.emit()


## ボタン押下時のアニメーション演出
func _play_button_press_animation() -> void:
	if not _execute_button:
		return

	# 既存のTweenをキャンセル
	var tween := create_tween()
	tween.set_parallel(true)

	# 拡大→縮小アニメーション
	_execute_button.pivot_offset = _execute_button.size / 2
	tween.tween_property(_execute_button, "scale", Vector2(1.15, 1.15), 0.08).set_ease(Tween.EASE_OUT)

	# 透明度アニメーション（少し透明→不透明）
	_execute_button.modulate.a = 0.7
	tween.tween_property(_execute_button, "modulate:a", 1.0, 0.08).set_ease(Tween.EASE_OUT)

	# 縮小アニメーション（元に戻る）
	tween.chain().tween_property(_execute_button, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_IN_OUT)


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
