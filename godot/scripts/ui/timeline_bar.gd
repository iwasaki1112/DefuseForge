class_name TimelineBar
extends Control
## 単一キャラクターのタイムラインバー
## パスの時間軸を可視化し、Execute時はプログレスバーとして機能

## 色定数
const COLOR_RUN := Color("#FF8800")
const COLOR_WAIT := Color("#FFCC00")
const COLOR_DOOR := Color("#FF4444")
const COLOR_BACKGROUND := Color("#333333", 0.5)

## バーの高さ
const BAR_HEIGHT: float = 24.0

## タイムラインデータ
var _timeline_data: TimelineCalculator.TimelineData = null
var _character_color: Color = Color.CYAN
var _max_duration: float = 0.0  ## 全体の最大時間（スケーリング用）

## マーカーアイコン（将来の拡張用）
var _marker_icons: Array[Dictionary] = []


func _init() -> void:
	custom_minimum_size = Vector2(200, BAR_HEIGHT)
	# マウスイベントを通過させる
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect = Rect2(Vector2.ZERO, size)

	# 背景を描画
	draw_rect(rect, COLOR_BACKGROUND, true)

	# タイムラインセグメントを描画
	if _timeline_data and _timeline_data.total_duration > 0.001:
		_draw_segments(rect)

	# 枠線を描画（実際のタイムライン幅のみ）
	var actual_width = _get_scaled_width(rect.size.x)
	var frame_rect = Rect2(Vector2.ZERO, Vector2(actual_width, rect.size.y))
	draw_rect(frame_rect, Color(1, 1, 1, 0.3), false, 1.0)


## スケーリングされた幅を取得
func _get_scaled_width(full_width: float) -> float:
	if _max_duration < 0.001:
		return full_width
	if not _timeline_data or _timeline_data.total_duration < 0.001:
		return 0.0
	var scale = _timeline_data.total_duration / _max_duration
	return full_width * scale


## タイムラインセグメントを描画
func _draw_segments(bar_rect: Rect2) -> void:
	if not _timeline_data:
		return

	var total_duration = _timeline_data.total_duration
	if total_duration < 0.001:
		return

	# 最大時間に対するスケーリング
	var scale_duration = _max_duration if _max_duration > 0.001 else total_duration

	for segment in _timeline_data.segments:
		var start_x = (segment.start_time / scale_duration) * bar_rect.size.x
		var end_x = (segment.end_time / scale_duration) * bar_rect.size.x
		var segment_width = end_x - start_x

		if segment_width < 1.0:
			segment_width = 1.0

		var segment_rect = Rect2(
			Vector2(start_x, 0),
			Vector2(segment_width, bar_rect.size.y)
		)

		var color = _get_segment_color(segment.type)
		draw_rect(segment_rect, color, true)


## セグメントタイプから色を取得
func _get_segment_color(segment_type: int) -> Color:
	match segment_type:
		TimelineCalculator.SegmentType.RUN:
			return COLOR_RUN
		TimelineCalculator.SegmentType.WAIT:
			return COLOR_WAIT
		TimelineCalculator.SegmentType.DOOR:
			return COLOR_DOOR
		_:
			# WALK: キャラクター色を使用（80%アルファ）
			return Color(_character_color.r, _character_color.g, _character_color.b, 0.8)


## タイムラインデータを設定
func set_timeline_data(data: TimelineCalculator.TimelineData, character_color: Color = Color.CYAN) -> void:
	_timeline_data = data
	_character_color = character_color
	queue_redraw()


## パス比率から時間を取得
func get_time_at_ratio(ratio: float) -> float:
	if _timeline_data:
		return _timeline_data.get_time_at_ratio(ratio)
	return 0.0


## タイムラインをクリア
func clear() -> void:
	_timeline_data = null
	_max_duration = 0.0
	queue_redraw()


## 最大時間を設定（相対スケーリング用）
func set_max_duration(max_duration: float) -> void:
	_max_duration = max_duration
	queue_redraw()


## 合計時間を取得
func get_total_duration() -> float:
	return _timeline_data.total_duration if _timeline_data else 0.0


## キャラクター色を取得
func get_character_color() -> Color:
	return _character_color
