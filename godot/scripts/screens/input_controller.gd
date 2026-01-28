class_name InputController
extends Node
## ゲーム画面の入力処理をまとめたコントローラー
## PC: 左クリックドラッグでカメラ移動 / クリックでキャラクター選択等
## モバイル: 2本指でカメラパン+ズーム、1本指はパス描画/タップ操作用
## パスモード時は優先順位に応じてPathDrawerまたはカメラ移動に委譲

var game_manager: GameManager = null
var camera_pan_controller: CameraPanController = null

## 左クリック押下時のスクリーン座標（ドラッグ判定用）
var _left_click_start_pos: Vector2 = Vector2.ZERO
## 左クリック中かどうか
var _left_button_pressed: bool = false


func setup(manager: GameManager, pan_controller: CameraPanController) -> void:
	game_manager = manager
	camera_pan_controller = pan_controller


## タッチ入力があるかどうか（マウスエミュレーション判定用）
func _is_touch_active() -> bool:
	return camera_pan_controller and camera_pan_controller.get_touch_count() > 0


func _unhandled_input(event: InputEvent) -> void:
	if not game_manager:
		return

	# ピンチ中はマウスイベントを完全に無視
	if camera_pan_controller and camera_pan_controller.is_pinching():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			return

	# 1本指タッチ中のマウスドラッグは、パスモード以外では無視（カメラパン防止）
	# パスモード中はPathDrawerがマウスイベントで描画するため許可
	if camera_pan_controller and camera_pan_controller.get_touch_count() == 1:
		if event is InputEventMouseMotion and not game_manager.is_path_mode():
			get_viewport().set_input_as_handled()
			return

	# タッチ入力の処理
	if camera_pan_controller:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			# タッチポイントを常に追跡（ピンチ検出のため）
			camera_pan_controller.track_touch(event)

			# 2本指以上、またはピンチ中はカメラズーム+パンを最優先（パスモード中でも）
			if camera_pan_controller.get_touch_count() >= 2 or camera_pan_controller.is_pinching():
				if camera_pan_controller.handle_pinch(event):
					get_viewport().set_input_as_handled()
					return

			# 1本指タッチ - パス描画などに使用（PathDrawerに委譲）
			# カメラパンはしない
			return

	# カメラズーム（マウスホイール）は常に処理
	if camera_pan_controller:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_pan_controller.handle_input(event)
				return

	# 回転モード中
	if game_manager.is_rotation_active() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			game_manager.handle_rotation_input(event.position)
		return

	# 左クリック処理（PC向け - タッチエミュレーションではない場合のみ）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(event)
		return

	# 左クリック中のマウス移動（PC向け）
	if event is InputEventMouseMotion and _left_button_pressed:
		_handle_left_drag(event)
		return


## 左クリック押下/解放の処理
func _handle_left_click(event: InputEventMouseButton) -> void:
	if event.pressed:
		_left_button_pressed = true
		_left_click_start_pos = event.position
		_on_left_press(event.position)
	else:
		_on_left_release(event.position)
		_left_button_pressed = false


## 左クリック押下時の処理
func _on_left_press(pos: Vector2) -> void:
	# タッチ中はカメラドラッグを開始しない（タップ操作のみ許可）
	var is_touch = _is_touch_active()

	# パスモードOFF → カメラドラッグ候補開始（PCのみ）
	if not game_manager.is_path_mode():
		if camera_pan_controller and not is_touch:
			camera_pan_controller.start_potential_drag(pos)
		return

	# パスモードON
	var path_drawer = _get_path_drawer()
	if not path_drawer:
		return

	# MOVEMENTモード → PathDrawerに委譲（何もしない、_unhandled_inputで処理される）
	if not path_drawer.is_marker_mode():
		return

	# マーカーモード → パス上かどうかで分岐
	var ground_pos = _get_ground_position(pos)
	if ground_pos != null and path_drawer.is_point_on_path(ground_pos):
		# パス上 → PathDrawerに委譲（何もしない）
		return
	else:
		# パス外 → カメラドラッグ候補開始（PCのみ）
		if camera_pan_controller and not is_touch:
			camera_pan_controller.start_potential_drag(pos)


## 左ドラッグ中の処理
func _handle_left_drag(event: InputEventMouseMotion) -> void:
	# カメラドラッグ中ならカメラ移動
	if camera_pan_controller and camera_pan_controller.is_dragging():
		camera_pan_controller.handle_input(event)
		get_viewport().set_input_as_handled()
		return

	# カメラドラッグ候補中なら閾値チェック
	if camera_pan_controller and camera_pan_controller.is_pending_drag():
		if camera_pan_controller.check_and_start_drag(event.position):
			# ドラッグ成立
			get_viewport().set_input_as_handled()
		return

	# パスモードON + MOVEMENTモード → PathDrawerが処理（何もしない）


## 左クリック解放時の処理
func _on_left_release(pos: Vector2) -> void:
	# カメラドラッグ中だった場合 → ドラッグ終了
	if camera_pan_controller and camera_pan_controller.is_dragging():
		camera_pan_controller.end_drag()
		return

	# カメラドラッグ候補中だった場合 → クリックとして処理
	if camera_pan_controller and camera_pan_controller.is_pending_drag():
		camera_pan_controller.cancel_potential_drag()
		_handle_click(pos)
		return

	# タッチからのタップ、またはパスモードON → クリックとして処理
	_handle_click(pos)


## クリックとして処理（ドラッグ不成立時）
func _handle_click(pos: Vector2) -> void:
	# パスモード中：パス描画後にキャラクター以外をクリックでキャンセル
	if game_manager.is_path_mode():
		if game_manager.has_pending_path():
			var path_drawer = _get_path_drawer()
			if path_drawer and path_drawer.is_marker_mode():
				# マーカーモード中はPathDrawerが処理
				return
			var clicked = game_manager.raycast_character(pos)
			if game_manager.path_service:
				game_manager.path_service.handle_click_to_cancel(clicked)
		return

	# 通常クリック処理
	if not game_manager.is_rotation_active() and not game_manager.is_path_mode():
		game_manager.handle_click(pos, MOUSE_BUTTON_LEFT)


## PathDrawerを取得
func _get_path_drawer() -> PathDrawer:
	return game_manager.path_drawer as PathDrawer


## スクリーン座標から地面座標を取得
func _get_ground_position(screen_pos: Vector2) -> Variant:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_direction = camera.project_ray_normal(screen_pos)
	var ground_plane = Plane(Vector3.UP, 0.0)

	var intersection = ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		return intersection as Vector3
	return null


func _input(event: InputEvent) -> void:
	if not game_manager:
		return

	# ESCキー処理
	if event.is_action_pressed("ui_cancel"):
		if game_manager.is_any_path_following_active():
			game_manager.cancel_all_path_following()
		elif game_manager.is_rotation_active():
			game_manager.cancel_rotation()
		elif game_manager.is_path_mode():
			game_manager.cancel_path()
