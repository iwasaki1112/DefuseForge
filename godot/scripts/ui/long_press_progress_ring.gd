extends Control
class_name LongPressProgressRing
## 長押しプログレスリング
##
## 長押し操作の進行状況を円形で表示するUIコンポーネント。
## 再利用可能なクラスとして設計されており、任意の長押し操作に使用可能。

## 設定
@export var ring_radius: float = 30.0  ## リングの半径
@export var ring_width: float = 4.0    ## リングの太さ
@export var ring_color: Color = Color(1.0, 1.0, 1.0, 0.9)  ## リングの色
@export var background_color: Color = Color(0.3, 0.3, 0.3, 0.5)  ## 背景リングの色
@export var segments: int = 64  ## 円の分割数（滑らかさ）
## タッチ時の上方オフセット（指で隠れないように）
var touch_offset: Vector2 = Vector2(0, -80)

## 内部状態
var _progress: float = 0.0  ## 現在の進行率 (0.0 ~ 1.0)
var _target_duration: float = 1.0  ## 目標時間（秒）
var _elapsed_time: float = 0.0  ## 経過時間
var _is_active: bool = false  ## アクティブ状態
var _auto_update: bool = false  ## 自動更新モード


func _ready() -> void:
	# 初期は非表示
	visible = false
	# マウスイベントを無視
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not _is_active:
		return

	if _auto_update:
		_elapsed_time += delta
		_progress = clampf(_elapsed_time / _target_duration, 0.0, 1.0)
		queue_redraw()

		# 完了時
		if _progress >= 1.0:
			_is_active = false


func _draw() -> void:
	if not visible:
		return

	var center := size / 2.0

	# 背景リング（全円）
	_draw_arc_ring(center, 0.0, 1.0, background_color)

	# プログレスリング
	if _progress > 0.0:
		_draw_arc_ring(center, 0.0, _progress, ring_color)


## 円弧リングを描画（内部ヘルパー）
func _draw_arc_ring(center: Vector2, start_ratio: float, end_ratio: float, color: Color) -> void:
	if end_ratio <= start_ratio:
		return

	# 開始角度は上（-90度 = -PI/2）から時計回り
	var start_angle := -PI / 2.0 + start_ratio * TAU
	var end_angle := -PI / 2.0 + end_ratio * TAU
	var angle_step := (end_angle - start_angle) / segments

	var outer_radius := ring_radius
	var inner_radius := ring_radius - ring_width

	# ポリゴンとして描画（外周→内周→外周の順で閉じたパスを作成）
	var polygon_points := PackedVector2Array()

	# 外周を時計回りに追加
	for i in range(segments + 1):
		var angle := start_angle + angle_step * i
		polygon_points.append(center + Vector2(cos(angle), sin(angle)) * outer_radius)

	# 内周を反時計回りに追加（逆順）
	for i in range(segments, -1, -1):
		var angle := start_angle + angle_step * i
		polygon_points.append(center + Vector2(cos(angle), sin(angle)) * inner_radius)

	if polygon_points.size() >= 3:
		draw_colored_polygon(polygon_points, color)


## ========================================
## 公開API
## ========================================

## 長押しを開始（自動更新モード）
## @param screen_pos: 表示位置（スクリーン座標）
## @param duration: 長押し完了までの時間（秒）
## @param color: リングの色（オプション）
func start(screen_pos: Vector2, duration: float, color: Color = Color.WHITE) -> void:
	_target_duration = duration
	_elapsed_time = 0.0
	_progress = 0.0
	_is_active = true
	_auto_update = true

	if color != Color.WHITE:
		ring_color = color

	# 位置を設定（中央揃え + タッチオフセット）
	var offset_pos := screen_pos + touch_offset
	position = offset_pos - size / 2.0
	visible = true
	queue_redraw()


## 長押しを開始（手動更新モード）
## @param screen_pos: 表示位置（スクリーン座標）
## @param color: リングの色（オプション）
func start_manual(screen_pos: Vector2, color: Color = Color.WHITE) -> void:
	_progress = 0.0
	_is_active = true
	_auto_update = false

	if color != Color.WHITE:
		ring_color = color

	var offset_pos := screen_pos + touch_offset
	position = offset_pos - size / 2.0
	visible = true
	queue_redraw()


## 進行率を手動で更新
## @param progress: 進行率 (0.0 ~ 1.0)
func set_progress(progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


## 進行率を時間ベースで更新
## @param elapsed: 経過時間（秒）
## @param duration: 目標時間（秒）
func update_progress(elapsed: float, duration: float) -> void:
	if duration > 0.0:
		_progress = clampf(elapsed / duration, 0.0, 1.0)
	else:
		_progress = 0.0
	queue_redraw()


## 位置を更新
## @param screen_pos: 新しい位置（スクリーン座標）
func update_position(screen_pos: Vector2) -> void:
	var offset_pos := screen_pos + touch_offset
	position = offset_pos - size / 2.0


## 長押しを完了（非表示にする）
func complete() -> void:
	_is_active = false
	visible = false
	_progress = 0.0


## 長押しをキャンセル（非表示にする）
func cancel() -> void:
	_is_active = false
	visible = false
	_progress = 0.0


## アクティブ状態を取得
func is_active() -> bool:
	return _is_active


## 完了したかどうか
func is_completed() -> bool:
	return _progress >= 1.0


## 現在の進行率を取得
func get_progress() -> float:
	return _progress


## サイズを設定
func set_ring_size(radius: float, width: float = 4.0) -> void:
	ring_radius = radius
	ring_width = width
	custom_minimum_size = Vector2(radius * 2 + 4, radius * 2 + 4)
	size = custom_minimum_size
	queue_redraw()


## ========================================
## ファクトリーメソッド
## ========================================

## 新しいインスタンスを作成して親に追加
static func create(parent: Node, radius: float = 30.0) -> LongPressProgressRing:
	var ring := LongPressProgressRing.new()
	ring.ring_radius = radius
	ring.custom_minimum_size = Vector2(radius * 2 + 4, radius * 2 + 4)
	ring.size = ring.custom_minimum_size
	parent.add_child(ring)
	return ring
