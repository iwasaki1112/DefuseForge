class_name InputController
extends Node
## ゲーム画面の入力処理
##
## 責務:
## - カメラ操作（パン、ズーム）
## - クリック/タップの検出とGameManagerへの委譲
## - パスモード中はPathDrawerに委譲

var game_manager: GameManager = null
var camera_pan_controller: CameraPanController = null

## 左クリック押下時のスクリーン座標（ドラッグ判定用）
var _left_click_start_pos: Vector2 = Vector2.ZERO
## 左クリック中かどうか
var _left_button_pressed: bool = false
## タッチ入力中かどうか（エミュレートされたマウスイベントを無視するため）
var _touch_active: bool = false
## タップダウン時にパスモードを即座に開始したかどうか
var _immediate_path_mode_started: bool = false
## 即座パスモードでドラッグによりパス描画を開始したかどうか
var _immediate_path_drawing_started: bool = false
## パス先端をつかんでパス延長モードを開始する準備ができているか
var _path_endpoint_extension_pending: bool = false
## パス先端延長モードが開始されたかどうか
var _path_endpoint_extension_started: bool = false


func setup(manager: GameManager, pan_controller: CameraPanController) -> void:
	game_manager = manager
	camera_pan_controller = pan_controller


## パス未設定キャラクターかどうかを判定
func _is_character_without_path(character: Node) -> bool:
	if not character:
		return false
	if not game_manager.path_execution_manager:
		return true
	return not game_manager.path_execution_manager.has_pending_path_for_character(character)


## タップダウン時にキャラクターを即座に選択（パスモードはドラッグ時に開始）
## @return: キャラクターが選択された場合true
func _try_start_immediate_path_mode(screen_pos: Vector2) -> bool:
	var clicked = game_manager.raycast_character(screen_pos)
	if not clicked:
		return false
	if PlayerState.is_enemy(clicked):
		return false
	if game_manager.path_service and game_manager.path_service.is_character_following_path(clicked):
		return false

	game_manager.selection_manager.deselect_all()
	game_manager.selection_manager.add_to_selection(clicked)
	# パスモードはドラッグ時に開始（タップのみの場合は既存パスを保持）
	return true


## パス先端をドラッグしてパス延長モードを開始
## @return: パス延長モードが開始された場合true
func _try_start_path_extension_from_endpoint(screen_pos: Vector2) -> bool:
	return game_manager.try_start_path_extension_at_position(screen_pos)


func _unhandled_input(event: InputEvent) -> void:
	if not game_manager:
		return

	# ========================================
	# タッチ中またはピンチ中はマウスイベントを無視
	# （タッチからエミュレートされたマウスイベントを防ぐ）
	# ========================================
	if _touch_active or (camera_pan_controller and camera_pan_controller.is_pinching()):
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			return

	# ========================================
	# タッチ入力の処理
	# ========================================
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_touch_event(event)
		return

	# ========================================
	# Macトラックパッドジェスチャー（ピンチズーム）
	# 微小なジェスチャーは無視（クリック時のノイズ対策）
	# ========================================
	if event is InputEventMagnifyGesture:
		# factor が 1.0 から十分離れている場合のみ処理
		if absf(event.factor - 1.0) > 0.01 and camera_pan_controller:
			camera_pan_controller.handle_magnify_gesture(event.factor)
			get_viewport().set_input_as_handled()
			return
		# 微小な場合は無視して次の処理へ（returnしない）

	# ========================================
	# マウスホイール（カメラズーム）
	# ========================================
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if camera_pan_controller:
				camera_pan_controller.handle_input(event)
			return

	# ========================================
	# パスモード中の処理
	# ========================================
	if game_manager.is_path_mode():
		# 即座パスモードでまだ描画開始していない場合のドラッグ検出
		if event is InputEventMouseMotion and _immediate_path_mode_started and not _immediate_path_drawing_started:
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
				_immediate_path_drawing_started = true
			# PathDrawerにドラッグイベントを伝播させる
			return

		# パス先端延長の待機中にドラッグが開始された場合
		if event is InputEventMouseMotion and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
			# 現在のパスを確定してからパス延長を試みる
			game_manager.confirm_path()
			if _try_start_path_extension_from_endpoint(_left_click_start_pos):
				_path_endpoint_extension_started = true
				_path_endpoint_extension_pending = false
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer.handle_drawing_press(_left_click_start_pos)
				return
			else:
				_path_endpoint_extension_pending = false

		# パス先端延長モードでドラッグ中の場合、PathDrawerにイベントを渡す
		if event is InputEventMouseMotion and _path_endpoint_extension_started:
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer._handle_movement_input(event)
				get_viewport().set_input_as_handled()
			return

		# マウスボタンリリース時：カメラドラッグ状態をクリア
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_left_button_pressed = false
			# パス先端延長中だった場合、PathDrawerに描画終了を通知
			if _path_endpoint_extension_started:
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer._handle_drawing_release()
				# 移動中延長モードの場合は自動確定
				if game_manager.path_service and game_manager.path_service.is_moving_extension_mode():
					game_manager.confirm_path()
			# 即座パスモードのフラグをリセット
			_immediate_path_mode_started = false
			_immediate_path_drawing_started = false
			# パス先端延長フラグもリセット
			_path_endpoint_extension_pending = false
			_path_endpoint_extension_started = false
			if camera_pan_controller:
				if camera_pan_controller.is_dragging():
					camera_pan_controller.end_drag()
				elif camera_pan_controller.is_pending_drag():
					camera_pan_controller.cancel_potential_drag()
			# PathDrawerにも伝播させる
			return
		# マウスクリック時：キャラクタータップ
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_left_button_pressed = true
			_left_click_start_pos = event.position
			var clicked = game_manager.raycast_character(event.position)
			if clicked:
				# 味方キャラクターなら選択（パスモードはドラッグ時に開始）
				if not PlayerState.is_enemy(clicked):
					if not (game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)):
						# 現在のパスを確定してから切り替え
						game_manager.confirm_path()
						game_manager.selection_manager.deselect_all()
						game_manager.selection_manager.add_to_selection(clicked)
						# パスモードはドラッグ時に開始（タップのみの場合は既存パスを保持）
						_immediate_path_mode_started = true
						_immediate_path_drawing_started = false
						get_viewport().set_input_as_handled()
						return
				# それ以外はGameManagerに委譲
			else:
				# キャラクターがクリックされなかった場合、パス先端延長を試みる
				_path_endpoint_extension_pending = true
				_path_endpoint_extension_started = false
				game_manager.handle_click(event.position, MOUSE_BUTTON_LEFT)
				get_viewport().set_input_as_handled()
				return
		# それ以外はPathDrawerに委譲
		return

	# ========================================
	# 左クリック処理（PC向け・非パスモード）
	# 1本指でタップ/パン、2本指でズーム
	# ========================================
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_button_pressed = true
			_left_click_start_pos = event.position

			# キャラクターなら即座にパスモード開始（描画はドラッグ時に開始）
			if _try_start_immediate_path_mode(event.position):
				_immediate_path_mode_started = true
				_immediate_path_drawing_started = false
				get_viewport().set_input_as_handled()
				return

			# パス先端近くをタップした場合、ドラッグ開始待機状態にする
			_path_endpoint_extension_pending = true
			_path_endpoint_extension_started = false
		else:
			_left_button_pressed = false
			# カメラドラッグ中だった場合はタップ処理をスキップ
			if camera_pan_controller and camera_pan_controller.is_dragging():
				camera_pan_controller.end_drag()
				return
			if camera_pan_controller and camera_pan_controller.is_pending_drag():
				camera_pan_controller.cancel_potential_drag()
			# 即座にパスモードを開始した場合はタップ処理をスキップ
			if _immediate_path_mode_started:
				_immediate_path_mode_started = false
				_immediate_path_drawing_started = false
				return
			# パス先端延長モードが開始された場合はタップ処理をスキップ
			if _path_endpoint_extension_started:
				# PathDrawerに描画終了を通知
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer._handle_drawing_release()
				# 移動中延長モードの場合は自動確定
				if game_manager.path_service and game_manager.path_service.is_moving_extension_mode():
					game_manager.confirm_path()
				_path_endpoint_extension_pending = false
				_path_endpoint_extension_started = false
				return
			# パス先端延長の待機中だった場合、先端近くならタップ処理をスキップ
			if _path_endpoint_extension_pending:
				_path_endpoint_extension_pending = false
				if _is_near_path_endpoint(_left_click_start_pos):
					return
			_path_endpoint_extension_started = false
			# タップ判定
			var distance = _left_click_start_pos.distance_to(event.position)
			if distance < 50.0:
				_handle_tap(event.position)
		return

	# 1本指マウスドラッグ処理
	if event is InputEventMouseMotion and _left_button_pressed:
		# 即座パスモードでドラッグが検出された場合、パスモード開始
		if _immediate_path_mode_started and not _immediate_path_drawing_started:
			game_manager.start_move_mode()
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
			_immediate_path_drawing_started = true
			return
		# パス先端延長の待機中にドラッグが開始された場合
		if _path_endpoint_extension_pending and not _path_endpoint_extension_started:
			if _try_start_path_extension_from_endpoint(_left_click_start_pos):
				_path_endpoint_extension_started = true
				_path_endpoint_extension_pending = false
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer.handle_drawing_press(_left_click_start_pos)
				return
			else:
				# パス先端でなければカメラパン候補を開始
				_path_endpoint_extension_pending = false
				if camera_pan_controller:
					camera_pan_controller.start_potential_drag(_left_click_start_pos)
		# パス先端延長モードでドラッグ中の場合、PathDrawerにイベントを渡す
		if _path_endpoint_extension_started:
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer._handle_movement_input(event)
				get_viewport().set_input_as_handled()
			return
		# カメラパン処理
		if camera_pan_controller:
			if camera_pan_controller.is_pending_drag():
				camera_pan_controller.check_and_start_drag(event.position)
			if camera_pan_controller.is_dragging():
				camera_pan_controller.handle_input(event)
				get_viewport().set_input_as_handled()
		return


## ========================================
## タッチ入力処理
## ========================================

func _handle_touch_event(event: InputEvent) -> void:
	if not camera_pan_controller:
		return

	# タッチ開始/終了でフラグを更新
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_active = true
		elif camera_pan_controller.get_touch_count() <= 1:
			# 最後のタッチが離れた時のみフラグをクリア
			_touch_active = false

	var touch_count_before = camera_pan_controller.get_touch_count()
	camera_pan_controller.track_touch(event)

	# 2本指以上：ピンチズーム（パスモード中でも有効）
	if camera_pan_controller.get_touch_count() >= 2 or camera_pan_controller.is_pinching():
		if camera_pan_controller.handle_pinch(event):
			get_viewport().set_input_as_handled()
		return

	# パスモード中の処理
	if game_manager.is_path_mode():
		# 即座パスモードでまだ描画開始していない場合のドラッグ検出
		if event is InputEventScreenDrag and _immediate_path_mode_started and not _immediate_path_drawing_started:
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
				_immediate_path_drawing_started = true
			# PathDrawerにドラッグイベントを伝播させる
			return

		# パス先端延長の待機中にドラッグが開始された場合
		if event is InputEventScreenDrag and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
			# 現在のパスを確定してからパス延長を試みる
			game_manager.confirm_path()
			if _try_start_path_extension_from_endpoint(_left_click_start_pos):
				_path_endpoint_extension_started = true
				_path_endpoint_extension_pending = false
				# パス延長開始時、PathDrawerに描画開始を通知
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer.handle_drawing_press(_left_click_start_pos)
				return
			else:
				_path_endpoint_extension_pending = false

		# パス先端延長モードでドラッグ中の場合、PathDrawerにイベントを渡す
		if event is InputEventScreenDrag and _path_endpoint_extension_started:
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer._handle_movement_input(event)
				get_viewport().set_input_as_handled()
			return

		# タッチ終了時：カメラパン状態をクリア
		if event is InputEventScreenTouch and not event.pressed:
			# パス先端延長中だった場合、PathDrawerに描画終了を通知
			if _path_endpoint_extension_started:
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer._handle_drawing_release()
				# 移動中延長モードの場合は自動確定
				if game_manager.path_service and game_manager.path_service.is_moving_extension_mode():
					game_manager.confirm_path()
			# 即座パスモードのフラグをリセット
			_immediate_path_mode_started = false
			_immediate_path_drawing_started = false
			# パス先端延長フラグもリセット
			_path_endpoint_extension_pending = false
			_path_endpoint_extension_started = false
			if camera_pan_controller.is_touch_panning():
				camera_pan_controller.end_touch_pan()
			elif camera_pan_controller.is_pending_touch_pan():
				camera_pan_controller.cancel_potential_touch_pan()
			# PathDrawerにも伝播させる
			return
		# タッチ開始時：キャラクタータップ
		if event is InputEventScreenTouch and event.pressed:
			_left_click_start_pos = event.position
			var clicked = game_manager.raycast_character(event.position)
			if clicked:
				# 味方キャラクターなら選択（パスモードはドラッグ時に開始）
				if not PlayerState.is_enemy(clicked):
					if not (game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)):
						# 現在のパスを確定してから切り替え
						game_manager.confirm_path()
						game_manager.selection_manager.deselect_all()
						game_manager.selection_manager.add_to_selection(clicked)
						# パスモードはドラッグ時に開始（タップのみの場合は既存パスを保持）
						_immediate_path_mode_started = true
						_immediate_path_drawing_started = false
						get_viewport().set_input_as_handled()
						return
				# それ以外はGameManagerに委譲
				game_manager.handle_click(event.position, MOUSE_BUTTON_LEFT)
				get_viewport().set_input_as_handled()
				return
			else:
				# キャラクターがクリックされなかった場合、パス先端延長を試みる
				_path_endpoint_extension_pending = true
				_path_endpoint_extension_started = false
		# それ以外はPathDrawerに委譲
		return

	# 1本指タッチ（非パスモード）- タップとパン、2本指でズーム
	var is_one_finger = camera_pan_controller.get_touch_count() == 1
	var is_one_finger_release = event is InputEventScreenTouch and not event.pressed and touch_count_before == 1

	if not (is_one_finger or is_one_finger_release):
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			# タッチ開始：タップ候補として記録
			_left_click_start_pos = event.position

			# パス未設定キャラクターなら即座にパスモード開始（描画はドラッグ時に開始）
			if _try_start_immediate_path_mode(event.position):
				_immediate_path_mode_started = true
				_immediate_path_drawing_started = false
				get_viewport().set_input_as_handled()
				return

			# パス先端近くをタップした場合、ドラッグ開始待機状態にする
			_path_endpoint_extension_pending = true
			_path_endpoint_extension_started = false
		else:
			# カメラパン中だった場合はタップ処理をスキップ
			if camera_pan_controller.is_touch_panning():
				camera_pan_controller.end_touch_pan()
				get_viewport().set_input_as_handled()
				return
			if camera_pan_controller.is_pending_touch_pan():
				camera_pan_controller.cancel_potential_touch_pan()
			# 即座にパスモードを開始した場合はタップ処理をスキップ
			# （パスモードに入った状態で、その後のドラッグでパスを描ける）
			if _immediate_path_mode_started:
				_immediate_path_mode_started = false
				_immediate_path_drawing_started = false
				get_viewport().set_input_as_handled()
				return
			# パス先端延長モードが開始された場合はタップ処理をスキップ
			if _path_endpoint_extension_started:
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer._handle_drawing_release()
				# 移動中延長モードの場合は自動確定
				if game_manager.path_service and game_manager.path_service.is_moving_extension_mode():
					game_manager.confirm_path()
				_path_endpoint_extension_pending = false
				_path_endpoint_extension_started = false
				get_viewport().set_input_as_handled()
				return
			# パス先端延長の待機中だった場合、先端近くならタップ処理をスキップ
			if _path_endpoint_extension_pending:
				_path_endpoint_extension_pending = false
				if _is_near_path_endpoint(_left_click_start_pos):
					get_viewport().set_input_as_handled()
					return
			_path_endpoint_extension_started = false
			# タッチ終了：タップ判定
			var distance = _left_click_start_pos.distance_to(event.position)
			if distance < 20.0:
				_handle_tap(event.position)
			get_viewport().set_input_as_handled()
		return

	# 1本指ドラッグ処理
	if event is InputEventScreenDrag:
		# 即座パスモードでドラッグが検出された場合、パスモード開始
		if _immediate_path_mode_started and not _immediate_path_drawing_started:
			game_manager.start_move_mode()
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
			_immediate_path_drawing_started = true
			return
		# パス先端延長の待機中にドラッグが開始された場合
		if _path_endpoint_extension_pending and not _path_endpoint_extension_started:
			if _try_start_path_extension_from_endpoint(_left_click_start_pos):
				_path_endpoint_extension_started = true
				_path_endpoint_extension_pending = false
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer.handle_drawing_press(_left_click_start_pos)
				return
			else:
				# パス先端でなければカメラパン候補を開始
				_path_endpoint_extension_pending = false
				camera_pan_controller.start_potential_touch_pan(_left_click_start_pos)
		# パス先端延長モードでドラッグ中の場合、PathDrawerにイベントを渡す
		if _path_endpoint_extension_started:
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer._handle_movement_input(event)
				get_viewport().set_input_as_handled()
			return
		# カメラパン処理
		if camera_pan_controller.is_pending_touch_pan():
			camera_pan_controller.check_and_start_touch_pan(event.position)
		if camera_pan_controller.is_touch_panning():
			camera_pan_controller.update_touch_pan(event.position)
		get_viewport().set_input_as_handled()


## ========================================
## マウス入力処理（非パスモード）
## ========================================

func _handle_mouse_click(event: InputEventMouseButton) -> void:
	if event.pressed:
		_left_button_pressed = true
		_left_click_start_pos = event.position

		# カメラドラッグ候補開始
		if camera_pan_controller:
			camera_pan_controller.start_potential_drag(event.position)
	else:
		_left_button_pressed = false

		if camera_pan_controller and camera_pan_controller.is_dragging():
			camera_pan_controller.end_drag()
		elif camera_pan_controller and camera_pan_controller.is_pending_drag():
			camera_pan_controller.cancel_potential_drag()
			_handle_tap(event.position)


func _handle_mouse_drag(event: InputEventMouseMotion) -> void:
	if camera_pan_controller and camera_pan_controller.is_dragging():
		camera_pan_controller.handle_input(event)
		get_viewport().set_input_as_handled()
		return

	if camera_pan_controller and camera_pan_controller.is_pending_drag():
		if camera_pan_controller.check_and_start_drag(event.position):
			get_viewport().set_input_as_handled()


## ========================================
## タップ/クリック処理（GameManagerに委譲）
## ========================================

func _handle_tap(pos: Vector2) -> void:
	game_manager.handle_click(pos, MOUSE_BUTTON_LEFT)


## ========================================
## ユーティリティ
## ========================================

func _get_path_drawer() -> PathDrawer:
	return game_manager.path_drawer as PathDrawer


## パス先端が近くにあるかチェック
func _is_near_path_endpoint(screen_pos: Vector2) -> bool:
	if not game_manager or not game_manager.path_execution_manager or not game_manager.camera:
		return false

	# 地面位置を取得
	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return false

	var ground_pos: Vector3 = intersect as Vector3
	var result := game_manager.path_execution_manager.find_path_endpoint_at_position(ground_pos, 0.5)
	return not result.is_empty()
