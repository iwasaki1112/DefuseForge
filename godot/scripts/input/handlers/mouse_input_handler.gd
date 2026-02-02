class_name MouseInputHandler
extends InputDeviceHandler
## マウス入力ハンドラ
##
## 責務:
## - マウスボタン（左クリック）の処理
## - マウス移動（ドラッグ）の処理
## - マウスホイール（ズーム）の処理
## - トラックパッドジェスチャー（ピンチズーム）の処理
##
## 対応イベント:
## - InputEventMouseButton
## - InputEventMouseMotion
## - InputEventMagnifyGesture


#region 設定

## マウス用タップ判定閾値（PCは精度が高いため大きめ）
const MOUSE_TAP_THRESHOLD: float = 50.0

## ズーム速度
var zoom_speed: float = 1.0

## 最後のタッチイベント時刻（エミュレートマウスイベント対策）
var _last_touch_time: int = 0

## タッチイベントとマウスイベントの間隔閾値（ミリ秒）
const TOUCH_MOUSE_INTERVAL_MS: int = 100

#endregion


func _init() -> void:
	tap_threshold = MOUSE_TAP_THRESHOLD


## タッチイベント時刻を記録（エミュレートマウスイベント対策用）
func record_touch_time() -> void:
	_last_touch_time = Time.get_ticks_msec()


## 入力イベントを処理
## @param event: 入力イベント
## @return: イベントを消費した場合true
func handle_input(event: InputEvent) -> bool:
	# タッチ直後のエミュレートマウスイベントはスキップ
	if Time.get_ticks_msec() - _last_touch_time < TOUCH_MOUSE_INTERVAL_MS:
		return false

	# マウスボタンイベント
	if event is InputEventMouseButton:
		return _handle_mouse_button(event as InputEventMouseButton)

	# マウス移動イベント
	if event is InputEventMouseMotion:
		return _handle_mouse_motion(event as InputEventMouseMotion)

	# トラックパッドピンチジェスチャー
	if event is InputEventMagnifyGesture:
		return _handle_magnify_gesture(event as InputEventMagnifyGesture)

	return false


#region プライベートメソッド

## マウスボタンイベントを処理
func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	# 左クリック
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release(event.position)
		return true

	# マウスホイール（ズーム）
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_requested.emit(-zoom_speed)
		return true
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_requested.emit(zoom_speed)
		return true

	return false


## マウス移動イベントを処理
func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _is_pressed:
		return false

	_on_drag(event.position)
	return true


## トラックパッドピンチジェスチャーを処理
func _handle_magnify_gesture(event: InputEventMagnifyGesture) -> bool:
	# factor が 1.0 から十分離れている場合のみ処理
	if absf(event.factor - 1.0) > 0.01:
		# factorを反転してズームに変換
		# factor > 1.0 = ピンチアウト = ズームイン = 負の値
		# factor < 1.0 = ピンチイン = ズームアウト = 正の値
		var zoom_delta := (1.0 - event.factor) * zoom_speed * 5.0
		zoom_requested.emit(zoom_delta)
		return true
	return false

#endregion
