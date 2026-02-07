class_name CameraPanController
extends RefCounted
## カメラを平行移動、ズームする簡易コントローラー
## PC: 1本指ドラッグでパン、マウスホイールでズーム
## モバイル: 1本指でパン、2本指でズーム
## パスモード時は1本指でパス描画
## 参考: https://github.com/DionHo/GodotTouchCamera

var camera: Camera3D = null
var pan_speed: float = 0.05

## モバイル向けパン速度
var mobile_pan_speed: float = 0.02

## ズーム設定
var zoom_speed: float = 1.0
var zoom_min: float = 12.0
var zoom_max: float = 25.0
var zoom_smoothing: float = 10.0

## ドラッグ判定の閾値（ピクセル）
const DRAG_THRESHOLD: float = 5.0

## 内部状態（PCマウスドラッグ用）
var _drag_active: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_start_target: Vector2 = Vector2.ZERO  # ドラッグ開始時のターゲット位置
var _pending_drag: bool = false
var _pending_start: Vector2 = Vector2.ZERO

## 内部状態（ズーム）
var _target_zoom: float = 0.0
var _current_zoom: float = 0.0

## カメラが見ている地上のターゲット位置（XZ平面）
var _ground_target: Vector2 = Vector2.ZERO  # 現在位置
var _target_ground: Vector2 = Vector2.ZERO  # 目標位置
var _is_animating_to_target: bool = false   # アニメーション中フラグ

## パンアニメーション設定
var pan_smoothing: float = 8.0  # パンのスムージング速度

## 内部状態（マルチタッチ）
var _touch_points: Dictionary = {}  # touch_index -> position
var _is_pinching: bool = false

## 前フレームの重心と標準偏差（相対移動計算用）
var _prev_centroid: Vector2 = Vector2.ZERO
var _prev_std_deviation: float = 0.0

## 内部状態（1本指タッチパン）
var _prev_touch_pos: Vector2 = Vector2.ZERO
var _is_touch_panning: bool = false
var _pending_touch_pan: bool = false
var _touch_pan_start: Vector2 = Vector2.ZERO


func setup(target_camera: Camera3D, speed: float = 0.05) -> void:
	camera = target_camera
	pan_speed = speed
	if camera:
		_current_zoom = camera.global_position.y
		_target_zoom = _current_zoom
		# 初期ターゲット位置を計算
		_ground_target = _calculate_ground_target_from_camera()
		_target_ground = _ground_target


## ピンチ中かどうかを取得
func is_pinching() -> bool:
	return _is_pinching


## 現在のタッチポイント数を取得
func get_touch_count() -> int:
	return _touch_points.size()


## タッチポイントを追跡（2本指検出用）
func track_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
			if _touch_points.size() == 2:
				_start_pinch()
		else:
			_touch_points.erase(event.index)
			if _touch_points.size() < 2:
				_is_pinching = false
	elif event is InputEventScreenDrag:
		if _touch_points.has(event.index):
			_touch_points[event.index] = event.position


## 2本指ピンチズーム処理
func handle_pinch(event: InputEvent) -> bool:
	if not camera:
		return false

	if event is InputEventScreenDrag:
		if _touch_points.size() == 2 and _is_pinching:
			_update_pinch_zoom()
			return true

	return _is_pinching


## ズームレベルに応じたパン速度を取得
func _get_adjusted_pan_speed(base_speed: float) -> float:
	if not camera:
		return base_speed
	var zoom_ratio = (_current_zoom - zoom_min) / (zoom_max - zoom_min)
	var speed_multiplier = 0.5 + (zoom_ratio * 0.5)
	return base_speed * speed_multiplier


## PC向け入力処理（マウスホイール、マウスドラッグ）
func handle_input(event: InputEvent) -> bool:
	if not camera:
		return false

	# ピンチ中はマウスドラッグを無視（タッチエミュレーション対策）
	if _is_pinching and event is InputEventMouseMotion:
		return true

	# ドラッグ中のマウス移動処理
	if event is InputEventMouseMotion and _drag_active and not _is_pinching:
		var delta = event.position - _drag_start
		var adjusted_speed = _get_adjusted_pan_speed(pan_speed)
		var move_x = -delta.x * adjusted_speed
		var move_z = -delta.y * adjusted_speed
		# ターゲット位置を更新（開始位置からの差分、アニメーションなし）
		_ground_target = _drag_start_target + Vector2(move_x, move_z)
		_target_ground = _ground_target
		return true

	# マウスホイールでズーム
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(-zoom_speed)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(zoom_speed)
			return true

	return false


## ドラッグ候補を開始（左クリック押下時に呼び出す）
func start_potential_drag(pos: Vector2) -> void:
	if not camera:
		return
	_pending_drag = true
	_pending_start = pos


## ドラッグが成立したかチェック
func check_and_start_drag(current_pos: Vector2) -> bool:
	if not _pending_drag:
		return false

	var distance = _pending_start.distance_to(current_pos)
	if distance >= DRAG_THRESHOLD:
		_drag_active = true
		_drag_start = _pending_start
		_drag_start_target = _ground_target  # ドラッグ開始時のターゲット位置を保存
		_is_animating_to_target = false  # アニメーションをキャンセル
		_pending_drag = false
		return true

	return false


## ドラッグ中かどうか
func is_dragging() -> bool:
	return _drag_active


## ドラッグ候補中かどうか
func is_pending_drag() -> bool:
	return _pending_drag


## ドラッグを終了
func end_drag() -> void:
	_drag_active = false
	_pending_drag = false


## ドラッグ候補をキャンセル
func cancel_potential_drag() -> void:
	_pending_drag = false


## マウスホイールによるズーム
func _zoom_by(amount: float) -> void:
	_target_zoom = clampf(_target_zoom + amount, zoom_min, zoom_max)


## ========================================
## Macトラックパッドジェスチャー処理
## ========================================

## トラックパッドのピンチ（Magnify）ジェスチャー処理
## factor: 1.0 = 変化なし, >1.0 = ズームイン, <1.0 = ズームアウト
func handle_magnify_gesture(factor: float) -> void:
	# factorを反転してズームに変換（ピンチイン = ズームアウト = カメラが遠ざかる）
	var zoom_delta = (1.0 - factor) * _current_zoom * 0.5
	_target_zoom = clampf(_target_zoom + zoom_delta, zoom_min, zoom_max)


## ピンチ開始時の処理
func _start_pinch() -> void:
	_is_pinching = true
	_pending_drag = false
	_drag_active = false
	_prev_centroid = _calc_centroid()
	_prev_std_deviation = _calc_std_deviation(_prev_centroid)


## 重心を計算
func _calc_centroid() -> Vector2:
	var c = Vector2.ZERO
	for p in _touch_points:
		c += _touch_points[p]
	return c / _touch_points.size()


## 標準偏差を計算（指の広がり具合）
func _calc_std_deviation(centroid: Vector2) -> float:
	var d = 0.0
	for p in _touch_points:
		d += centroid.distance_squared_to(_touch_points[p])
	return sqrt(d / _touch_points.size())


## 2本指ピンチでズーム処理
func _update_pinch_zoom() -> void:
	if not camera or _touch_points.size() < 2:
		return

	var current_centroid = _calc_centroid()
	var current_std_deviation = _calc_std_deviation(current_centroid)

	var scale_pinch = current_std_deviation / _prev_std_deviation if _prev_std_deviation > 0 else 1.0

	_prev_centroid = current_centroid
	_prev_std_deviation = current_std_deviation

	# ズーム処理
	var zoom_delta = (1.0 - scale_pinch) * _current_zoom * 0.5
	_target_zoom = clampf(_target_zoom + zoom_delta, zoom_min, zoom_max)


## 1本指タッチパン候補開始（タップとドラッグを区別するため）
func start_potential_touch_pan(pos: Vector2) -> void:
	_pending_touch_pan = true
	_touch_pan_start = pos


## 1本指タッチパンが成立したかチェック
func check_and_start_touch_pan(current_pos: Vector2) -> bool:
	if not _pending_touch_pan:
		return false

	var distance = _touch_pan_start.distance_to(current_pos)
	if distance >= DRAG_THRESHOLD:
		_is_touch_panning = true
		_prev_touch_pos = current_pos
		_is_animating_to_target = false  # アニメーションをキャンセル
		_pending_touch_pan = false
		return true

	return false


## 1本指タッチパン候補中かどうか
func is_pending_touch_pan() -> bool:
	return _pending_touch_pan


## 1本指タッチパン候補をキャンセル
func cancel_potential_touch_pan() -> void:
	_pending_touch_pan = false


## 1本指タッチパンを即座に開始（閾値チェックなし）
func start_touch_pan(pos: Vector2) -> void:
	_prev_touch_pos = pos
	_is_touch_panning = true
	_is_animating_to_target = false  # アニメーションをキャンセル
	_pending_touch_pan = false


## 1本指タッチパン更新（2本指パンと同じ滑らかな実装）
func update_touch_pan(current_pos: Vector2) -> bool:
	if not camera or not _is_touch_panning:
		return false

	var relative_drag = current_pos - _prev_touch_pos
	_prev_touch_pos = current_pos

	var adjusted_speed = _get_adjusted_pan_speed(mobile_pan_speed)
	var move_x = -relative_drag.x * adjusted_speed
	var move_z = -relative_drag.y * adjusted_speed
	# ターゲット位置を更新（アニメーションなし）
	_ground_target += Vector2(move_x, move_z)
	_target_ground = _ground_target

	return true


## 1本指タッチパン終了
func end_touch_pan() -> void:
	_is_touch_panning = false
	_pending_touch_pan = false
	_prev_touch_pos = Vector2.ZERO


## 1本指パン中かどうか
func is_touch_panning() -> bool:
	return _is_touch_panning


## 毎フレーム呼び出してズームとパンを滑らかに適用
func process(delta: float) -> void:
	if not camera:
		return

	# ズームのスムージング
	if not is_equal_approx(_current_zoom, _target_zoom):
		_current_zoom = lerpf(_current_zoom, _target_zoom, zoom_smoothing * delta)

		if absf(_current_zoom - _target_zoom) < 0.01:
			_current_zoom = _target_zoom

	# パンのスムージング（アニメーション中のみ）
	if _is_animating_to_target:
		_ground_target = _ground_target.lerp(_target_ground, pan_smoothing * delta)

		if _ground_target.distance_to(_target_ground) < 0.01:
			_ground_target = _target_ground
			_is_animating_to_target = false

	# ターゲット位置を基準にカメラ位置を更新
	_update_camera_position_from_target()


## ターゲット位置を基準にカメラ位置を更新
func _update_camera_position_from_target() -> void:
	if not camera:
		return
	var z_offset := _calculate_z_offset(_current_zoom)
	camera.global_position = Vector3(_ground_target.x, _current_zoom, _ground_target.y + z_offset)


## 現在のカメラ位置から地上のターゲット位置を計算
func _calculate_ground_target_from_camera() -> Vector2:
	if not camera:
		return Vector2.ZERO
	var z_offset := _calculate_z_offset(camera.global_position.y)
	return Vector2(camera.global_position.x, camera.global_position.z - z_offset)


## ターゲット位置を設定（アニメーション付き）
func set_ground_target(target: Vector3) -> void:
	_target_ground = Vector2(target.x, target.z)
	_is_animating_to_target = true


## ターゲット位置を即座に設定（アニメーションなし）
func set_ground_target_immediate(target: Vector3) -> void:
	_ground_target = Vector2(target.x, target.z)
	_target_ground = _ground_target
	_is_animating_to_target = false


## ターゲット位置を移動（パン用）- アニメーションをキャンセル
func move_ground_target(delta_x: float, delta_z: float) -> void:
	_is_animating_to_target = false
	_ground_target.x += delta_x
	_ground_target.y += delta_z
	_target_ground = _ground_target


## カメラ高さからZオフセットを計算（角度に基づく）
func _calculate_z_offset(height: float) -> float:
	if not camera:
		return 0.0
	return height * tan(PI / 2.0 + camera.rotation.x)
