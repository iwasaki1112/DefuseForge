class_name TimelineBarUI
extends PanelContainer
## タイムラインバーUI
## 複数キャラクターのタイムラインを管理し、画面下部に表示

const CharacterTimelineRowScript = preload("res://scripts/ui/character_timeline_row.gd")
const TimelineCalculatorScript = preload("res://scripts/utils/timeline_calculator.gd")

## UI設定
const PANEL_HEIGHT: float = 80.0  ## 2行分の高さ
const PANEL_MAX_HEIGHT: float = 120.0  ## 3行以上の場合
const ROW_HEIGHT: float = 32.0
const PADDING: float = 8.0
const VISIBLE_ROWS: int = 2

## 内部参照
var _scroll_container: ScrollContainer = null
var _rows_container: VBoxContainer = null
var _character_rows: Dictionary = {}  ## { character_id: CharacterTimelineRow }

## 状態
var _is_executing: bool = false
var _max_duration: float = 0.0  ## 全キャラクター中の最長時間
var _current_time: float = 0.0  ## 現在の経過時間

## プログレスライン用
var _progress_line: Control = null


func _init() -> void:
	# マウスイベントを通過させる（ゲーム操作をブロックしない）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false  ## 初期状態は非表示


## UIを構築
func _build_ui() -> void:
	# パネルスタイル
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = PADDING
	style.content_margin_right = PADDING
	style.content_margin_top = PADDING
	style.content_margin_bottom = PADDING
	add_theme_stylebox_override("panel", style)

	# ScrollContainer
	_scroll_container = ScrollContainer.new()
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll_container)

	# VBoxContainer（行コンテナ）
	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 4)
	_rows_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_container.add_child(_rows_container)

	# プログレスライン（全体を覆うオーバーレイ）
	_progress_line = Control.new()
	_progress_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress_line.draw.connect(_draw_progress_line)
	add_child(_progress_line)

	# 初期サイズ
	custom_minimum_size = Vector2(300, PANEL_HEIGHT)


## キャラクターのタイムラインを追加または更新
## @param character: キャラクターノード
## @param path: パスポイント配列
## @param run_segments: Run区間配列
## @param wait_markers: Waitマーカー配列
## @param door_markers: Doorマーカー配列
## @param label_text: キャラクターラベル（A, B, C...）
## @param color: キャラクター色
func set_character_timeline(
	character: Node,
	path: Array[Vector3],
	run_segments: Array[Dictionary] = [],
	wait_markers: Array[Dictionary] = [],
	door_markers: Array[Dictionary] = [],
	label_text: String = "A",
	color: Color = Color.CYAN
) -> void:
	var char_id = character.get_instance_id()

	# タイムラインデータを計算
	var timeline_data = TimelineCalculator.calculate_timeline(
		path, run_segments, wait_markers, door_markers
	)

	# 既存の行を更新または新規作成
	var row: CharacterTimelineRow
	if _character_rows.has(char_id):
		row = _character_rows[char_id]
	else:
		row = CharacterTimelineRow.new()
		_rows_container.add_child(row)
		row.setup(character, label_text, color)
		_character_rows[char_id] = row

	row.set_timeline_data(timeline_data)

	# 最大時間を再計算して全バーを更新
	_recalculate_max_duration()

	# 表示状態を更新
	_update_visibility()


## キャラクターのタイムラインを削除
func remove_character_timeline(character: Node) -> void:
	var char_id = character.get_instance_id()
	if _character_rows.has(char_id):
		var row = _character_rows[char_id]
		row.queue_free()
		_character_rows.erase(char_id)

	# 最大時間を再計算
	_recalculate_max_duration()
	_update_visibility()


## 全タイムラインをクリア
func clear_all() -> void:
	for row in _character_rows.values():
		row.queue_free()
	_character_rows.clear()
	_is_executing = false
	_max_duration = 0.0

	_update_visibility()


## 最大時間を再計算して全バーのスケールを更新
func _recalculate_max_duration() -> void:
	_max_duration = 0.0
	for row in _character_rows.values():
		var duration = row.get_total_duration()
		if duration > _max_duration:
			_max_duration = duration

	# 全バーに最大時間を設定（相対スケーリング用）
	for row in _character_rows.values():
		row.set_max_duration(_max_duration)


## プログレスラインを描画
func _draw_progress_line() -> void:
	if not _is_executing or _max_duration < 0.001 or _character_rows.is_empty():
		return

	# 時間から位置を計算
	var progress_ratio = clampf(_current_time / _max_duration, 0.0, 1.0)

	# タイムラインバーの開始位置（ラベル幅分オフセット）
	var label_width = 30.0 + 8.0  # LABEL_WIDTH + SPACING from CharacterTimelineRow
	var bar_start_x = PADDING + label_width
	var bar_width = _progress_line.size.x - PADDING * 2 - label_width

	var x_pos = bar_start_x + progress_ratio * bar_width
	var line_start = Vector2(x_pos, 0)
	var line_end = Vector2(x_pos, _progress_line.size.y)

	_progress_line.draw_line(line_start, line_end, Color.WHITE, 2.0)


## 実行モードを開始
func start_execution() -> void:
	_is_executing = true
	_current_time = 0.0
	if _progress_line:
		_progress_line.queue_redraw()


## 実行モードを終了
func stop_execution() -> void:
	_is_executing = false
	_current_time = 0.0
	if _progress_line:
		_progress_line.queue_redraw()


## キャラクターの進行率を更新（時間ベースに変換）
## @param character: キャラクターノード
## @param progress: 進行率 (0.0 ~ 1.0)
func update_character_progress(character: Node, progress: float) -> void:
	var char_id = character.get_instance_id()
	if _character_rows.has(char_id):
		var row = _character_rows[char_id]
		var char_duration = row.get_total_duration()
		var char_time = progress * char_duration
		_update_current_time(char_time)


## キャラクターの進行率をパス比率から更新
func update_character_progress_from_ratio(character: Node, ratio: float) -> void:
	var char_id = character.get_instance_id()
	if _character_rows.has(char_id):
		var row = _character_rows[char_id]
		var char_time = row.get_time_at_ratio(ratio)
		_update_current_time(char_time)


## 現在時間を更新（最大の経過時間を使用）
func _update_current_time(time: float) -> void:
	if time > _current_time:
		_current_time = time
		if _progress_line:
			_progress_line.queue_redraw()


## 経過時間で直接更新（実時間ベース）
func update_execution_time(elapsed_time: float) -> void:
	_current_time = elapsed_time
	if _progress_line:
		_progress_line.queue_redraw()


## 表示状態を更新
func _update_visibility() -> void:
	var row_count = _character_rows.size()

	if row_count == 0:
		visible = false
		return

	visible = true

	# 行数に応じてパネル高さを調整
	if row_count <= VISIBLE_ROWS:
		custom_minimum_size.y = PADDING * 2 + ROW_HEIGHT * row_count + 4 * (row_count - 1)
	else:
		custom_minimum_size.y = PANEL_MAX_HEIGHT


## 実行中かどうか
func is_executing() -> bool:
	return _is_executing


## キャラクターのタイムライン行を取得
func get_character_row(character: Node) -> CharacterTimelineRow:
	var char_id = character.get_instance_id()
	return _character_rows.get(char_id, null)


## 登録されているキャラクター数を取得
func get_character_count() -> int:
	return _character_rows.size()
