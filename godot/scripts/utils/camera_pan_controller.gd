class_name CameraPanController
extends RefCounted
## 左ドラッグでカメラを平行移動、スクロール/ピンチでズームする簡易コントローラー
## ドラッグ判定: 閾値以上移動したらドラッグ成立

var camera: Camera3D = null
var pan_speed: float = 0.05

## ズーム設定
var zoom_speed: float = 1.0
var zoom_min: float = 12.0
var zoom_max: float = 20.0
var zoom_smoothing: float = 10.0

## ドラッグ判定の閾値（ピクセル）
const DRAG_THRESHOLD: float = 5.0

## 内部状態（パン）
var _drag_active: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_start_pos: Vector3 = Vector3.ZERO

## ドラッグ候補状態（閾値判定前）
var _pending_drag: bool = false
var _pending_start: Vector2 = Vector2.ZERO

## 内部状態（ズーム）
var _target_zoom: float = 0.0
var _current_zoom: float = 0.0

## 内部状態（ピンチズーム）
var _touch_points: Dictionary = {}  # touch_index -> position
var _pinch_start_distance: float = 0.0
var _pinch_start_zoom: float = 0.0


func setup(target_camera: Camera3D, speed: float = 0.05) -> void:
	camera = target_camera
	pan_speed = speed
	if camera:
		_current_zoom = camera.global_position.y
		_target_zoom = _current_zoom


## 入力処理。処理した場合はtrueを返す
## 注: 左クリックドラッグはInputControllerから呼び出されるAPIを使用
func handle_input(event: InputEvent) -> bool:
	if not camera:
		return false

	# ドラッグ中のマウス移動処理
	if event is InputEventMouseMotion and _drag_active:
		var delta = event.position - _drag_start
		var move_x = -delta.x * pan_speed
		var move_z = -delta.y * pan_speed
		camera.global_position = _camera_start_pos + Vector3(move_x, 0, move_z)
		return true

	# マウスホイールでズーム（PC）
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(-zoom_speed)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(zoom_speed)
			return true

	# タッチ入力（ピンチズーム用）
	if event is InputEventScreenTouch:
		return _handle_touch(event)

	if event is InputEventScreenDrag:
		return _handle_touch_drag(event)

	return false


## ドラッグ候補を開始（左クリック押下時に呼び出す）
func start_potential_drag(pos: Vector2) -> void:
	if not camera:
		return
	_pending_drag = true
	_pending_start = pos


## ドラッグが成立したかチェックし、成立したらドラッグモードに移行
## @param current_pos: 現在のマウス位置
## @return: ドラッグが成立した場合true
func check_and_start_drag(current_pos: Vector2) -> bool:
	if not _pending_drag:
		return false

	var distance = _pending_start.distance_to(current_pos)
	if distance >= DRAG_THRESHOLD:
		# ドラッグ成立
		_drag_active = true
		_drag_start = _pending_start
		_camera_start_pos = camera.global_position
		_pending_drag = false
		return true

	return false


## ドラッグ中かどうか
func is_dragging() -> bool:
	return _drag_active


## ドラッグ候補中かどうか（閾値判定前）
func is_pending_drag() -> bool:
	return _pending_drag


## ドラッグを終了
func end_drag() -> void:
	_drag_active = false
	_pending_drag = false


## ドラッグ候補をキャンセル（閾値未達でクリックとして処理する場合）
func cancel_potential_drag() -> void:
	_pending_drag = false


## マウスホイールによるズーム
func _zoom_by(amount: float) -> void:
	_target_zoom = clampf(_target_zoom + amount, zoom_min, zoom_max)


## タッチ開始/終了を処理
func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		_touch_points[event.index] = event.position
		# 2本指になったらピンチ開始
		if _touch_points.size() == 2:
			_start_pinch()
	else:
		_touch_points.erase(event.index)
		# ピンチ終了
		if _touch_points.size() < 2:
			_pinch_start_distance = 0.0

	return _touch_points.size() >= 2


## タッチドラッグを処理
func _handle_touch_drag(event: InputEventScreenDrag) -> bool:
	if not _touch_points.has(event.index):
		return false

	_touch_points[event.index] = event.position

	# 2本指ならピンチズーム処理
	if _touch_points.size() == 2 and _pinch_start_distance > 0.0:
		_update_pinch()
		return true

	return false


## ピンチ開始時の処理
func _start_pinch() -> void:
	var points = _touch_points.values()
	_pinch_start_distance = points[0].distance_to(points[1])
	_pinch_start_zoom = _target_zoom


## ピンチ中の処理
func _update_pinch() -> void:
	var points = _touch_points.values()
	var current_distance = points[0].distance_to(points[1])

	if _pinch_start_distance > 0.0:
		# ピンチアウト（指を広げる）→ズームイン（カメラが近づく）
		# ピンチイン（指を狭める）→ズームアウト（カメラが離れる）
		var scale_factor = _pinch_start_distance / current_distance
		_target_zoom = clampf(_pinch_start_zoom * scale_factor, zoom_min, zoom_max)


## 毎フレーム呼び出してズームを滑らかに適用
func process(delta: float) -> void:
	if not camera:
		return

	# 目標値に向かってスムーズに補間
	if not is_equal_approx(_current_zoom, _target_zoom):
		_current_zoom = lerpf(_current_zoom, _target_zoom, zoom_smoothing * delta)

		# 十分近づいたらスナップ
		if absf(_current_zoom - _target_zoom) < 0.01:
			_current_zoom = _target_zoom

		# カメラのY座標を更新
		camera.global_position.y = _current_zoom
