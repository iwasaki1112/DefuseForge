class_name TouchInputHandler
extends InputDeviceHandler
## タッチ入力ハンドラ
##
## 責務:
## - タッチ開始/終了の処理
## - タッチドラッグの処理
## - ピンチズームの処理
##
## 対応イベント:
## - InputEventScreenTouch
## - InputEventScreenDrag


#region 設定

## タッチ用タップ判定閾値（指は精度が低いため小さめ）
const TOUCH_TAP_THRESHOLD: float = 20.0

#endregion


#region 内部状態

## タッチ入力アクティブかどうか（エミュレートマウスイベント抑制用）
var _touch_active: bool = false

## タッチポイント辞書（index -> position）
var _touch_points: Dictionary = {}

## ピンチ中かどうか
var _is_pinching: bool = false

## 前フレームの重心（相対移動計算用）
var _prev_centroid: Vector2 = Vector2.ZERO

## 前フレームの標準偏差（ピンチ計算用）
var _prev_std_deviation: float = 0.0

#endregion


func _init() -> void:
	tap_threshold = TOUCH_TAP_THRESHOLD


## タッチ入力がアクティブかどうかを取得
func is_touch_active() -> bool:
	return _touch_active


## ピンチ中かどうかを取得（オーバーライド）
func is_pinching() -> bool:
	return _is_pinching


## タッチポイント数を取得（オーバーライド）
func get_touch_count() -> int:
	return _touch_points.size()


## 入力イベントを処理
## @param event: 入力イベント
## @return: イベントを消費した場合true
func handle_input(event: InputEvent) -> bool:
	# タッチイベント
	if event is InputEventScreenTouch:
		return _handle_screen_touch(event as InputEventScreenTouch)

	# タッチドラッグイベント
	if event is InputEventScreenDrag:
		return _handle_screen_drag(event as InputEventScreenDrag)

	return false


## 状態をリセット（オーバーライド）
func reset_state() -> void:
	super.reset_state()
	_touch_active = false
	_touch_points.clear()
	_is_pinching = false
	_prev_centroid = Vector2.ZERO
	_prev_std_deviation = 0.0


#region プライベートメソッド

## タッチイベントを処理
func _handle_screen_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		# タッチ開始
		_touch_active = true
		_touch_points[event.index] = event.position

		# 2本指以上でピンチ開始
		if _touch_points.size() == 2:
			_start_pinch()
		elif _touch_points.size() == 1:
			# 1本指タッチ開始
			_on_press(event.position)
	else:
		# タッチ終了
		_touch_points.erase(event.index)

		# ピンチ終了判定
		if _touch_points.size() < 2 and _is_pinching:
			_end_pinch()

		# 最後のタッチが離れた場合
		if _touch_points.size() == 0:
			_touch_active = false
			_on_release(event.position)

	return true


## タッチドラッグイベントを処理
func _handle_screen_drag(event: InputEventScreenDrag) -> bool:
	# タッチポイントを更新
	if _touch_points.has(event.index):
		_touch_points[event.index] = event.position

	# ピンチ中は2本指ズーム処理
	if _is_pinching and _touch_points.size() >= 2:
		_update_pinch_zoom()
		return true

	# 1本指ドラッグ
	if _touch_points.size() == 1 and _is_pressed:
		_on_drag(event.position)
		return true

	return false


## ピンチ開始
func _start_pinch() -> void:
	_is_pinching = true
	_is_pending_drag = false
	_is_dragging = false
	_prev_centroid = _calc_centroid()
	_prev_std_deviation = _calc_std_deviation(_prev_centroid)
	pinch_state_changed.emit(true)


## ピンチ終了
func _end_pinch() -> void:
	_is_pinching = false
	pinch_state_changed.emit(false)


## 2本指ピンチでズーム処理
func _update_pinch_zoom() -> void:
	if _touch_points.size() < 2:
		return

	var current_centroid := _calc_centroid()
	var current_std_deviation := _calc_std_deviation(current_centroid)

	var scale_pinch := current_std_deviation / _prev_std_deviation if _prev_std_deviation > 0 else 1.0

	_prev_centroid = current_centroid
	_prev_std_deviation = current_std_deviation

	# ズーム処理
	# scale_pinch > 1.0 = 指が広がった = ズームイン = 負の値
	# scale_pinch < 1.0 = 指が近づいた = ズームアウト = 正の値
	var zoom_delta := (1.0 - scale_pinch) * 5.0
	zoom_requested.emit(zoom_delta)


## 重心を計算
func _calc_centroid() -> Vector2:
	var c := Vector2.ZERO
	for p in _touch_points:
		c += _touch_points[p]
	return c / _touch_points.size()


## 標準偏差を計算（指の広がり具合）
func _calc_std_deviation(centroid: Vector2) -> float:
	var d := 0.0
	for p in _touch_points:
		d += centroid.distance_squared_to(_touch_points[p])
	return sqrt(d / _touch_points.size())

#endregion
