class_name PathInputHandler
extends RefCounted
## パス入力処理ハンドラ
##
## 責務:
## - パスモード中の入力処理
## - 回転モード
## - Visionポイント配置（確認済みパス、移動中パス）
## - パス先端延長
## - 長押し検出


#region 依存関係

var game_manager: GameManager = null
var camera_handler: CameraInputHandler = null

#endregion


#region UI要素

## 長押しプログレスリング
var _progress_ring: LongPressProgressRing = null

#endregion


#region 共有入力状態（InputControllerと共有）

## 左クリック中かどうか（InputControllerから参照される）
var left_button_pressed: bool = false
## 左クリック押下時のスクリーン座標（InputControllerから参照される）
var left_click_start_pos: Vector2 = Vector2.ZERO

#endregion


#region 入力状態

## タップダウン時にパスモードを即座に開始したかどうか
var _immediate_path_mode_started: bool = false
## 即座パスモードでドラッグによりパス描画を開始したかどうか
var _immediate_path_drawing_started: bool = false
## パス先端をつかんでパス延長モードを開始する準備ができているか
var _path_endpoint_extension_pending: bool = false
## パス先端延長モードが開始されたかどうか
var _path_endpoint_extension_started: bool = false
## 実行中だったキャラクター（新しいパス確定後に自動実行するため）
var _auto_execute_character: Node = null

#endregion


#region 長押し回転モード

var _long_press_timer: float = 0.0
var _long_press_threshold: float = 1.0  ## 長押し判定の閾値（秒）
var _is_rotation_mode: bool = false  ## 回転モード中かどうか
var _rotation_target_character: Node = null  ## 回転対象のキャラクター
var _rotation_center_screen_pos: Vector2 = Vector2.ZERO  ## 回転中心のスクリーン座標
var _min_drag_distance: float = 15.0  ## ドラッグ判定の最小距離（ピクセル）

#endregion


#region 確認済みパス上長押し（Visionポイント配置用）

var _confirmed_path_longpress_pending: bool = false
var _confirmed_path_longpress_timer: float = 0.0
var _confirmed_path_longpress_threshold: float = 0.5
var _confirmed_path_longpress_screen_pos: Vector2 = Vector2.ZERO
var _confirmed_path_longpress_ground_pos: Vector3 = Vector3.ZERO
var _confirmed_path_longpress_is_touch: bool = false
var _confirmed_path_tap_path_data: Dictionary = {}

#endregion


#region 移動中パス上長押し（Visionポイント配置用）

var _moving_path_longpress_pending: bool = false
var _moving_path_longpress_timer: float = 0.0
var _moving_path_longpress_threshold: float = 0.5
var _moving_path_longpress_screen_pos: Vector2 = Vector2.ZERO
var _moving_path_longpress_data: Dictionary = {}
var _moving_path_vision_drawing: bool = false
var _moving_path_tap_path_data: Dictionary = {}

#endregion


#region パスモード終了フラグ

var _path_mode_ended_frame: int = -1

#endregion


#region ダブルタップ検出

var _last_path_tap_time: int = 0
var _last_path_tap_path_data: Dictionary = {}
const DOUBLE_TAP_THRESHOLD_MS: int = 300

#endregion


#region コンテキストメニュー遅延表示

var _context_menu_timer: SceneTreeTimer = null
var _pending_context_menu_screen_pos: Vector2 = Vector2.ZERO
var _pending_context_menu_path_data: Dictionary = {}

#endregion


#region 初期化

func setup(manager: GameManager, cam_handler: CameraInputHandler) -> void:
	game_manager = manager
	camera_handler = cam_handler
	_setup_progress_ring()
	_connect_path_mode_signals()


## 長押しプログレスリングを初期化
func _setup_progress_ring() -> void:
	if not game_manager:
		return
	var ui_layer = game_manager.get_ui_layer()
	if not ui_layer:
		return
	_progress_ring = LongPressProgressRing.create(ui_layer, 50.0)
	_progress_ring.ring_width = 6.0
	_progress_ring.ring_color = Color(1.0, 1.0, 1.0, 0.9)
	_progress_ring.background_color = Color(0.3, 0.3, 0.3, 0.5)

	# パス先端ドラッグシグナルを接続
	var path_drawer = _get_path_drawer()
	if path_drawer:
		if not path_drawer.endpoint_drag_detected.is_connected(_on_endpoint_drag_detected):
			path_drawer.endpoint_drag_detected.connect(_on_endpoint_drag_detected)


## パスモード終了シグナルを接続
func _connect_path_mode_signals() -> void:
	if not game_manager:
		return
	var path_mode_controller = game_manager.get_path_mode_controller()
	if path_mode_controller:
		if not path_mode_controller.mode_ended.is_connected(_on_path_mode_ended):
			path_mode_controller.mode_ended.connect(_on_path_mode_ended)
		if not path_mode_controller.mode_cancelled.is_connected(_on_path_mode_ended):
			path_mode_controller.mode_cancelled.connect(_on_path_mode_ended)

#endregion


#region タイマー更新（毎フレーム処理）

func update_timers(delta: float) -> void:
	# 長押し検出（キャラクター回転用）
	if left_button_pressed and not _is_rotation_mode and not _immediate_path_drawing_started:
		if _rotation_target_character and is_instance_valid(_rotation_target_character):
			_long_press_timer += delta
			_update_progress_ring(left_click_start_pos, _long_press_timer, _long_press_threshold)
			if _long_press_timer >= _long_press_threshold:
				_hide_progress_ring()
				_start_rotation_mode()

	# 確認済みパス上長押し検出
	if _confirmed_path_longpress_pending:
		_confirmed_path_longpress_timer += delta
		_update_progress_ring(_confirmed_path_longpress_screen_pos, _confirmed_path_longpress_timer, _confirmed_path_longpress_threshold)
		if _confirmed_path_longpress_timer >= _confirmed_path_longpress_threshold:
			_hide_progress_ring()
			_start_vision_mode_on_confirmed_path()

	# 移動中パス上長押し検出
	if _moving_path_longpress_pending:
		_moving_path_longpress_timer += delta
		_update_progress_ring(_moving_path_longpress_screen_pos, _moving_path_longpress_timer, _moving_path_longpress_threshold)
		if _moving_path_longpress_timer >= _moving_path_longpress_threshold:
			_hide_progress_ring()
			_start_vision_mode_on_moving_path()

#endregion


#region マウス入力処理（パスモード）

## パスモード中のマウス入力処理
func handle_mouse_event_path_mode(event: InputEvent, viewport: Viewport) -> bool:
	# 回転モード中のドラッグ処理
	if event is InputEventMouseMotion and _is_rotation_mode:
		_process_rotation_drag(event.position)
		viewport.set_input_as_handled()
		return true

	# 即座パスモードでまだ描画開始していない場合のドラッグ検出
	if event is InputEventMouseMotion and _immediate_path_mode_started and not _immediate_path_drawing_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer.handle_drawing_press(left_click_start_pos)
			_immediate_path_drawing_started = true
		return true

	# パス先端延長の待機中にドラッグが開始された場合
	if event is InputEventMouseMotion and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
		if Debug.enabled: print("[PointDebug] path_mode: starting path extension from pending (mouse motion)")
		game_manager.confirm_path()
		if _try_start_path_continuation_from_endpoint(left_click_start_pos):
			_path_endpoint_extension_started = true
			_path_endpoint_extension_pending = false
			if Debug.enabled: print("[PointDebug] path_mode: ext_started=true (from mouse motion)")
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(left_click_start_pos)
			return true
		else:
			_path_endpoint_extension_pending = false

	# パス先端延長モードでドラッグ中
	if event is InputEventMouseMotion and _path_endpoint_extension_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer._handle_movement_input(event)
			viewport.set_input_as_handled()
		return true

	# マウスボタンリリース
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		handle_path_mode_mouse_release(event.position, viewport)
		return true

	# マウスボタンプレス
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		handle_path_mode_mouse_press(event.position, viewport)
		return true

	return false


## パスモード中のマウスリリース処理
func handle_path_mode_mouse_release(position: Vector2, viewport: Viewport) -> void:
	if Debug.enabled: print("[PointDebug] path_mode mouse release: is_path_mode=%s, ext_started=%s, ext_pending=%s, longpress_pending=%s" % [
		str(game_manager.is_path_mode()), str(_path_endpoint_extension_started), str(_path_endpoint_extension_pending), str(_confirmed_path_longpress_pending)
	])
	left_button_pressed = false

	if _is_rotation_mode:
		_end_rotation_mode()
		viewport.set_input_as_handled()
		return

	# 確認済みパス長押し待機中だった場合（タップ判定 → ダブルタップ検出）
	if _confirmed_path_longpress_pending:
		_handle_path_tap_for_confirmed_path()
		_reset_confirmed_path_longpress()
		return

	# 移動中パス長押し待機中だった場合（タップ判定 → ダブルタップ検出）
	if _moving_path_longpress_pending:
		_handle_path_tap_for_moving_path()
		_reset_moving_path_longpress()
		return

	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()

	# パス先端継続中だった場合
	if _path_endpoint_extension_started:
		if Debug.enabled: print("[PointDebug] path_mode mouse release: confirming path (ext_started=true)")
		var drawer = _get_path_drawer()
		if drawer:
			drawer._handle_drawing_release()
		game_manager.confirm_path()
	# 実行中キャラクターに新しいパスを描いた場合
	elif _immediate_path_drawing_started and _auto_execute_character:
		if Debug.enabled: print("[PointDebug] path_mode mouse release: auto-confirming path for executing character")
		var drawer = _get_path_drawer()
		if drawer:
			drawer._handle_drawing_release()
		game_manager.confirm_path()

	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	_path_endpoint_extension_pending = false
	_path_endpoint_extension_started = false

	var path_drawer = _get_path_drawer()
	if path_drawer:
		if path_drawer.is_point_mode():
			path_drawer.handle_point_release(position)
		else:
			path_drawer.handle_movement_release(position)

	if camera_handler:
		if camera_handler.is_dragging():
			camera_handler.end_drag()
		elif camera_handler.is_pending_drag():
			camera_handler.cancel_drag()


## パスモード中のマウスプレス処理
func handle_path_mode_mouse_press(position: Vector2, viewport: Viewport) -> void:
	left_button_pressed = true
	left_click_start_pos = position
	_long_press_timer = 0.0

	var clicked = game_manager.raycast_character(position)
	if Debug.enabled: print("[PointDebug] path_mode click: clicked=%s" % (clicked.name if clicked else "null"))

	if clicked:
		var is_enemy = PlayerState.is_enemy(clicked)
		var _gc := clicked as GameCharacter
		var is_dead = _gc and not _gc.is_alive
		var is_following = game_manager.is_character_following_path(clicked)
		if Debug.enabled: print("[PointDebug] path_mode click: is_enemy=%s, is_dead=%s, is_following=%s" % [is_enemy, is_dead, is_following])

		if not is_enemy and not is_dead:
			if is_following:
				game_manager.cancel_path_following(clicked, true)
				_auto_execute_character = clicked

			_rotation_target_character = clicked
			if Debug.enabled: print("[PointDebug] path_mode click: confirming current path and selecting %s" % clicked.name)
			game_manager.confirm_path()
			if Debug.enabled: print("[PointDebug] path_mode click: after confirm, is_path_mode=%s" % game_manager.is_path_mode())
			game_manager.selection_manager.deselect_all()
			game_manager.selection_manager.add_to_selection(clicked)
			_immediate_path_mode_started = true
			_immediate_path_drawing_started = false
			if Debug.enabled: print("[PointDebug] path_mode click: set _immediate_path_mode_started=true for %s" % clicked.name)
			viewport.set_input_as_handled()
			return
	else:
		var pd = _get_path_drawer()
		var drawing_started = false
		if pd:
			drawing_started = pd.handle_movement_press(position)

		if drawing_started:
			_path_endpoint_extension_pending = false
		else:
			if _try_start_confirmed_path_longpress(position, false):  # マウス入力
				_path_endpoint_extension_pending = false
			else:
				_path_endpoint_extension_pending = true
				_path_endpoint_extension_started = false
				game_manager.handle_click(position, MOUSE_BUTTON_LEFT)
		viewport.set_input_as_handled()

#endregion


#region タッチ入力処理（パスモード）

## パスモード中のタッチ入力処理
func handle_touch_event_path_mode(event: InputEvent, viewport: Viewport) -> bool:
	var path_drawer = _get_path_drawer()

	# ポイントモード中
	if path_drawer and path_drawer.is_point_mode():
		if path_drawer.handle_point_touch_input(event):
			viewport.set_input_as_handled()
			return true

	# 回転モード中のドラッグ処理
	if event is InputEventScreenDrag and _is_rotation_mode:
		_process_rotation_drag(event.position)
		viewport.set_input_as_handled()
		return true

	# 即座パスモードでまだ描画開始していない場合
	if event is InputEventScreenDrag and _immediate_path_mode_started and not _immediate_path_drawing_started:
		if path_drawer:
			path_drawer.handle_drawing_press(left_click_start_pos)
			_immediate_path_drawing_started = true
		return true

	# パス先端延長の待機中にドラッグが開始された場合
	if event is InputEventScreenDrag and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
		if Debug.enabled: print("[PointDebug] path_mode: starting path extension from pending (touch drag)")
		game_manager.confirm_path()
		if _try_start_path_continuation_from_endpoint(left_click_start_pos):
			_path_endpoint_extension_started = true
			_path_endpoint_extension_pending = false
			if Debug.enabled: print("[PointDebug] path_mode: ext_started=true (from touch drag)")
			if path_drawer:
				path_drawer.handle_drawing_press(left_click_start_pos)
			return true
		else:
			_path_endpoint_extension_pending = false

	# パス先端延長モードでドラッグ中
	if event is InputEventScreenDrag and _path_endpoint_extension_started:
		if path_drawer:
			path_drawer._handle_movement_input(event)
			viewport.set_input_as_handled()
		return true

	# タッチ終了
	if event is InputEventScreenTouch and not event.pressed:
		handle_path_mode_touch_release(event.position, path_drawer, viewport)
		return true

	# タッチ開始
	if event is InputEventScreenTouch and event.pressed:
		handle_path_mode_touch_press(event.position, path_drawer, viewport)
		return true

	return false


## パスモード中のタッチリリース処理
func handle_path_mode_touch_release(position: Vector2, path_drawer: PathDrawer, viewport: Viewport) -> void:
	left_button_pressed = false

	if _is_rotation_mode:
		_end_rotation_mode()
		viewport.set_input_as_handled()
		return

	# 確認済みパス長押し待機中だった場合（タップ判定 → ダブルタップ検出）
	if _confirmed_path_longpress_pending:
		_handle_path_tap_for_confirmed_path()
		_reset_confirmed_path_longpress()
		viewport.set_input_as_handled()
		return

	# 移動中パス長押し待機中だった場合（タップ判定 → ダブルタップ検出）
	if _moving_path_longpress_pending:
		_handle_path_tap_for_moving_path()
		_reset_moving_path_longpress()
		viewport.set_input_as_handled()
		return

	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()

	if _path_endpoint_extension_started:
		if path_drawer:
			path_drawer._handle_drawing_release()
		game_manager.confirm_path()
	elif _immediate_path_drawing_started and _auto_execute_character:
		if Debug.enabled: print("[PointDebug] touch path_mode release: auto-confirming path for executing character")
		if path_drawer:
			path_drawer._handle_drawing_release()
		game_manager.confirm_path()

	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	_path_endpoint_extension_pending = false
	_path_endpoint_extension_started = false

	if path_drawer and path_drawer.is_point_mode():
		path_drawer.handle_point_release(position)

	if camera_handler.is_touch_panning():
		camera_handler.end_touch_pan()
	elif camera_handler.is_pending_touch_pan():
		camera_handler.cancel_touch_pan()


## パスモード中のタッチプレス処理
func handle_path_mode_touch_press(position: Vector2, path_drawer: PathDrawer, viewport: Viewport) -> void:
	left_button_pressed = true
	left_click_start_pos = position
	_long_press_timer = 0.0

	var clicked = game_manager.raycast_character(position)
	if Debug.enabled: print("[PointDebug] touch path_mode click: clicked=%s" % (clicked.name if clicked else "null"))

	if clicked:
		var is_enemy = PlayerState.is_enemy(clicked)
		var _gc := clicked as GameCharacter
		var is_dead = _gc and not _gc.is_alive
		var is_following = game_manager.is_character_following_path(clicked)
		if Debug.enabled: print("[PointDebug] touch path_mode click: is_enemy=%s, is_dead=%s, is_following=%s" % [is_enemy, is_dead, is_following])

		if not is_enemy and not is_dead:
			if is_following:
				game_manager.cancel_path_following(clicked, true)
				_auto_execute_character = clicked

			_rotation_target_character = clicked
			if Debug.enabled: print("[PointDebug] touch path_mode click: confirming current path and selecting %s" % clicked.name)
			game_manager.confirm_path()
			if Debug.enabled: print("[PointDebug] touch path_mode click: after confirm, is_path_mode=%s" % game_manager.is_path_mode())
			game_manager.selection_manager.deselect_all()
			game_manager.selection_manager.add_to_selection(clicked)
			_immediate_path_mode_started = true
			_immediate_path_drawing_started = false
			if Debug.enabled: print("[PointDebug] touch path_mode click: set _immediate_path_mode_started=true for %s" % clicked.name)
			viewport.set_input_as_handled()
			return

		game_manager.handle_click(position, MOUSE_BUTTON_LEFT)
		viewport.set_input_as_handled()
		return
	else:
		var drawing_started = false
		if path_drawer:
			drawing_started = path_drawer.handle_movement_press(position)

		if drawing_started:
			_path_endpoint_extension_pending = false
		else:
			if _try_start_confirmed_path_longpress(position, true):  # タッチ入力
				_path_endpoint_extension_pending = false
			else:
				_path_endpoint_extension_pending = true
				_path_endpoint_extension_started = false
				game_manager.handle_click(position, MOUSE_BUTTON_LEFT)
		viewport.set_input_as_handled()

#endregion


#region 非パスモード入力処理

## 非パスモードのプレス処理
func handle_normal_mode_press(position: Vector2, is_touch: bool, viewport: Viewport) -> void:
	if Debug.enabled: print("[PointDebug] non-path_mode press: is_path_mode=%s, is_touch=%s" % [str(game_manager.is_path_mode()), str(is_touch)])
	left_button_pressed = true
	left_click_start_pos = position
	_long_press_timer = 0.0

	# グレネードターゲット選択モード中はパス操作をバイパス
	if game_manager.is_grenade_target_mode():
		return

	# キャラクターがクリックされたか確認
	var clicked = game_manager.raycast_character(position)
	if clicked and not PlayerState.is_enemy(clicked):
		_rotation_target_character = clicked
	else:
		_rotation_target_character = null

	# キャラクターなら即座にパスモード開始
	if _try_start_immediate_path_mode(position):
		_immediate_path_mode_started = true
		_immediate_path_drawing_started = false
		viewport.set_input_as_handled()
		return

	# 確認済みパス上の長押しを検出
	if _try_start_confirmed_path_longpress(position, is_touch):
		viewport.set_input_as_handled()
		return

	# パス先端近くをタップした場合
	_path_endpoint_extension_pending = true
	_path_endpoint_extension_started = false


## 非パスモードのリリース処理
## @return: タップを処理すべきかどうか
func handle_normal_mode_release(position: Vector2, is_touch: bool) -> bool:
	if Debug.enabled: print("[PointDebug] _handle_normal_mode_release: is_touch=%s, _confirmed_path_longpress_pending=%s" % [str(is_touch), str(_confirmed_path_longpress_pending)])
	left_button_pressed = false

	if _is_rotation_mode:
		_end_rotation_mode()
		return false

	if _moving_path_vision_drawing:
		_finish_moving_path_vision_point(position)
		return false

	if _confirmed_path_longpress_pending:
		if Debug.enabled: print("[PointDebug] _handle_normal_mode_release: calling _handle_path_tap_for_confirmed_path")
		_handle_path_tap_for_confirmed_path()
		_reset_confirmed_path_longpress()
		return false

	if _moving_path_longpress_pending:
		if Debug.enabled: print("[PointDebug] _handle_normal_mode_release: calling _handle_path_tap_for_moving_path")
		_handle_path_tap_for_moving_path()
		_reset_moving_path_longpress()
		return false

	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()

	# カメラドラッグ中だった場合
	if is_touch:
		if camera_handler.is_touch_panning():
			camera_handler.end_touch_pan()
			return false
		if camera_handler.is_pending_touch_pan():
			camera_handler.cancel_touch_pan()
	else:
		if camera_handler and camera_handler.is_dragging():
			camera_handler.end_drag()
			return false
		if camera_handler and camera_handler.is_pending_drag():
			camera_handler.cancel_drag()

	if _immediate_path_mode_started:
		_immediate_path_mode_started = false
		_immediate_path_drawing_started = false
		return false

	if _path_endpoint_extension_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer._handle_drawing_release()
		game_manager.confirm_path()
		_path_endpoint_extension_pending = false
		_path_endpoint_extension_started = false
		return false

	if _path_endpoint_extension_pending:
		_path_endpoint_extension_pending = false
		if _is_near_path_endpoint(left_click_start_pos):
			return false

	_path_endpoint_extension_started = false

	# タップ判定
	var tap_threshold = 20.0 if is_touch else 50.0
	var distance = left_click_start_pos.distance_to(position)
	return distance < tap_threshold


## 非パスモードのドラッグ処理
## @return: カメラパン処理を実行すべきかどうか
func handle_normal_mode_drag(position: Vector2, is_touch: bool, viewport: Viewport) -> bool:
	# グレネードターゲットモード中はカメラパン/パス操作をバイパス
	if game_manager.is_grenade_target_mode():
		return false

	var current_frame = Engine.get_process_frames()
	var just_ended = (current_frame == _path_mode_ended_frame)
	if Debug.enabled: print("[PointDebug] non-path_mode drag: frame=%d, ended_frame=%d, just_ended=%s, ext_pending=%s" % [
		current_frame, _path_mode_ended_frame, str(just_ended), str(_path_endpoint_extension_pending)
	])

	# 回転モード中
	if _is_rotation_mode:
		_process_rotation_drag(position)
		viewport.set_input_as_handled()
		return false

	# 移動中パスVision描画中
	if _moving_path_vision_drawing:
		_update_moving_path_vision_preview(position)
		viewport.set_input_as_handled()
		return false

	# 確認済みパス長押し待機中にドラッグが検出された場合
	if _confirmed_path_longpress_pending:
		var move_dist = position.distance_to(_confirmed_path_longpress_screen_pos)
		if move_dist > 20.0:
			_reset_confirmed_path_longpress()
			if is_touch:
				camera_handler.start_touch_pan(left_click_start_pos)
			elif camera_handler:
				camera_handler.start_drag(left_click_start_pos)

	# 移動中パス長押し待機中にドラッグが検出された場合
	if _moving_path_longpress_pending:
		var move_dist = position.distance_to(_moving_path_longpress_screen_pos)
		if move_dist > 20.0:
			var path_ratio: float = _moving_path_longpress_data.get("path_ratio", 0.0)
			if path_ratio >= 0.99:
				if Debug.enabled: print("[PointDebug] non-path_mode: longpress cancelled, trying path extension")
				_reset_moving_path_longpress()
				if _try_start_path_continuation_from_endpoint(left_click_start_pos):
					_path_endpoint_extension_started = true
					if Debug.enabled: print("[PointDebug] non-path_mode: ext_started=true (from longpress cancel)")
					var path_drawer = _get_path_drawer()
					if path_drawer:
						path_drawer.handle_drawing_press(left_click_start_pos)
					return false

			_reset_moving_path_longpress()
			if is_touch:
				camera_handler.start_touch_pan(left_click_start_pos)
			elif camera_handler:
				camera_handler.start_drag(left_click_start_pos)

	# 即座パスモードでドラッグが検出された場合
	var drag_distance = position.distance_to(left_click_start_pos)
	if Debug.enabled: print("[PointDebug] non-path_mode drag: _immediate_path_mode_started=%s, _immediate_path_drawing_started=%s, drag_distance=%.1f" % [_immediate_path_mode_started, _immediate_path_drawing_started, drag_distance])
	if _immediate_path_mode_started and not _immediate_path_drawing_started and drag_distance > _min_drag_distance:
		if Debug.enabled: print("[PointDebug] non-path_mode drag: starting path mode for character (drag_distance=%.1f > %.1f)" % [drag_distance, _min_drag_distance])
		_rotation_target_character = null
		_long_press_timer = 0.0
		_hide_progress_ring()
		var res = game_manager.start_move_mode()
		if Debug.enabled: print("[PointDebug] non-path_mode drag: start_move_mode result=%s" % res)
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer.handle_drawing_press(left_click_start_pos)
		_immediate_path_drawing_started = true
		return false

	# パス先端延長の待機中にドラッグが開始された場合
	if _path_endpoint_extension_pending and not _path_endpoint_extension_started and not just_ended:
		if Debug.enabled: print("[PointDebug] non-path_mode: trying path extension from pending (drag)")
		if _try_start_path_continuation_from_endpoint(left_click_start_pos):
			_path_endpoint_extension_started = true
			_path_endpoint_extension_pending = false
			if Debug.enabled: print("[PointDebug] non-path_mode: ext_started=true (drag)")
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(left_click_start_pos)
			return false
		else:
			_path_endpoint_extension_pending = false
			if is_touch:
				camera_handler.start_touch_pan(left_click_start_pos)
			elif camera_handler:
				camera_handler.start_drag(left_click_start_pos)

	# パス先端延長モードでドラッグ中
	if _path_endpoint_extension_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer._handle_movement_input_with_position(position)
			viewport.set_input_as_handled()
		return false

	# カメラパン処理が必要
	return true

#endregion


#region キャラクター・パス操作

## タップダウン時にキャラクターを即座に選択
func _try_start_immediate_path_mode(screen_pos: Vector2) -> bool:
	var clicked = game_manager.raycast_character(screen_pos)
	if not clicked:
		return false
	if PlayerState.is_enemy(clicked):
		return false
	# 死亡キャラクターはスキップ
	var game_char := clicked as GameCharacter
	if game_char and not game_char.is_alive:
		return false

	if game_manager.is_character_following_path(clicked):
		game_manager.cancel_path_following(clicked, true)
		_auto_execute_character = clicked

	game_manager.selection_manager.deselect_all()
	game_manager.selection_manager.add_to_selection(clicked)
	return true


## パス先端からパス継続モードを開始
func _try_start_path_continuation_from_endpoint(screen_pos: Vector2) -> bool:
	return game_manager.try_start_path_continuation_at_position(screen_pos)

#endregion


#region 回転モード

func _start_rotation_mode() -> void:
	if not _rotation_target_character or not is_instance_valid(_rotation_target_character):
		return
	_is_rotation_mode = true
	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	var char_pos = _rotation_target_character.global_position
	_rotation_center_screen_pos = game_manager.camera.unproject_position(char_pos)

	# 手動回転フラグを設定し、現在の敵ターゲットを無視
	if _rotation_target_character.has_method("set_manual_rotating"):
		_rotation_target_character.set_manual_rotating(true)
	if _rotation_target_character.has_method("get_combat_awareness"):
		var combat = _rotation_target_character.get_combat_awareness()
		if combat and combat.has_method("dismiss_current_target"):
			combat.dismiss_current_target()


func _end_rotation_mode() -> void:
	# 手動回転フラグを解除（nullにする前に）
	if _rotation_target_character and is_instance_valid(_rotation_target_character):
		if _rotation_target_character.has_method("set_manual_rotating"):
			_rotation_target_character.set_manual_rotating(false)

	_is_rotation_mode = false
	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()


func _process_rotation_drag(screen_pos: Vector2) -> void:
	if not _rotation_target_character or not is_instance_valid(_rotation_target_character):
		_end_rotation_mode()
		return

	var dir_from_center = screen_pos - _rotation_center_screen_pos
	if dir_from_center.length() < 10.0:
		return

	var angle = atan2(dir_from_center.x, dir_from_center.y)
	var direction = Vector3(sin(angle), 0, cos(angle))
	_rotation_target_character.set_facing_direction_vec(direction)

#endregion


#region プログレスリング

## タップ時にリングが一瞬表示されるのを防ぐための遅延
const PROGRESS_RING_DISPLAY_DELAY: float = 0.2

func _update_progress_ring(screen_pos: Vector2, elapsed: float, threshold: float) -> void:
	if not _progress_ring:
		return
	# 遅延未満はリングを表示しない（タップのチラつき防止）
	if elapsed < PROGRESS_RING_DISPLAY_DELAY:
		return
	if not _progress_ring.is_active():
		_progress_ring.start_manual(screen_pos)
	_progress_ring.update_progress(elapsed, threshold)


func _hide_progress_ring() -> void:
	if _progress_ring:
		_progress_ring.cancel()

#endregion


#region ユーティリティ

func _get_path_drawer() -> PathDrawer:
	return game_manager.path_drawer as PathDrawer


func _is_near_path_endpoint(screen_pos: Vector2) -> bool:
	if not game_manager or not game_manager.camera:
		return false

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return false

	var ground_pos: Vector3 = intersect as Vector3
	var result := game_manager.find_path_endpoint_at_position(ground_pos, GameConstants.PATH_CLICK_THRESHOLD)
	return not result.is_empty()

#endregion


#region 確認済みパス上長押し処理

func _try_start_confirmed_path_longpress(screen_pos: Vector2, is_touch: bool = false) -> bool:
	if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: called, is_touch=%s" % str(is_touch))
	if not game_manager or not game_manager.camera:
		if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: no manager")
		return false

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return false

	var ground_pos: Vector3 = intersect as Vector3
	if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: ground_pos=%s" % [ground_pos])

	# モバイルではタッチ精度が低いため、より大きな閾値を使用
	var threshold := GameConstants.PATH_CLICK_THRESHOLD_MOBILE if is_touch else GameConstants.PATH_CLICK_THRESHOLD

	var result := game_manager.find_path_point_at_position(ground_pos, threshold)
	if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: find_path_point result=%s, threshold=%.2f" % [result, threshold])
	if not result.is_empty():
		if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: starting longpress for confirmed path")
		_confirmed_path_longpress_pending = true
		_confirmed_path_longpress_timer = 0.0
		_confirmed_path_longpress_screen_pos = screen_pos
		_confirmed_path_longpress_ground_pos = ground_pos
		_confirmed_path_longpress_is_touch = is_touch
		_confirmed_path_tap_path_data = result
		return true

	var moving_result := game_manager.try_start_vision_point_on_moving_path(screen_pos, ground_pos, threshold)
	if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: moving_result=%s" % [moving_result])
	if not moving_result.is_empty():
		if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: starting longpress for moving path")
		_moving_path_longpress_pending = true
		_moving_path_longpress_timer = 0.0
		_moving_path_longpress_screen_pos = screen_pos
		_moving_path_longpress_data = moving_result
		_moving_path_tap_path_data = moving_result
		return true

	if Debug.enabled: print("[PointDebug] _try_start_confirmed_path_longpress: no path found, returning false")
	return false


func _start_vision_mode_on_confirmed_path() -> void:
	_confirmed_path_longpress_pending = false
	_confirmed_path_longpress_timer = 0.0

	# 初回検出と同じ閾値を使用（モバイルでは0.5m、PCでは0.15m）
	var threshold := GameConstants.PATH_CLICK_THRESHOLD_MOBILE if _confirmed_path_longpress_is_touch else GameConstants.PATH_CLICK_THRESHOLD

	if Debug.enabled: print("[PointDebug] _start_vision_mode_on_confirmed_path: attempting, threshold=%.2f" % threshold)
	if game_manager.try_start_vision_point_on_confirmed_path(
		_confirmed_path_longpress_screen_pos,
		_confirmed_path_longpress_ground_pos,
		threshold
	):
		if Debug.enabled: print("[PointDebug] _start_vision_mode_on_confirmed_path: success")
		_path_endpoint_extension_pending = false
		_path_endpoint_extension_started = false
	else:
		if Debug.enabled: print("[PointDebug] _start_vision_mode_on_confirmed_path: failed")
		_reset_confirmed_path_longpress()


func _reset_confirmed_path_longpress() -> void:
	_confirmed_path_longpress_pending = false
	_confirmed_path_longpress_timer = 0.0
	_confirmed_path_longpress_screen_pos = Vector2.ZERO
	_confirmed_path_longpress_ground_pos = Vector3.ZERO
	_confirmed_path_longpress_is_touch = false
	_confirmed_path_tap_path_data = {}
	_hide_progress_ring()


func _handle_path_tap_for_confirmed_path() -> void:
	if Debug.enabled: print("[PointDebug] _handle_path_tap_for_confirmed_path: called")
	if _confirmed_path_tap_path_data.is_empty():
		if Debug.enabled: print("[PointDebug] _handle_path_tap_for_confirmed_path: data is empty")
		return
	if not game_manager:
		return

	var current_time := Time.get_ticks_msec()
	var time_diff := current_time - _last_path_tap_time
	var is_same_path := _is_same_path(_last_path_tap_path_data, _confirmed_path_tap_path_data)
	if Debug.enabled: print("[PointDebug] _handle_path_tap_for_confirmed_path: time_diff=%d, is_same_path=%s, threshold=%d" % [time_diff, str(is_same_path), DOUBLE_TAP_THRESHOLD_MS])

	if time_diff <= DOUBLE_TAP_THRESHOLD_MS and is_same_path:
		if Debug.enabled: print("[PointDebug] _handle_path_tap_for_confirmed_path: DOUBLE TAP DETECTED - adding wait point")
		# ダブルタップ: コンテキストメニュータイマーをキャンセルしてWaitPoint直接追加
		_cancel_context_menu_timer()
		game_manager.add_sync_wait_point(_confirmed_path_tap_path_data)
		_last_path_tap_time = 0
		_last_path_tap_path_data = {}
	else:
		if Debug.enabled: print("[PointDebug] _handle_path_tap_for_confirmed_path: single tap, starting context menu timer")
		_last_path_tap_time = current_time
		_last_path_tap_path_data = _confirmed_path_tap_path_data.duplicate()
		# シングルタップ: 300ms後にコンテキストメニュー表示
		_start_context_menu_timer(_confirmed_path_longpress_screen_pos, _confirmed_path_tap_path_data)

#endregion


#region 移動中パス上長押し処理

func _start_vision_mode_on_moving_path() -> void:
	_moving_path_longpress_pending = false
	_moving_path_longpress_timer = 0.0

	if _moving_path_longpress_data.is_empty():
		if Debug.enabled: print("[PointDebug] _start_vision_mode_on_moving_path: no data")
		return

	if Debug.enabled: print("[PointDebug] _start_vision_mode_on_moving_path: started, ratio=%.3f" % _moving_path_longpress_data.get("path_ratio", 0.0))
	_moving_path_vision_drawing = true


func _finish_moving_path_vision_point(screen_pos: Vector2) -> void:
	if not _moving_path_vision_drawing or _moving_path_longpress_data.is_empty():
		if Debug.enabled: print("[PointDebug] _finish_moving_path_vision_point: not drawing or no data")
		_reset_moving_path_longpress()
		return

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		if Debug.enabled: print("[PointDebug] _finish_moving_path_vision_point: no ground intersection")
		_reset_moving_path_longpress()
		return

	var target_point: Vector3 = intersect as Vector3
	target_point.y = 0.0

	var anchor: Vector3 = _moving_path_longpress_data.get("point", Vector3.ZERO)
	var path_ratio: float = _moving_path_longpress_data.get("path_ratio", 0.0)
	var character: Node = _moving_path_longpress_data.get("character")

	var direction = target_point - anchor
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		if Debug.enabled: print("[PointDebug] _finish_moving_path_vision_point: direction too short")
		_reset_moving_path_longpress()
		return

	if Debug.enabled: print("[PointDebug] _finish_moving_path_vision_point: adding point, ratio=%.3f, char_valid=%s" % [
		path_ratio, str(is_instance_valid(character))
	])
	game_manager.add_vision_point_to_moving_path(character, path_ratio, anchor, target_point)
	_reset_moving_path_longpress()


func _update_moving_path_vision_preview(screen_pos: Vector2) -> void:
	if _moving_path_longpress_data.is_empty():
		return

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return

	var target_point: Vector3 = intersect as Vector3
	target_point.y = 0.0

	var anchor: Vector3 = _moving_path_longpress_data.get("point", Vector3.ZERO)
	var path_ratio: float = _moving_path_longpress_data.get("path_ratio", 0.0)
	var character: Node = _moving_path_longpress_data.get("character")

	game_manager.update_moving_path_vision_preview(character, anchor, target_point, path_ratio)


func _reset_moving_path_longpress() -> void:
	_moving_path_longpress_pending = false
	_moving_path_longpress_timer = 0.0
	_moving_path_longpress_screen_pos = Vector2.ZERO
	_moving_path_longpress_data = {}
	_moving_path_vision_drawing = false
	_moving_path_tap_path_data = {}
	_hide_progress_ring()
	if game_manager:
		game_manager.clear_moving_path_vision_preview()


func _handle_path_tap_for_moving_path() -> void:
	if _moving_path_tap_path_data.is_empty():
		return
	if not game_manager:
		return

	var current_time := Time.get_ticks_msec()
	var time_diff := current_time - _last_path_tap_time
	var is_same_path := _is_same_path(_last_path_tap_path_data, _moving_path_tap_path_data)

	if time_diff <= DOUBLE_TAP_THRESHOLD_MS and is_same_path:
		# ダブルタップ: コンテキストメニュータイマーをキャンセルしてWaitPoint直接追加
		_cancel_context_menu_timer()
		game_manager.add_sync_wait_point(_moving_path_tap_path_data)
		_last_path_tap_time = 0
		_last_path_tap_path_data = {}
	else:
		_last_path_tap_time = current_time
		_last_path_tap_path_data = _moving_path_tap_path_data.duplicate()
		# シングルタップ: 300ms後にコンテキストメニュー表示
		_start_context_menu_timer(_moving_path_longpress_screen_pos, _moving_path_tap_path_data)


func _is_same_path(data1: Dictionary, data2: Dictionary) -> bool:
	if data1.is_empty() or data2.is_empty():
		return false
	var char1 = data1.get("character")
	var char2 = data2.get("character")
	return char1 == char2 and is_instance_valid(char1)

#endregion


#region パスモード終了ハンドラ

func _on_path_mode_ended() -> void:
	var current_frame = Engine.get_process_frames()
	if Debug.enabled: print("[PointDebug] _on_path_mode_ended: frame=%d, _left_button_pressed=%s" % [current_frame, left_button_pressed])

	if left_button_pressed:
		if Debug.enabled: print("[PointDebug] _on_path_mode_ended: skipping reset because left button still pressed (character switch)")
		_path_mode_ended_frame = current_frame
		return

	_path_endpoint_extension_pending = false
	_path_endpoint_extension_started = false
	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	left_button_pressed = false
	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()
	_path_mode_ended_frame = current_frame

	if _auto_execute_character and is_instance_valid(_auto_execute_character):
		if game_manager.has_pending_path_for_character(_auto_execute_character):
			if Debug.enabled: print("[PointDebug] _on_path_mode_ended: auto-executing path for %s" % _auto_execute_character.name)
			game_manager.execute_path_for_character(_auto_execute_character, false)
	_auto_execute_character = null


func _on_endpoint_drag_detected(screen_pos: Vector2) -> void:
	if Debug.enabled: print("[PointDebug] _on_endpoint_drag_detected: screen_pos=%s" % str(screen_pos))
	if not game_manager.is_path_mode():
		return

	game_manager.confirm_path()
	if _try_start_path_continuation_from_endpoint(screen_pos):
		_path_endpoint_extension_started = true
		_path_endpoint_extension_pending = false
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer.handle_drawing_press(screen_pos)
		if Debug.enabled: print("[PointDebug] _on_endpoint_drag_detected: path continuation started")

#endregion


#region コンテキストメニュータイマー

## コンテキストメニュー表示の遅延タイマーを開始（300ms）
func _start_context_menu_timer(screen_pos: Vector2, path_data: Dictionary) -> void:
	_cancel_context_menu_timer()
	_pending_context_menu_screen_pos = screen_pos
	_pending_context_menu_path_data = path_data.duplicate()
	if game_manager:
		_context_menu_timer = game_manager.get_tree().create_timer(0.3)
		_context_menu_timer.timeout.connect(_on_context_menu_timer_timeout, CONNECT_ONE_SHOT)


## コンテキストメニュータイマーをキャンセル
func _cancel_context_menu_timer() -> void:
	if _context_menu_timer and _context_menu_timer.timeout.is_connected(_on_context_menu_timer_timeout):
		_context_menu_timer.timeout.disconnect(_on_context_menu_timer_timeout)
	_context_menu_timer = null
	_pending_context_menu_screen_pos = Vector2.ZERO
	_pending_context_menu_path_data = {}


## コンテキストメニュータイマー完了時のコールバック
func _on_context_menu_timer_timeout() -> void:
	_context_menu_timer = null
	if _pending_context_menu_path_data.is_empty() or not game_manager:
		return
	game_manager.show_path_context_menu(_pending_context_menu_screen_pos, _pending_context_menu_path_data)
	_pending_context_menu_screen_pos = Vector2.ZERO
	_pending_context_menu_path_data = {}

#endregion


