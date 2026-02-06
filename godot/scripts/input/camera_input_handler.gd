class_name CameraInputHandler
extends RefCounted
## カメラ入力処理ハンドラ
##
## 責務:
## - CameraPanControllerへの委譲
## - マウスホイール/トラックパッドのズーム
## - マウスドラッグ/タッチパンによるカメラ移動
## - ピンチズーム


#region 依存関係

var camera_pan_controller: CameraPanController = null

#endregion


#region 初期化

func setup(pan_controller: CameraPanController) -> void:
	camera_pan_controller = pan_controller

#endregion


#region ズーム処理

## マウスホイール/トラックパッドズーム
func handle_mouse_zoom(amount: float) -> void:
	if camera_pan_controller:
		camera_pan_controller._zoom_by(amount)

#endregion


#region ドラッグ処理（マウス）

func start_drag(pos: Vector2) -> void:
	if camera_pan_controller:
		camera_pan_controller.start_potential_drag(pos)


func check_and_start_drag(pos: Vector2) -> void:
	if camera_pan_controller:
		camera_pan_controller.check_and_start_drag(pos)


func update_drag(event: InputEventMouseMotion) -> void:
	if camera_pan_controller:
		camera_pan_controller.handle_input(event)


func end_drag() -> void:
	if camera_pan_controller:
		camera_pan_controller.end_drag()


func cancel_drag() -> void:
	if camera_pan_controller:
		camera_pan_controller.cancel_potential_drag()


func is_dragging() -> bool:
	return camera_pan_controller and camera_pan_controller.is_dragging()


func is_pending_drag() -> bool:
	return camera_pan_controller and camera_pan_controller.is_pending_drag()

#endregion


#region タッチパン処理

func start_touch_pan(pos: Vector2) -> void:
	if camera_pan_controller:
		camera_pan_controller.start_potential_touch_pan(pos)


func check_and_start_touch_pan(pos: Vector2) -> void:
	if camera_pan_controller:
		camera_pan_controller.check_and_start_touch_pan(pos)


func update_touch_pan(pos: Vector2) -> void:
	if camera_pan_controller:
		camera_pan_controller.update_touch_pan(pos)


func end_touch_pan() -> void:
	if camera_pan_controller:
		camera_pan_controller.end_touch_pan()


func cancel_touch_pan() -> void:
	if camera_pan_controller:
		camera_pan_controller.cancel_potential_touch_pan()


func is_touch_panning() -> bool:
	return camera_pan_controller and camera_pan_controller.is_touch_panning()


func is_pending_touch_pan() -> bool:
	return camera_pan_controller and camera_pan_controller.is_pending_touch_pan()

#endregion


#region ピンチズーム処理

func handle_pinch(event: InputEvent) -> bool:
	if camera_pan_controller:
		return camera_pan_controller.handle_pinch(event)
	return false


func track_touch(event: InputEvent) -> void:
	if camera_pan_controller:
		camera_pan_controller.track_touch(event)


func get_touch_count() -> int:
	if camera_pan_controller:
		return camera_pan_controller.get_touch_count()
	return 0

#endregion
