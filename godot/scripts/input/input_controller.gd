class_name InputController
extends Node
## ゲーム画面の入力処理
##
## 責務:
## - カメラ操作（パン、ズーム）
## - クリック/タップの検出とGameManagerへの委譲
## - パスモード中はPathDrawerに委譲
##
## アーキテクチャ:
## - デバイス固有の入力処理はMouseInputHandler/TouchInputHandlerに委譲
## - このクラスは共通のゲームロジックを担当


#region 依存関係

var game_manager: GameManager = null
var camera_pan_controller: CameraPanController = null

## 入力デバイスハンドラ
var _mouse_handler: MouseInputHandler = null
var _touch_handler: TouchInputHandler = null

#endregion


#region UI要素

## 長押しプログレスリング
var _progress_ring: LongPressProgressRing = null

#endregion


#region 入力状態

## 左クリック押下時のスクリーン座標（ドラッグ判定用）
var _left_click_start_pos: Vector2 = Vector2.ZERO
## 左クリック中かどうか
var _left_button_pressed: bool = false
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


#region 初期化

func setup(manager: GameManager, pan_controller: CameraPanController) -> void:
	game_manager = manager
	camera_pan_controller = pan_controller
	_setup_input_handlers()
	_setup_progress_ring()
	_connect_path_mode_signals()


## 入力ハンドラを初期化
func _setup_input_handlers() -> void:
	_mouse_handler = MouseInputHandler.new()
	_touch_handler = TouchInputHandler.new()

	# マウスハンドラのシグナル接続
	_mouse_handler.press_detected.connect(_on_mouse_press)
	_mouse_handler.release_detected.connect(_on_mouse_release)
	_mouse_handler.drag_detected.connect(_on_mouse_drag)
	_mouse_handler.tap_detected.connect(_on_mouse_tap)
	_mouse_handler.zoom_requested.connect(_on_zoom_requested)

	# タッチハンドラのシグナル接続
	_touch_handler.press_detected.connect(_on_touch_press)
	_touch_handler.release_detected.connect(_on_touch_release)
	_touch_handler.drag_detected.connect(_on_touch_drag)
	_touch_handler.tap_detected.connect(_on_touch_tap)
	_touch_handler.zoom_requested.connect(_on_zoom_requested)
	_touch_handler.pinch_state_changed.connect(_on_pinch_state_changed)


## 長押しプログレスリングを初期化
func _setup_progress_ring() -> void:
	if not game_manager:
		return
	var ui_layer = game_manager.get_ui_layer()
	if not ui_layer:
		return
	_progress_ring = LongPressProgressRing.create(ui_layer, 25.0)
	_progress_ring.ring_width = 3.0
	_progress_ring.ring_color = Color(1.0, 1.0, 1.0, 0.9)
	_progress_ring.background_color = Color(0.2, 0.2, 0.2, 0.4)

	# パス先端ドラッグシグナルを接続
	var path_drawer = _get_path_drawer()
	if path_drawer:
		if not path_drawer.endpoint_drag_detected.is_connected(_on_endpoint_drag_detected):
			path_drawer.endpoint_drag_detected.connect(_on_endpoint_drag_detected)


## パスモード終了シグナルを接続
func _connect_path_mode_signals() -> void:
	if not game_manager or not game_manager.path_service:
		return
	var path_mode_controller = game_manager.path_service.path_mode_controller
	if path_mode_controller:
		if not path_mode_controller.mode_ended.is_connected(_on_path_mode_ended):
			path_mode_controller.mode_ended.connect(_on_path_mode_ended)
		if not path_mode_controller.mode_cancelled.is_connected(_on_path_mode_ended):
			path_mode_controller.mode_cancelled.connect(_on_path_mode_ended)

#endregion


#region 毎フレーム処理

func _process(delta: float) -> void:
	# 長押し検出（キャラクター回転用）
	if _left_button_pressed and not _is_rotation_mode and not _immediate_path_drawing_started:
		if _rotation_target_character and is_instance_valid(_rotation_target_character):
			_long_press_timer += delta
			_update_progress_ring(_left_click_start_pos, _long_press_timer, _long_press_threshold)
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


#region 入力イベント処理

func _unhandled_input(event: InputEvent) -> void:
	if not game_manager:
		return

	# デバッグログ
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		print("[PointDebug] _unhandled_input: mouse_left pressed=%s, is_path_mode=%s" % [
			str(event.pressed), str(game_manager.is_path_mode())
		])

	# タッチ入力の処理（最優先 - エミュレートマウスイベントより先に処理）
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_touch_event(event)
		return

	# タッチ入力優先：タッチ中、ピンチ中、またはタッチ直後はマウスイベントを無視
	# （iOSではタッチがマウスイベントとしてもエミュレートされるため）
	if _touch_handler.is_touch_active() or _touch_handler.is_pinching() or _mouse_handler.is_recent_touch():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			return

	# マウス/トラックパッド入力の処理
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventMagnifyGesture:
		_handle_mouse_event(event)
		return

#endregion


#region マウス入力処理

func _handle_mouse_event(event: InputEvent) -> void:
	# ピンチ中はマウスドラッグを無視（タッチエミュレーション対策）
	if _touch_handler.is_pinching() and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		return

	# Macトラックパッドジェスチャー（ピンチズーム）
	if event is InputEventMagnifyGesture:
		if absf(event.factor - 1.0) > 0.01:
			_mouse_handler.handle_input(event)
			get_viewport().set_input_as_handled()
		return

	# マウスホイール（カメラズーム）
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_mouse_handler.handle_input(event)
			return

	# パスモード中の処理
	if game_manager.is_path_mode():
		_handle_mouse_event_path_mode(event)
		return

	# 非パスモードの処理
	_handle_mouse_event_normal_mode(event)


## パスモード中のマウス入力処理
func _handle_mouse_event_path_mode(event: InputEvent) -> void:
	# 回転モード中のドラッグ処理
	if event is InputEventMouseMotion and _is_rotation_mode:
		_process_rotation_drag(event.position)
		get_viewport().set_input_as_handled()
		return

	# 即座パスモードでまだ描画開始していない場合のドラッグ検出
	if event is InputEventMouseMotion and _immediate_path_mode_started and not _immediate_path_drawing_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer.handle_drawing_press(_left_click_start_pos)
			_immediate_path_drawing_started = true
		return

	# パス先端延長の待機中にドラッグが開始された場合
	if event is InputEventMouseMotion and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
		print("[PointDebug] path_mode: starting path extension from pending (mouse motion)")
		game_manager.confirm_path()
		if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
			_path_endpoint_extension_started = true
			_path_endpoint_extension_pending = false
			print("[PointDebug] path_mode: ext_started=true (from mouse motion)")
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
			return
		else:
			_path_endpoint_extension_pending = false

	# パス先端延長モードでドラッグ中
	if event is InputEventMouseMotion and _path_endpoint_extension_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer._handle_movement_input(event)
			get_viewport().set_input_as_handled()
		return

	# マウスボタンリリース
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_handle_path_mode_mouse_release(event.position)
		return

	# マウスボタンプレス
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_path_mode_mouse_press(event.position)
		return


## パスモード中のマウスリリース処理
func _handle_path_mode_mouse_release(position: Vector2) -> void:
	print("[PointDebug] path_mode mouse release: is_path_mode=%s, ext_started=%s, ext_pending=%s, longpress_pending=%s" % [
		str(game_manager.is_path_mode()), str(_path_endpoint_extension_started), str(_path_endpoint_extension_pending), str(_confirmed_path_longpress_pending)
	])
	_left_button_pressed = false

	if _is_rotation_mode:
		_end_rotation_mode()
		get_viewport().set_input_as_handled()
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
		print("[PointDebug] path_mode mouse release: confirming path (ext_started=true)")
		var drawer = _get_path_drawer()
		if drawer:
			drawer._handle_drawing_release()
		game_manager.confirm_path()
	# 実行中キャラクターに新しいパスを描いた場合
	elif _immediate_path_drawing_started and _auto_execute_character:
		print("[PointDebug] path_mode mouse release: auto-confirming path for executing character")
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

	if camera_pan_controller:
		if camera_pan_controller.is_dragging():
			camera_pan_controller.end_drag()
		elif camera_pan_controller.is_pending_drag():
			camera_pan_controller.cancel_potential_drag()


## パスモード中のマウスプレス処理
func _handle_path_mode_mouse_press(position: Vector2) -> void:
	_left_button_pressed = true
	_left_click_start_pos = position
	_long_press_timer = 0.0

	var clicked = game_manager.raycast_character(position)
	print("[PointDebug] path_mode click: clicked=%s" % (clicked.name if clicked else "null"))

	if clicked:
		var is_enemy = PlayerState.is_enemy(clicked)
		var is_following = game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)
		print("[PointDebug] path_mode click: is_enemy=%s, is_following=%s" % [is_enemy, is_following])

		if not is_enemy:
			if is_following:
				game_manager.path_service.cancel_path_following(clicked, true)
				_auto_execute_character = clicked

			_rotation_target_character = clicked
			print("[PointDebug] path_mode click: confirming current path and selecting %s" % clicked.name)
			game_manager.confirm_path()
			print("[PointDebug] path_mode click: after confirm, is_path_mode=%s" % game_manager.is_path_mode())
			game_manager.selection_manager.deselect_all()
			game_manager.selection_manager.add_to_selection(clicked)
			_immediate_path_mode_started = true
			_immediate_path_drawing_started = false
			print("[PointDebug] path_mode click: set _immediate_path_mode_started=true for %s" % clicked.name)
			get_viewport().set_input_as_handled()
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
		get_viewport().set_input_as_handled()


## 非パスモードのマウス入力処理
func _handle_mouse_event_normal_mode(event: InputEvent) -> void:
	# 左クリック
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed:
			_handle_normal_mode_press(mouse_event.position, false)
		else:
			_handle_normal_mode_release(mouse_event.position, false)
		return

	# マウスドラッグ
	if event is InputEventMouseMotion and _left_button_pressed:
		_handle_normal_mode_drag(event.position, false)
		return

#endregion


#region タッチ入力処理

func _handle_touch_event(event: InputEvent) -> void:
	if not camera_pan_controller:
		return

	# タッチ時刻を記録（エミュレートマウスイベント対策 - 最初に記録）
	_mouse_handler.record_touch_time()

	# タッチカウントを先に取得（リリース前の値が必要）
	var touch_count_before = _touch_handler.get_touch_count()

	# タッチ開始/終了でフラグを更新
	if event is InputEventScreenTouch:
		_touch_handler.handle_input(event)

	# CameraPanControllerにもタッチ追跡を通知（ピンチズーム用）
	camera_pan_controller.track_touch(event)

	# 2本指以上：ピンチズーム（パスモード中でも有効）
	if camera_pan_controller.get_touch_count() >= 2 or camera_pan_controller.is_pinching():
		if camera_pan_controller.handle_pinch(event):
			get_viewport().set_input_as_handled()
		return

	# パスモード中の処理
	if game_manager.is_path_mode():
		_handle_touch_event_path_mode(event, touch_count_before)
		return

	# 非パスモードの処理
	_handle_touch_event_normal_mode(event, touch_count_before)


## パスモード中のタッチ入力処理
func _handle_touch_event_path_mode(event: InputEvent, _touch_count_before: int) -> void:
	var path_drawer = _get_path_drawer()

	# ポイントモード中
	if path_drawer and path_drawer.is_point_mode():
		if path_drawer.handle_point_touch_input(event):
			get_viewport().set_input_as_handled()
			return

	# 回転モード中のドラッグ処理
	if event is InputEventScreenDrag and _is_rotation_mode:
		_process_rotation_drag(event.position)
		get_viewport().set_input_as_handled()
		return

	# 即座パスモードでまだ描画開始していない場合
	if event is InputEventScreenDrag and _immediate_path_mode_started and not _immediate_path_drawing_started:
		if path_drawer:
			path_drawer.handle_drawing_press(_left_click_start_pos)
			_immediate_path_drawing_started = true
		return

	# パス先端延長の待機中にドラッグが開始された場合
	if event is InputEventScreenDrag and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
		print("[PointDebug] path_mode: starting path extension from pending (touch drag)")
		game_manager.confirm_path()
		if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
			_path_endpoint_extension_started = true
			_path_endpoint_extension_pending = false
			print("[PointDebug] path_mode: ext_started=true (from touch drag)")
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
			return
		else:
			_path_endpoint_extension_pending = false

	# パス先端延長モードでドラッグ中
	if event is InputEventScreenDrag and _path_endpoint_extension_started:
		if path_drawer:
			path_drawer._handle_movement_input(event)
			get_viewport().set_input_as_handled()
		return

	# タッチ終了
	if event is InputEventScreenTouch and not event.pressed:
		_handle_path_mode_touch_release(event.position, path_drawer)
		return

	# タッチ開始
	if event is InputEventScreenTouch and event.pressed:
		_handle_path_mode_touch_press(event.position, path_drawer)
		return


## パスモード中のタッチリリース処理
func _handle_path_mode_touch_release(position: Vector2, path_drawer: PathDrawer) -> void:
	_left_button_pressed = false

	if _is_rotation_mode:
		_end_rotation_mode()
		get_viewport().set_input_as_handled()
		return

	# 確認済みパス長押し待機中だった場合（タップ判定 → ダブルタップ検出）
	if _confirmed_path_longpress_pending:
		_handle_path_tap_for_confirmed_path()
		_reset_confirmed_path_longpress()
		get_viewport().set_input_as_handled()
		return

	# 移動中パス長押し待機中だった場合（タップ判定 → ダブルタップ検出）
	if _moving_path_longpress_pending:
		_handle_path_tap_for_moving_path()
		_reset_moving_path_longpress()
		get_viewport().set_input_as_handled()
		return

	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()

	if _path_endpoint_extension_started:
		if path_drawer:
			path_drawer._handle_drawing_release()
		game_manager.confirm_path()
	elif _immediate_path_drawing_started and _auto_execute_character:
		print("[PointDebug] touch path_mode release: auto-confirming path for executing character")
		if path_drawer:
			path_drawer._handle_drawing_release()
		game_manager.confirm_path()

	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	_path_endpoint_extension_pending = false
	_path_endpoint_extension_started = false

	if path_drawer and path_drawer.is_point_mode():
		path_drawer.handle_point_release(position)

	if camera_pan_controller.is_touch_panning():
		camera_pan_controller.end_touch_pan()
	elif camera_pan_controller.is_pending_touch_pan():
		camera_pan_controller.cancel_potential_touch_pan()


## パスモード中のタッチプレス処理
func _handle_path_mode_touch_press(position: Vector2, path_drawer: PathDrawer) -> void:
	_left_button_pressed = true
	_left_click_start_pos = position
	_long_press_timer = 0.0

	var clicked = game_manager.raycast_character(position)
	print("[PointDebug] touch path_mode click: clicked=%s" % (clicked.name if clicked else "null"))

	if clicked:
		var is_enemy = PlayerState.is_enemy(clicked)
		var is_following = game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)
		print("[PointDebug] touch path_mode click: is_enemy=%s, is_following=%s" % [is_enemy, is_following])

		if not is_enemy:
			if is_following:
				game_manager.path_service.cancel_path_following(clicked, true)
				_auto_execute_character = clicked

			_rotation_target_character = clicked
			print("[PointDebug] touch path_mode click: confirming current path and selecting %s" % clicked.name)
			game_manager.confirm_path()
			print("[PointDebug] touch path_mode click: after confirm, is_path_mode=%s" % game_manager.is_path_mode())
			game_manager.selection_manager.deselect_all()
			game_manager.selection_manager.add_to_selection(clicked)
			_immediate_path_mode_started = true
			_immediate_path_drawing_started = false
			print("[PointDebug] touch path_mode click: set _immediate_path_mode_started=true for %s" % clicked.name)
			get_viewport().set_input_as_handled()
			return

		game_manager.handle_click(position, MOUSE_BUTTON_LEFT)
		get_viewport().set_input_as_handled()
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
		get_viewport().set_input_as_handled()


## 非パスモードのタッチ入力処理
func _handle_touch_event_normal_mode(event: InputEvent, touch_count_before: int) -> void:
	var is_one_finger = camera_pan_controller.get_touch_count() == 1
	var is_one_finger_release = event is InputEventScreenTouch and not event.pressed and touch_count_before == 1

	if not (is_one_finger or is_one_finger_release):
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_normal_mode_press(event.position, true)
		else:
			_handle_normal_mode_release(event.position, true)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		_handle_normal_mode_drag(event.position, true)
		get_viewport().set_input_as_handled()

#endregion


#region 共通入力処理（非パスモード）

## 非パスモードのプレス処理
func _handle_normal_mode_press(position: Vector2, is_touch: bool) -> void:
	print("[PointDebug] non-path_mode press: is_path_mode=%s, is_touch=%s" % [str(game_manager.is_path_mode()), str(is_touch)])
	_left_button_pressed = true
	_left_click_start_pos = position
	_long_press_timer = 0.0

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
		get_viewport().set_input_as_handled()
		return

	# 確認済みパス上の長押しを検出
	if _try_start_confirmed_path_longpress(position, is_touch):
		get_viewport().set_input_as_handled()
		return

	# パス先端近くをタップした場合
	_path_endpoint_extension_pending = true
	_path_endpoint_extension_started = false


## 非パスモードのリリース処理
func _handle_normal_mode_release(position: Vector2, is_touch: bool) -> void:
	print("[PointDebug] _handle_normal_mode_release: is_touch=%s, _confirmed_path_longpress_pending=%s" % [str(is_touch), str(_confirmed_path_longpress_pending)])
	_left_button_pressed = false

	if _is_rotation_mode:
		_end_rotation_mode()
		return

	if _moving_path_vision_drawing:
		_finish_moving_path_vision_point(position)
		return

	if _confirmed_path_longpress_pending:
		print("[PointDebug] _handle_normal_mode_release: calling _handle_path_tap_for_confirmed_path")
		_handle_path_tap_for_confirmed_path()
		_reset_confirmed_path_longpress()
		return

	if _moving_path_longpress_pending:
		print("[PointDebug] _handle_normal_mode_release: calling _handle_path_tap_for_moving_path")
		_handle_path_tap_for_moving_path()
		_reset_moving_path_longpress()
		return

	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()

	# カメラドラッグ中だった場合
	if is_touch:
		if camera_pan_controller.is_touch_panning():
			camera_pan_controller.end_touch_pan()
			return
		if camera_pan_controller.is_pending_touch_pan():
			camera_pan_controller.cancel_potential_touch_pan()
	else:
		if camera_pan_controller and camera_pan_controller.is_dragging():
			camera_pan_controller.end_drag()
			return
		if camera_pan_controller and camera_pan_controller.is_pending_drag():
			camera_pan_controller.cancel_potential_drag()

	if _immediate_path_mode_started:
		_immediate_path_mode_started = false
		_immediate_path_drawing_started = false
		return

	if _path_endpoint_extension_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer._handle_drawing_release()
		game_manager.confirm_path()
		_path_endpoint_extension_pending = false
		_path_endpoint_extension_started = false
		return

	if _path_endpoint_extension_pending:
		_path_endpoint_extension_pending = false
		if _is_near_path_endpoint(_left_click_start_pos):
			return

	_path_endpoint_extension_started = false

	# タップ判定
	var tap_threshold = 20.0 if is_touch else 50.0
	var distance = _left_click_start_pos.distance_to(position)
	if distance < tap_threshold:
		_handle_tap(position)


## 非パスモードのドラッグ処理
func _handle_normal_mode_drag(position: Vector2, is_touch: bool) -> void:
	var current_frame = Engine.get_process_frames()
	var just_ended = (current_frame == _path_mode_ended_frame)
	print("[PointDebug] non-path_mode drag: frame=%d, ended_frame=%d, just_ended=%s, ext_pending=%s" % [
		current_frame, _path_mode_ended_frame, str(just_ended), str(_path_endpoint_extension_pending)
	])

	# 回転モード中
	if _is_rotation_mode:
		_process_rotation_drag(position)
		get_viewport().set_input_as_handled()
		return

	# 移動中パスVision描画中
	if _moving_path_vision_drawing:
		_update_moving_path_vision_preview(position)
		get_viewport().set_input_as_handled()
		return

	# 確認済みパス長押し待機中にドラッグが検出された場合
	if _confirmed_path_longpress_pending:
		var move_dist = position.distance_to(_confirmed_path_longpress_screen_pos)
		if move_dist > 20.0:
			_reset_confirmed_path_longpress()
			if is_touch:
				camera_pan_controller.start_potential_touch_pan(_left_click_start_pos)
			elif camera_pan_controller:
				camera_pan_controller.start_potential_drag(_left_click_start_pos)

	# 移動中パス長押し待機中にドラッグが検出された場合
	if _moving_path_longpress_pending:
		var move_dist = position.distance_to(_moving_path_longpress_screen_pos)
		if move_dist > 20.0:
			var path_ratio: float = _moving_path_longpress_data.get("path_ratio", 0.0)
			if path_ratio >= 0.99:
				print("[PointDebug] non-path_mode: longpress cancelled, trying path extension")
				_reset_moving_path_longpress()
				if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
					_path_endpoint_extension_started = true
					print("[PointDebug] non-path_mode: ext_started=true (from longpress cancel)")
					var path_drawer = _get_path_drawer()
					if path_drawer:
						path_drawer.handle_drawing_press(_left_click_start_pos)
					return

			_reset_moving_path_longpress()
			if is_touch:
				camera_pan_controller.start_potential_touch_pan(_left_click_start_pos)
			elif camera_pan_controller:
				camera_pan_controller.start_potential_drag(_left_click_start_pos)

	# 即座パスモードでドラッグが検出された場合
	var drag_distance = position.distance_to(_left_click_start_pos)
	print("[PointDebug] non-path_mode drag: _immediate_path_mode_started=%s, _immediate_path_drawing_started=%s, drag_distance=%.1f" % [_immediate_path_mode_started, _immediate_path_drawing_started, drag_distance])
	if _immediate_path_mode_started and not _immediate_path_drawing_started and drag_distance > _min_drag_distance:
		print("[PointDebug] non-path_mode drag: starting path mode for character (drag_distance=%.1f > %.1f)" % [drag_distance, _min_drag_distance])
		_rotation_target_character = null
		_long_press_timer = 0.0
		_hide_progress_ring()
		var result = game_manager.start_move_mode()
		print("[PointDebug] non-path_mode drag: start_move_mode result=%s" % result)
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer.handle_drawing_press(_left_click_start_pos)
		_immediate_path_drawing_started = true
		return

	# パス先端延長の待機中にドラッグが開始された場合
	if _path_endpoint_extension_pending and not _path_endpoint_extension_started and not just_ended:
		print("[PointDebug] non-path_mode: trying path extension from pending (drag)")
		if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
			_path_endpoint_extension_started = true
			_path_endpoint_extension_pending = false
			print("[PointDebug] non-path_mode: ext_started=true (drag)")
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
			return
		else:
			_path_endpoint_extension_pending = false
			if is_touch:
				camera_pan_controller.start_potential_touch_pan(_left_click_start_pos)
			elif camera_pan_controller:
				camera_pan_controller.start_potential_drag(_left_click_start_pos)

	# パス先端延長モードでドラッグ中
	if _path_endpoint_extension_started:
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer._handle_movement_input_with_position(position)
			get_viewport().set_input_as_handled()
		return

	# カメラパン処理
	if is_touch:
		if camera_pan_controller.is_pending_touch_pan():
			camera_pan_controller.check_and_start_touch_pan(position)
		if camera_pan_controller.is_touch_panning():
			camera_pan_controller.update_touch_pan(position)
	else:
		if camera_pan_controller and camera_pan_controller.is_pending_drag():
			camera_pan_controller.check_and_start_drag(position)
		if camera_pan_controller and camera_pan_controller.is_dragging():
			# マウスモーションイベントを作成してhandle_inputに渡す
			var motion := InputEventMouseMotion.new()
			motion.position = position
			camera_pan_controller.handle_input(motion)
			get_viewport().set_input_as_handled()

#endregion


#region ハンドラシグナルコールバック

func _on_mouse_press(_position: Vector2) -> void:
	# マウスプレスはイベント処理内で直接処理
	pass


func _on_mouse_release(_position: Vector2, _was_dragging: bool) -> void:
	# マウスリリースはイベント処理内で直接処理
	pass


func _on_mouse_drag(_position: Vector2, _distance_from_start: float) -> void:
	# マウスドラッグはイベント処理内で直接処理
	pass


func _on_mouse_tap(_position: Vector2) -> void:
	# マウスタップはイベント処理内で直接処理
	pass


func _on_touch_press(_position: Vector2) -> void:
	# タッチプレスはイベント処理内で直接処理
	pass


func _on_touch_release(_position: Vector2, _was_dragging: bool) -> void:
	# タッチリリースはイベント処理内で直接処理
	pass


func _on_touch_drag(_position: Vector2, _distance_from_start: float) -> void:
	# タッチドラッグはイベント処理内で直接処理
	pass


func _on_touch_tap(_position: Vector2) -> void:
	# タッチタップはイベント処理内で直接処理
	pass


func _on_zoom_requested(amount: float) -> void:
	if camera_pan_controller:
		camera_pan_controller._zoom_by(amount)


func _on_pinch_state_changed(_is_pinching: bool) -> void:
	# ピンチ状態変更は必要に応じて処理
	pass

#endregion


#region キャラクター・パス操作

## タップダウン時にキャラクターを即座に選択
func _try_start_immediate_path_mode(screen_pos: Vector2) -> bool:
	var clicked = game_manager.raycast_character(screen_pos)
	if not clicked:
		return false
	if PlayerState.is_enemy(clicked):
		return false

	if game_manager.path_service and game_manager.path_service.is_character_following_path(clicked):
		game_manager.path_service.cancel_path_following(clicked, true)
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


func _end_rotation_mode() -> void:
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

func _update_progress_ring(screen_pos: Vector2, elapsed: float, threshold: float) -> void:
	if not _progress_ring:
		return
	if not _progress_ring.is_active():
		_progress_ring.start_manual(screen_pos)
	_progress_ring.update_progress(elapsed, threshold)


func _hide_progress_ring() -> void:
	if _progress_ring:
		_progress_ring.cancel()

#endregion


#region タップ/クリック処理

func _handle_tap(pos: Vector2) -> void:
	game_manager.handle_click(pos, MOUSE_BUTTON_LEFT)

#endregion


#region ユーティリティ

func _get_path_drawer() -> PathDrawer:
	return game_manager.path_drawer as PathDrawer


func _is_near_path_endpoint(screen_pos: Vector2) -> bool:
	if not game_manager or not game_manager.path_execution_manager or not game_manager.camera:
		return false

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return false

	var ground_pos: Vector3 = intersect as Vector3
	var result := game_manager.path_execution_manager.find_path_endpoint_at_position(ground_pos, GameConstants.PATH_CLICK_THRESHOLD)
	return not result.is_empty()

#endregion


#region 確認済みパス上長押し処理

func _try_start_confirmed_path_longpress(screen_pos: Vector2, is_touch: bool = false) -> bool:
	print("[PointDebug] _try_start_confirmed_path_longpress: called, is_touch=%s" % str(is_touch))
	if not game_manager or not game_manager.path_execution_manager or not game_manager.camera:
		print("[PointDebug] _try_start_confirmed_path_longpress: no manager")
		return false

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return false

	var ground_pos: Vector3 = intersect as Vector3
	print("[PointDebug] _try_start_confirmed_path_longpress: ground_pos=%s" % [ground_pos])

	# モバイルではタッチ精度が低いため、より大きな閾値を使用
	var threshold := GameConstants.PATH_CLICK_THRESHOLD_MOBILE if is_touch else GameConstants.PATH_CLICK_THRESHOLD

	var result := game_manager.path_execution_manager.find_path_point_at_position(ground_pos, threshold)
	print("[PointDebug] _try_start_confirmed_path_longpress: find_path_point result=%s, threshold=%.2f" % [result, threshold])
	if not result.is_empty():
		print("[PointDebug] _try_start_confirmed_path_longpress: starting longpress for confirmed path")
		_confirmed_path_longpress_pending = true
		_confirmed_path_longpress_timer = 0.0
		_confirmed_path_longpress_screen_pos = screen_pos
		_confirmed_path_longpress_ground_pos = ground_pos
		_confirmed_path_tap_path_data = result
		return true

	var moving_result := game_manager.try_start_vision_point_on_moving_path(screen_pos, ground_pos, threshold)
	print("[PointDebug] _try_start_confirmed_path_longpress: moving_result=%s" % [moving_result])
	if not moving_result.is_empty():
		print("[PointDebug] _try_start_confirmed_path_longpress: starting longpress for moving path")
		_moving_path_longpress_pending = true
		_moving_path_longpress_timer = 0.0
		_moving_path_longpress_screen_pos = screen_pos
		_moving_path_longpress_data = moving_result
		_moving_path_tap_path_data = moving_result
		return true

	print("[PointDebug] _try_start_confirmed_path_longpress: no path found, returning false")
	return false


func _start_vision_mode_on_confirmed_path() -> void:
	_confirmed_path_longpress_pending = false
	_confirmed_path_longpress_timer = 0.0

	print("[PointDebug] _start_vision_mode_on_confirmed_path: attempting")
	if game_manager.try_start_vision_point_on_confirmed_path(
		_confirmed_path_longpress_screen_pos,
		_confirmed_path_longpress_ground_pos
	):
		print("[PointDebug] _start_vision_mode_on_confirmed_path: success")
		_path_endpoint_extension_pending = false
		_path_endpoint_extension_started = false
	else:
		print("[PointDebug] _start_vision_mode_on_confirmed_path: failed")


func _reset_confirmed_path_longpress() -> void:
	_confirmed_path_longpress_pending = false
	_confirmed_path_longpress_timer = 0.0
	_confirmed_path_longpress_screen_pos = Vector2.ZERO
	_confirmed_path_longpress_ground_pos = Vector3.ZERO
	_confirmed_path_tap_path_data = {}
	_hide_progress_ring()


func _handle_path_tap_for_confirmed_path() -> void:
	print("[PointDebug] _handle_path_tap_for_confirmed_path: called")
	if _confirmed_path_tap_path_data.is_empty():
		print("[PointDebug] _handle_path_tap_for_confirmed_path: data is empty")
		return
	if not game_manager:
		return

	var current_time := Time.get_ticks_msec()
	var time_diff := current_time - _last_path_tap_time
	var is_same_path := _is_same_path(_last_path_tap_path_data, _confirmed_path_tap_path_data)
	print("[PointDebug] _handle_path_tap_for_confirmed_path: time_diff=%d, is_same_path=%s, threshold=%d" % [time_diff, str(is_same_path), DOUBLE_TAP_THRESHOLD_MS])

	if time_diff <= DOUBLE_TAP_THRESHOLD_MS and is_same_path:
		print("[PointDebug] _handle_path_tap_for_confirmed_path: DOUBLE TAP DETECTED - adding wait point")
		game_manager.add_sync_wait_point(_confirmed_path_tap_path_data)
		_last_path_tap_time = 0
		_last_path_tap_path_data = {}
	else:
		print("[PointDebug] _handle_path_tap_for_confirmed_path: single tap, saving for next")
		_last_path_tap_time = current_time
		_last_path_tap_path_data = _confirmed_path_tap_path_data.duplicate()

#endregion


#region 移動中パス上長押し処理

func _start_vision_mode_on_moving_path() -> void:
	_moving_path_longpress_pending = false
	_moving_path_longpress_timer = 0.0

	if _moving_path_longpress_data.is_empty():
		print("[PointDebug] _start_vision_mode_on_moving_path: no data")
		return

	print("[PointDebug] _start_vision_mode_on_moving_path: started, ratio=%.3f" % _moving_path_longpress_data.get("path_ratio", 0.0))
	_moving_path_vision_drawing = true


func _finish_moving_path_vision_point(screen_pos: Vector2) -> void:
	if not _moving_path_vision_drawing or _moving_path_longpress_data.is_empty():
		print("[PointDebug] _finish_moving_path_vision_point: not drawing or no data")
		_reset_moving_path_longpress()
		return

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		print("[PointDebug] _finish_moving_path_vision_point: no ground intersection")
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
		print("[PointDebug] _finish_moving_path_vision_point: direction too short")
		_reset_moving_path_longpress()
		return

	print("[PointDebug] _finish_moving_path_vision_point: adding point, ratio=%.3f, char_valid=%s" % [
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
		game_manager.add_sync_wait_point(_moving_path_tap_path_data)
		_last_path_tap_time = 0
		_last_path_tap_path_data = {}
	else:
		_last_path_tap_time = current_time
		_last_path_tap_path_data = _moving_path_tap_path_data.duplicate()


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
	print("[PointDebug] _on_path_mode_ended: frame=%d, _left_button_pressed=%s" % [current_frame, _left_button_pressed])

	if _left_button_pressed:
		print("[PointDebug] _on_path_mode_ended: skipping reset because left button still pressed (character switch)")
		_path_mode_ended_frame = current_frame
		return

	_path_endpoint_extension_pending = false
	_path_endpoint_extension_started = false
	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	_left_button_pressed = false
	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()
	_path_mode_ended_frame = current_frame

	if _auto_execute_character and is_instance_valid(_auto_execute_character):
		if game_manager.path_service and game_manager.path_service.has_pending_path_for_character(_auto_execute_character):
			print("[PointDebug] _on_path_mode_ended: auto-executing path for %s" % _auto_execute_character.name)
			game_manager.path_service.execute_path_for_character(_auto_execute_character, false)
	_auto_execute_character = null


func _on_endpoint_drag_detected(screen_pos: Vector2) -> void:
	print("[PointDebug] _on_endpoint_drag_detected: screen_pos=%s" % str(screen_pos))
	if not game_manager.is_path_mode():
		return

	game_manager.confirm_path()
	if _try_start_path_continuation_from_endpoint(screen_pos):
		_path_endpoint_extension_started = true
		_path_endpoint_extension_pending = false
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer.handle_drawing_press(screen_pos)
		print("[PointDebug] _on_endpoint_drag_detected: path continuation started")

#endregion
