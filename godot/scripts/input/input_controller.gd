class_name InputController
extends Node
## ゲーム画面の入力処理
##
## 責務:
## - 入力イベントの受信とハンドラへの委譲
## - マウス/タッチハンドラのシグナル接続
##
## アーキテクチャ:
## - CameraInputHandler: カメラ操作
## - PathInputHandler: パス関連の入力処理
## - MouseInputHandler/TouchInputHandler: デバイス固有の入力処理


#region 依存関係

var game_manager: GameManager = null
var camera_pan_controller: CameraPanController = null

## 入力デバイスハンドラ
var _mouse_handler: MouseInputHandler = null
var _touch_handler: TouchInputHandler = null

## 機能別ハンドラ
var _camera_handler: CameraInputHandler = null
var _path_handler: PathInputHandler = null

#endregion


#region 初期化

func setup(manager: GameManager, pan_controller: CameraPanController) -> void:
	game_manager = manager
	camera_pan_controller = pan_controller
	_setup_input_handlers()


## 入力ハンドラを初期化
func _setup_input_handlers() -> void:
	# デバイスハンドラの初期化
	_mouse_handler = MouseInputHandler.new()
	_touch_handler = TouchInputHandler.new()

	# 機能別ハンドラの初期化
	_camera_handler = CameraInputHandler.new()
	_camera_handler.setup(camera_pan_controller)

	_path_handler = PathInputHandler.new()
	_path_handler.setup(game_manager, _camera_handler)

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

#endregion


#region 毎フレーム処理

func _process(delta: float) -> void:
	# タイマー更新をPathHandlerに委譲
	if _path_handler:
		_path_handler.update_timers(delta)

#endregion


#region 入力イベント処理

func _unhandled_input(event: InputEvent) -> void:
	if not game_manager:
		return

	# デバッグログ
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Debug.enabled: print("[PointDebug] _unhandled_input: mouse_left pressed=%s, is_path_mode=%s" % [
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

	# グレネードターゲットモードはパスモードより優先
	if game_manager.is_grenade_target_mode():
		_handle_mouse_event_normal_mode(event)
		return

	# パスモード中の処理
	if game_manager.is_path_mode():
		_path_handler.handle_mouse_event_path_mode(event, get_viewport())
		return

	# 非パスモードの処理
	_handle_mouse_event_normal_mode(event)


## 非パスモードのマウス入力処理
func _handle_mouse_event_normal_mode(event: InputEvent) -> void:
	# グレネードターゲットモード中のモーション → プレビュー更新
	if event is InputEventMouseMotion and game_manager.is_grenade_target_mode():
		game_manager.update_grenade_target_preview(event.position)
		return

	# 左クリック
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed:
			_path_handler.handle_normal_mode_press(mouse_event.position, false, get_viewport())
		else:
			if _path_handler.handle_normal_mode_release(mouse_event.position, false):
				_handle_tap(mouse_event.position)
		return

	# マウスドラッグ
	if event is InputEventMouseMotion and _path_handler.left_button_pressed:
		_handle_normal_mode_drag(event.position, false)
		return

#endregion


#region タッチ入力処理

func _handle_touch_event(event: InputEvent) -> void:
	if not _camera_handler:
		return

	# タッチ時刻を記録（エミュレートマウスイベント対策 - 最初に記録）
	_mouse_handler.record_touch_time()

	# タッチカウントを先に取得（リリース前の値が必要）
	var touch_count_before = _touch_handler.get_touch_count()

	# タッチ開始/終了でフラグを更新
	if event is InputEventScreenTouch:
		_touch_handler.handle_input(event)

	# CameraPanControllerにもタッチ追跡を通知（ピンチズーム用）
	_camera_handler.track_touch(event)

	# 2本指以上：ピンチズーム（パスモード中でも有効）
	if _camera_handler.get_touch_count() >= 2 or camera_pan_controller.is_pinching():
		if _camera_handler.handle_pinch(event):
			get_viewport().set_input_as_handled()
		return

	# グレネードターゲットモードはパスモードより優先
	if game_manager.is_grenade_target_mode():
		_handle_touch_event_normal_mode(event, touch_count_before)
		return

	# パスモード中の処理
	if game_manager.is_path_mode():
		_path_handler.handle_touch_event_path_mode(event, get_viewport())
		return

	# 非パスモードの処理
	_handle_touch_event_normal_mode(event, touch_count_before)


## 非パスモードのタッチ入力処理
func _handle_touch_event_normal_mode(event: InputEvent, touch_count_before: int) -> void:
	var is_one_finger = _camera_handler.get_touch_count() == 1
	var is_one_finger_release = event is InputEventScreenTouch and not event.pressed and touch_count_before == 1

	if not (is_one_finger or is_one_finger_release):
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			# グレネードターゲットモード中はプレビュー初回表示
			if game_manager.is_grenade_target_mode():
				game_manager.update_grenade_target_preview(event.position)
			else:
				_path_handler.handle_normal_mode_press(event.position, true, get_viewport())
		else:
			# グレネードターゲットモード中はリリースで直接タップ確定
			if game_manager.is_grenade_target_mode():
				_handle_tap(event.position)
			elif _path_handler.handle_normal_mode_release(event.position, true):
				_handle_tap(event.position)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		_handle_normal_mode_drag(event.position, true)
		get_viewport().set_input_as_handled()

#endregion


#region 共通入力処理（非パスモード）

## 非パスモードのドラッグ処理
func _handle_normal_mode_drag(position: Vector2, is_touch: bool) -> void:
	# グレネードターゲットモード中はプレビュー更新のみ
	if game_manager.is_grenade_target_mode():
		game_manager.update_grenade_target_preview(position)
		return

	var should_update_camera = _path_handler.handle_normal_mode_drag(position, is_touch, get_viewport())

	# カメラパン処理
	if should_update_camera:
		if is_touch:
			if _camera_handler.is_pending_touch_pan():
				_camera_handler.check_and_start_touch_pan(position)
			if _camera_handler.is_touch_panning():
				_camera_handler.update_touch_pan(position)
		else:
			if _camera_handler and _camera_handler.is_pending_drag():
				_camera_handler.check_and_start_drag(position)
			if _camera_handler and _camera_handler.is_dragging():
				# マウスモーションイベントを作成してhandle_inputに渡す
				var motion := InputEventMouseMotion.new()
				motion.position = position
				_camera_handler.update_drag(motion)
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
	if _camera_handler:
		_camera_handler.handle_mouse_zoom(amount)


func _on_pinch_state_changed(_is_pinching: bool) -> void:
	# ピンチ状態変更は必要に応じて処理
	pass

#endregion


#region タップ/クリック処理

func _handle_tap(pos: Vector2) -> void:
	game_manager.handle_click(pos, MOUSE_BUTTON_LEFT)

#endregion
