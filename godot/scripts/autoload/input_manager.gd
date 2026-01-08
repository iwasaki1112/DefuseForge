extends Node

## 入力システム統合マネージャー
## 全てのタッチ/マウス入力を一箇所で管理し、シグナルで各システムに通知

# ジェスチャータイプ
enum GestureType { NONE, DRAWING, CAMERA }

# シグナル - パス描画関連
signal draw_started(screen_pos: Vector2, world_pos: Vector3)
signal draw_moved(screen_pos: Vector2, world_pos: Vector3)
signal draw_ended(screen_pos: Vector2)

# シグナル - カメラ操作関連
signal camera_zoom(zoom_delta: float)
signal camera_pan(delta: Vector2)

# シグナル - ジェスチャー状態変更
signal gesture_changed(new_gesture: GestureType)

# 設定
@export var gesture_confirm_delay: float = 0.1  # 100ms

# 内部状態
var current_gesture: GestureType = GestureType.NONE
var touch_points: Dictionary = {}  # index -> Vector2
var gesture_start_time: float = 0.0
var pending_position: Vector2 = Vector2.ZERO
var drawing_finger_index: int = -1
var last_touch_distance: float = 0.0
var last_touch_center: Vector2 = Vector2.ZERO

# カメラ参照（ワールド座標変換用）
var camera: Camera3D = null


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()

	# ペンディング状態の処理
	if current_gesture == GestureType.NONE and touch_points.size() == 1 and gesture_start_time > 0:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - gesture_start_time
		if elapsed >= gesture_confirm_delay:
			_set_gesture(GestureType.DRAWING)
			var world_pos := _get_world_position(pending_position)
			draw_started.emit(pending_position, world_pos)


func _input(event: InputEvent) -> void:
	# プレイ中でない場合は入力を無視
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	# マウス入力
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)

	# タッチ入力
	if event is InputEventScreenTouch:
		_handle_touch(event)
	if event is InputEventScreenDrag:
		_handle_touch_drag(event)


## マウスボタン処理
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_set_gesture(GestureType.DRAWING)
			var world_pos := _get_world_position(event.position)
			draw_started.emit(event.position, world_pos)
		else:
			draw_ended.emit(event.position)
			_set_gesture(GestureType.NONE)

	# マウスホイールでズーム
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_zoom.emit(-1.0)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_zoom.emit(1.0)


## マウス移動処理
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if current_gesture == GestureType.DRAWING:
		var world_pos := _get_world_position(event.position)
		draw_moved.emit(event.position, world_pos)


## タッチ開始/終了処理
func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		touch_points[event.index] = event.position

		match touch_points.size():
			1:
				# 最初のタッチ - ペンディング状態へ
				gesture_start_time = Time.get_ticks_msec() / 1000.0
				pending_position = event.position
				drawing_finger_index = event.index

			2:
				# 2本目のタッチ - カメラ操作へ切り替え
				if current_gesture == GestureType.DRAWING:
					draw_ended.emit(pending_position)
				_set_gesture(GestureType.CAMERA)
				_init_two_finger_gesture()
				drawing_finger_index = -1
				gesture_start_time = 0.0

			_:
				# 3本指以上 - カメラ操作継続
				pass
	else:
		touch_points.erase(event.index)

		if touch_points.size() == 0:
			# 全ての指が離れた
			if current_gesture == GestureType.DRAWING:
				draw_ended.emit(event.position)
			_set_gesture(GestureType.NONE)
			drawing_finger_index = -1
			gesture_start_time = 0.0


## タッチドラッグ処理
func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if not touch_points.has(event.index):
		return

	touch_points[event.index] = event.position

	match current_gesture:
		GestureType.DRAWING:
			if event.index == drawing_finger_index:
				var world_pos := _get_world_position(event.position)
				draw_moved.emit(event.position, world_pos)

		GestureType.CAMERA:
			if touch_points.size() >= 2:
				_handle_two_finger_gesture()


## 2本指ジェスチャーの初期化
func _init_two_finger_gesture() -> void:
	var positions = touch_points.values()
	if positions.size() < 2:
		return
	last_touch_distance = positions[0].distance_to(positions[1])
	last_touch_center = (positions[0] + positions[1]) / 2.0


## 2本指ジェスチャー処理
func _handle_two_finger_gesture() -> void:
	var positions = touch_points.values()
	if positions.size() < 2:
		return

	var current_distance: float = positions[0].distance_to(positions[1])
	var current_center: Vector2 = (positions[0] + positions[1]) / 2.0

	# ピンチズーム（ゼロ除算防止）
	if last_touch_distance > 0 and current_distance > 0.01:
		var zoom_factor := last_touch_distance / current_distance
		var zoom_delta := (zoom_factor - 1.0) * 10.0  # スケール調整
		camera_zoom.emit(zoom_delta)

	# パン
	var delta_center := current_center - last_touch_center
	camera_pan.emit(delta_center)

	# 状態を更新
	last_touch_distance = current_distance
	last_touch_center = current_center


## ジェスチャー状態を設定
func _set_gesture(new_gesture: GestureType) -> void:
	if current_gesture != new_gesture:
		current_gesture = new_gesture
		gesture_changed.emit(new_gesture)


## スクリーン座標からワールド座標を取得
func _get_world_position(screen_pos: Vector2) -> Vector3:
	if camera == null:
		return Vector3.INF

	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2  # 地形レイヤー

	var result := space_state.intersect_ray(query)
	if result:
		return result.position

	return Vector3.INF


## 現在のジェスチャータイプを取得
func get_gesture_type() -> GestureType:
	return current_gesture


## パス描画中かどうか
func is_drawing() -> bool:
	return current_gesture == GestureType.DRAWING


## カメラ操作中かどうか
func is_camera_mode() -> bool:
	return current_gesture == GestureType.CAMERA
