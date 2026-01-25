class_name TimelineBar
extends Control
## 単一キャラクターのタイムラインバー
## パスの時間軸を可視化し、Execute時はプログレスバーとして機能

## 色定数
const COLOR_RUN := Color("#FF8800")
const COLOR_WAIT := Color("#FFCC00")
const COLOR_DOOR := Color("#FF4444")
const COLOR_VISION := Color("#AA66FF")  ## 紫
const COLOR_CLEAR := Color("#66CCFF")   ## 水色
const COLOR_GRENADE := Color("#66FF66") ## 緑
const COLOR_BACKGROUND := Color("#333333", 0.5)

## マーカーサイズ
const MARKER_ICON_SIZE := 16.0  ## アイコンサイズ（ピクセル）
const MARKER_BG_PADDING := 2.0  ## 背景のパディング

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
		_draw_markers(rect)

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


## 瞬間マーカーを描画
func _draw_markers(bar_rect: Rect2) -> void:
	if not _timeline_data:
		return

	var total_duration = _timeline_data.total_duration
	if total_duration < 0.001:
		return

	# 最大時間に対するスケーリング
	var scale_duration = _max_duration if _max_duration > 0.001 else total_duration
	var icon_size = MARKER_ICON_SIZE
	var center_y = bar_rect.size.y / 2.0

	for marker in _timeline_data.markers:
		var x = (marker.time / scale_duration) * bar_rect.size.x
		var bg_color = _get_marker_color(marker.type)
		var icon_color = Color.WHITE

		# 背景円を描画
		var bg_radius = (icon_size / 2.0) + MARKER_BG_PADDING
		draw_circle(Vector2(x, center_y), bg_radius, bg_color)

		# 白い縁取り
		draw_arc(Vector2(x, center_y), bg_radius, 0, TAU, 24, Color(1, 1, 1, 0.6), 1.0)

		# アイコンを描画
		_draw_marker_icon(marker.type, Vector2(x, center_y), icon_size, icon_color)


## マーカータイプから色を取得
func _get_marker_color(marker_type: int) -> Color:
	match marker_type:
		TimelineCalculator.MarkerType.VISION:
			return COLOR_VISION
		TimelineCalculator.MarkerType.CLEAR:
			return COLOR_CLEAR
		TimelineCalculator.MarkerType.GRENADE:
			return COLOR_GRENADE
		_:
			return Color.WHITE


## マーカーアイコンを描画
func _draw_marker_icon(marker_type: int, center: Vector2, icon_size: float, color: Color) -> void:
	var half_size = icon_size / 2.0

	match marker_type:
		TimelineCalculator.MarkerType.VISION:
			_draw_vision_icon(center, half_size, color)
		TimelineCalculator.MarkerType.CLEAR:
			_draw_clear_icon(center, half_size, color)
		TimelineCalculator.MarkerType.GRENADE:
			_draw_grenade_icon(center, half_size, color)


## Vision アイコン（矢印）を描画
func _draw_vision_icon(center: Vector2, half_size: float, color: Color) -> void:
	# 上向き矢印
	var shaft_width = half_size * 0.3
	var shaft_height = half_size * 0.6
	var head_width = half_size * 0.8
	var head_height = half_size * 0.6

	# シャフト（縦棒）
	var shaft_rect = Rect2(
		center - Vector2(shaft_width / 2.0, -shaft_height * 0.2),
		Vector2(shaft_width, shaft_height)
	)
	draw_rect(shaft_rect, color, true)

	# 矢印の頭（三角形）
	var arrow_tip = center - Vector2(0, half_size * 0.8)
	var arrow_left = center - Vector2(head_width / 2.0, shaft_height * 0.2 - head_height)
	var arrow_right = center - Vector2(-head_width / 2.0, shaft_height * 0.2 - head_height)

	draw_polygon(PackedVector2Array([arrow_tip, arrow_left, arrow_right]), PackedColorArray([color, color, color]))


## Clear アイコン（リセット矢印）を描画
func _draw_clear_icon(center: Vector2, half_size: float, color: Color) -> void:
	# 円弧（270度分）
	var arc_radius = half_size * 0.6
	var arc_width = 2.0

	# 円弧を描画（45度から315度まで）
	draw_arc(center, arc_radius, deg_to_rad(45), deg_to_rad(315), 16, color, arc_width)

	# 矢印の先端（円弧の終点に三角形）
	var arrow_angle = deg_to_rad(315)
	var arrow_pos = center + Vector2(cos(arrow_angle), sin(arrow_angle)) * arc_radius
	var arrow_size = half_size * 0.4

	# 矢印の方向（接線方向）
	var tangent = Vector2(-sin(arrow_angle), cos(arrow_angle))
	var tip = arrow_pos + tangent * arrow_size
	var base1 = arrow_pos + Vector2(cos(arrow_angle), sin(arrow_angle)) * arrow_size * 0.5
	var base2 = arrow_pos - Vector2(cos(arrow_angle), sin(arrow_angle)) * arrow_size * 0.5

	draw_polygon(PackedVector2Array([tip, base1, base2]), PackedColorArray([color, color, color]))


## Grenade アイコン（爆発）を描画
func _draw_grenade_icon(center: Vector2, half_size: float, color: Color) -> void:
	# スターバースト形状（8つの尖った部分）
	var outer_radius = half_size * 0.8
	var inner_radius = half_size * 0.35
	var num_points = 8

	var points = PackedVector2Array()
	var colors = PackedColorArray()

	for i in range(num_points * 2):
		var angle = TAU * i / (num_points * 2) - PI / 2  # 上向きに開始
		var radius = outer_radius if i % 2 == 0 else inner_radius
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		colors.append(color)

	draw_polygon(points, colors)


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
