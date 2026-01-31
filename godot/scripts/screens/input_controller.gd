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

## 長押しプログレスリング
var _progress_ring: LongPressProgressRing = null

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

## 長押し回転モード用変数
var _long_press_timer: float = 0.0
var _long_press_threshold: float = 1.0  ## 長押し判定の閾値（秒）
var _is_rotation_mode: bool = false  ## 回転モード中かどうか
var _rotation_target_character: Node = null  ## 回転対象のキャラクター
var _rotation_center_screen_pos: Vector2 = Vector2.ZERO  ## 回転中心のスクリーン座標

## 確認済みパス上長押しでVisionポイント配置用
var _confirmed_path_longpress_pending: bool = false  ## 長押し待機中か
var _confirmed_path_longpress_timer: float = 0.0     ## 長押しタイマー
var _confirmed_path_longpress_threshold: float = 0.5  ## 長押し閾値（秒）
var _confirmed_path_longpress_screen_pos: Vector2 = Vector2.ZERO  ## 長押し開始スクリーン位置
var _confirmed_path_longpress_ground_pos: Vector3 = Vector3.ZERO  ## 長押し開始地面位置
var _confirmed_path_tap_path_data: Dictionary = {}  ## タップしたパスの情報（コンテキストメニュー用）

## 移動中パス上長押しでVisionポイント配置用
var _moving_path_longpress_pending: bool = false  ## 長押し待機中か
var _moving_path_longpress_timer: float = 0.0     ## 長押しタイマー
var _moving_path_longpress_threshold: float = 0.5  ## 長押し閾値（秒）
var _moving_path_longpress_screen_pos: Vector2 = Vector2.ZERO  ## 長押し開始スクリーン位置
var _moving_path_longpress_data: Dictionary = {}  ## 移動中パスの情報（character, path_ratio, point等）
var _moving_path_vision_drawing: bool = false  ## 移動中パスへのVision描画中か
var _moving_path_tap_path_data: Dictionary = {}  ## タップした移動中パスの情報（コンテキストメニュー用）

## パスモード終了直後のパス延長を禁止するフラグ（フレーム番号で管理）
var _path_mode_ended_frame: int = -1


func setup(manager: GameManager, pan_controller: CameraPanController) -> void:
	game_manager = manager
	camera_pan_controller = pan_controller
	_setup_progress_ring()
	_connect_path_mode_signals()


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

	# PathDrawerにもプログレスリングを設定
	var path_drawer = _get_path_drawer()
	if path_drawer:
		path_drawer.set_progress_ring(_progress_ring)
		# パス先端ドラッグシグナルを接続
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


func _process(delta: float) -> void:
	# 長押し検出（キャラクター回転用）
	if _left_button_pressed and not _is_rotation_mode and not _immediate_path_drawing_started:
		if _rotation_target_character and is_instance_valid(_rotation_target_character):
			_long_press_timer += delta
			# プログレスリングを更新
			_update_progress_ring(_left_click_start_pos, _long_press_timer, _long_press_threshold)
			if _long_press_timer >= _long_press_threshold:
				_hide_progress_ring()
				_start_rotation_mode()

	# 確認済みパス上長押し検出
	if _confirmed_path_longpress_pending:
		_confirmed_path_longpress_timer += delta
		# プログレスリングを更新
		_update_progress_ring(_confirmed_path_longpress_screen_pos, _confirmed_path_longpress_timer, _confirmed_path_longpress_threshold)
		if _confirmed_path_longpress_timer >= _confirmed_path_longpress_threshold:
			_hide_progress_ring()
			_start_vision_mode_on_confirmed_path()

	# 移動中パス上長押し検出
	if _moving_path_longpress_pending:
		_moving_path_longpress_timer += delta
		# プログレスリングを更新
		_update_progress_ring(_moving_path_longpress_screen_pos, _moving_path_longpress_timer, _moving_path_longpress_threshold)
		if _moving_path_longpress_timer >= _moving_path_longpress_threshold:
			_hide_progress_ring()
			_start_vision_mode_on_moving_path()


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


## パス先端をドラッグしてパス継続モードを開始
## @return: パス継続モードが開始された場合true
func _try_start_path_continuation_from_endpoint(screen_pos: Vector2) -> bool:
	return game_manager.try_start_path_continuation_at_position(screen_pos)


## 回転モードを開始
func _start_rotation_mode() -> void:
	if not _rotation_target_character or not is_instance_valid(_rotation_target_character):
		return
	_is_rotation_mode = true
	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	# キャラクターの位置をスクリーン座標に変換して回転中心とする
	var char_pos = _rotation_target_character.global_position
	_rotation_center_screen_pos = game_manager.camera.unproject_position(char_pos)


## 回転モードを終了
func _end_rotation_mode() -> void:
	_is_rotation_mode = false
	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()


## ========================================
## プログレスリング制御
## ========================================

## プログレスリングを更新（表示・進行率更新）
func _update_progress_ring(screen_pos: Vector2, elapsed: float, threshold: float) -> void:
	if not _progress_ring:
		return
	if not _progress_ring.is_active():
		_progress_ring.start_manual(screen_pos)
	_progress_ring.update_progress(elapsed, threshold)


## プログレスリングを非表示
func _hide_progress_ring() -> void:
	if _progress_ring:
		_progress_ring.cancel()


## 回転モード中のドラッグ処理
func _process_rotation_drag(screen_pos: Vector2) -> void:
	if not _rotation_target_character or not is_instance_valid(_rotation_target_character):
		_end_rotation_mode()
		return

	# スクリーン座標からキャラクター中心への方向を計算
	var dir_from_center = screen_pos - _rotation_center_screen_pos
	if dir_from_center.length() < 10.0:
		return  # 中心に近すぎる場合は無視

	# スクリーン座標の方向をワールド座標の方向に変換
	# スクリーン: 右が+X、下が+Y
	# ワールド: 右が+X、手前が-Z（カメラが上から見下ろしている場合）
	var angle = atan2(dir_from_center.x, dir_from_center.y)

	# キャラクターの向きを設定
	var direction = Vector3(sin(angle), 0, cos(angle))
	_rotation_target_character.set_facing_direction_vec(direction)


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
			# PathDrawerにドラッグイベントを伝播させる
			return

		# パス先端延長の待機中にドラッグが開始された場合
		if event is InputEventMouseMotion and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
			# 現在のパスを確定してからパス延長を試みる
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

		# パス先端延長モードでドラッグ中の場合、PathDrawerにイベントを渡す
		if event is InputEventMouseMotion and _path_endpoint_extension_started:
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer._handle_movement_input(event)
				get_viewport().set_input_as_handled()
			return

		# マウスボタンリリース時：カメラドラッグ状態をクリア
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			print("[PointDebug] path_mode mouse release: is_path_mode=%s, ext_started=%s, ext_pending=%s" % [
				str(game_manager.is_path_mode()), str(_path_endpoint_extension_started), str(_path_endpoint_extension_pending)
			])
			_left_button_pressed = false
			# 回転モード中だった場合は終了
			if _is_rotation_mode:
				_end_rotation_mode()
				get_viewport().set_input_as_handled()
				return
			_rotation_target_character = null
			_long_press_timer = 0.0
			_hide_progress_ring()
			# パス先端継続中だった場合、PathDrawerに描画終了を通知してモード終了
			if _path_endpoint_extension_started:
				print("[PointDebug] path_mode mouse release: confirming path (ext_started=true)")
				var drawer = _get_path_drawer()
				if drawer:
					drawer._handle_drawing_release()
				game_manager.confirm_path()
			# 即座パスモードのフラグをリセット
			_immediate_path_mode_started = false
			_immediate_path_drawing_started = false
			# パス先端延長フラグもリセット
			_path_endpoint_extension_pending = false
			_path_endpoint_extension_started = false
			# PathDrawerにリリースイベントを渡す
			var path_drawer = _get_path_drawer()
			if path_drawer:
				# ポイントモード中（Visionポイント等）の場合はポイント用リリース処理
				if path_drawer.is_point_mode():
					path_drawer.handle_point_release(event.position)
				else:
					path_drawer.handle_movement_release(event.position)
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
			_long_press_timer = 0.0
			var clicked = game_manager.raycast_character(event.position)
			if clicked:
				# 味方キャラクターなら選択（パスモードはドラッグ時に開始）
				if not PlayerState.is_enemy(clicked):
					if not (game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)):
						# 長押し回転用にキャラクターを記録
						_rotation_target_character = clicked
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
				# PathDrawerにプレスイベントを渡す（長押しVisionポイント用）
				var path_drawer = _get_path_drawer()
				var longpress_started = false
				if path_drawer:
					longpress_started = path_drawer.handle_movement_press(event.position)
				# 長押し待機を開始した場合
				if longpress_started:
					# パス延長待機をキャンセル（モーション時にconfirm_pathが呼ばれないように）
					_path_endpoint_extension_pending = false
				else:
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
			print("[PointDebug] non-path_mode mouse press: is_path_mode=%s" % str(game_manager.is_path_mode()))
			_left_button_pressed = true
			_left_click_start_pos = event.position
			_long_press_timer = 0.0

			# キャラクターがクリックされたか確認して、長押し回転用に記録
			var clicked = game_manager.raycast_character(event.position)
			if clicked and not PlayerState.is_enemy(clicked):
				_rotation_target_character = clicked
			else:
				_rotation_target_character = null

			# キャラクターなら即座にパスモード開始（描画はドラッグ時に開始）
			if _try_start_immediate_path_mode(event.position):
				_immediate_path_mode_started = true
				_immediate_path_drawing_started = false
				get_viewport().set_input_as_handled()
				return

			# 確認済みパス上の長押しを検出
			if _try_start_confirmed_path_longpress(event.position):
				get_viewport().set_input_as_handled()
				return

			# パス先端近くをタップした場合、ドラッグ開始待機状態にする
			_path_endpoint_extension_pending = true
			_path_endpoint_extension_started = false
		else:
			_left_button_pressed = false
			# 回転モード中だった場合は終了
			if _is_rotation_mode:
				_end_rotation_mode()
				return
			# 移動中パスVision描画中だった場合、ポイントを確定
			if _moving_path_vision_drawing:
				_finish_moving_path_vision_point(event.position)
				return
			# 確認済みパス長押し待機中だった場合（タップ判定）
			if _confirmed_path_longpress_pending:
				# 長押しにならなかった = タップ → コンテキストメニュー表示
				_show_path_context_menu_for_confirmed_path()
				_reset_confirmed_path_longpress()
				return
			# 移動中パス長押し待機中だった場合（タップ判定）
			if _moving_path_longpress_pending:
				# 長押しにならなかった = タップ → コンテキストメニュー表示
				_show_path_context_menu_for_moving_path()
				_reset_moving_path_longpress()
				return
			_rotation_target_character = null
			_long_press_timer = 0.0
			_hide_progress_ring()
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
				# PathDrawerに描画終了を通知してモード終了
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer._handle_drawing_release()
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
		var current_frame = Engine.get_process_frames()
		var just_ended = (current_frame == _path_mode_ended_frame)
		print("[PointDebug] non-path_mode drag: frame=%d, ended_frame=%d, just_ended=%s, ext_pending=%s" % [
			current_frame, _path_mode_ended_frame, str(just_ended), str(_path_endpoint_extension_pending)
		])
		# 回転モード中のドラッグ処理
		if _is_rotation_mode:
			_process_rotation_drag(event.position)
			get_viewport().set_input_as_handled()
			return

		# 移動中パスVision描画中のプレビュー更新
		if _moving_path_vision_drawing:
			_update_moving_path_vision_preview(event.position)
			get_viewport().set_input_as_handled()
			return

		# 確認済みパス長押し待機中にドラッグが検出された場合、キャンセルしてカメラパンへ
		if _confirmed_path_longpress_pending:
			var move_dist = event.position.distance_to(_confirmed_path_longpress_screen_pos)
			if move_dist > 20.0:
				_reset_confirmed_path_longpress()
				if camera_pan_controller:
					camera_pan_controller.start_potential_drag(_left_click_start_pos)

		# 移動中パス長押し待機中にドラッグが検出された場合
		if _moving_path_longpress_pending:
			var move_dist = event.position.distance_to(_moving_path_longpress_screen_pos)
			if move_dist > 20.0:
				# エンドポイント（path_ratio == 1.0）の場合はパス延長を試みる
				var path_ratio: float = _moving_path_longpress_data.get("path_ratio", 0.0)
				if path_ratio >= 0.99:  # 1.0（終点）付近
					print("[PointDebug] non-path_mode: longpress cancelled, trying path extension (mouse)")
					_reset_moving_path_longpress()
					if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
						_path_endpoint_extension_started = true
						print("[PointDebug] non-path_mode: ext_started=true (from longpress cancel mouse)")
						var path_drawer = _get_path_drawer()
						if path_drawer:
							path_drawer.handle_drawing_press(_left_click_start_pos)
						return
				# エンドポイント以外または延長失敗時はカメラパンへ
				_reset_moving_path_longpress()
				if camera_pan_controller:
					camera_pan_controller.start_potential_drag(_left_click_start_pos)

		# 即座パスモードでドラッグが検出された場合、パスモード開始
		if _immediate_path_mode_started and not _immediate_path_drawing_started:
			# 回転長押しをキャンセル（パス描画が優先）
			_rotation_target_character = null
			_long_press_timer = 0.0
			_hide_progress_ring()
			game_manager.start_move_mode()
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
			_immediate_path_drawing_started = true
			return
		# パス先端延長の待機中にドラッグが開始された場合
		# ただし、パスモード終了直後（同一フレーム）は禁止
		if _path_endpoint_extension_pending and not _path_endpoint_extension_started and not just_ended:
			print("[PointDebug] non-path_mode: trying path extension from pending (mouse drag)")
			if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
				_path_endpoint_extension_started = true
				_path_endpoint_extension_pending = false
				print("[PointDebug] non-path_mode: ext_started=true (mouse drag)")
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
		var path_drawer = _get_path_drawer()

		# ポイントモード中（Vision, Wait等）はPathDrawerに直接イベントを渡す
		if path_drawer and path_drawer.is_point_mode():
			if path_drawer.handle_point_touch_input(event):
				get_viewport().set_input_as_handled()
				return

		# 回転モード中のドラッグ処理（タッチ）
		if event is InputEventScreenDrag and _is_rotation_mode:
			_process_rotation_drag(event.position)
			get_viewport().set_input_as_handled()
			return

		# 即座パスモードでまだ描画開始していない場合のドラッグ検出
		if event is InputEventScreenDrag and _immediate_path_mode_started and not _immediate_path_drawing_started:
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
				_immediate_path_drawing_started = true
			# PathDrawerにドラッグイベントを伝播させる
			return

		# パス先端延長の待機中にドラッグが開始された場合
		if event is InputEventScreenDrag and _path_endpoint_extension_pending and not _path_endpoint_extension_started:
			# 現在のパスを確定してからパス延長を試みる
			print("[PointDebug] path_mode: starting path extension from pending (touch drag)")
			game_manager.confirm_path()
			if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
				_path_endpoint_extension_started = true
				_path_endpoint_extension_pending = false
				print("[PointDebug] path_mode: ext_started=true (from touch drag)")
				# パス延長開始時、PathDrawerに描画開始を通知
				if path_drawer:
					path_drawer.handle_drawing_press(_left_click_start_pos)
				return
			else:
				_path_endpoint_extension_pending = false

		# パス先端延長モードでドラッグ中の場合、PathDrawerにイベントを渡す
		if event is InputEventScreenDrag and _path_endpoint_extension_started:
			if path_drawer:
				path_drawer._handle_movement_input(event)
				get_viewport().set_input_as_handled()
			return

		# タッチ終了時：カメラパン状態をクリア
		if event is InputEventScreenTouch and not event.pressed:
			_left_button_pressed = false
			# 回転モード中だった場合は終了
			if _is_rotation_mode:
				_end_rotation_mode()
				get_viewport().set_input_as_handled()
				return
			_rotation_target_character = null
			_long_press_timer = 0.0
			_hide_progress_ring()
			# パス先端継続中だった場合、PathDrawerに描画終了を通知してモード終了
			if _path_endpoint_extension_started:
				if path_drawer:
					path_drawer._handle_drawing_release()
				game_manager.confirm_path()
			# 即座パスモードのフラグをリセット
			_immediate_path_mode_started = false
			_immediate_path_drawing_started = false
			# パス先端延長フラグもリセット
			_path_endpoint_extension_pending = false
			_path_endpoint_extension_started = false
			# PathDrawerにリリースイベントを渡す
			if path_drawer:
				# ポイントモード中（Visionポイント等）の場合はポイント用リリース処理
				if path_drawer.is_point_mode():
					path_drawer.handle_point_release(event.position)
			if camera_pan_controller.is_touch_panning():
				camera_pan_controller.end_touch_pan()
			elif camera_pan_controller.is_pending_touch_pan():
				camera_pan_controller.cancel_potential_touch_pan()
			# PathDrawerにも伝播させる
			return
		# タッチ開始時：キャラクタータップ
		if event is InputEventScreenTouch and event.pressed:
			_left_button_pressed = true
			_left_click_start_pos = event.position
			_long_press_timer = 0.0
			var clicked = game_manager.raycast_character(event.position)
			if clicked:
				# 味方キャラクターなら選択（パスモードはドラッグ時に開始）
				if not PlayerState.is_enemy(clicked):
					if not (game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)):
						# 長押し回転用にキャラクターを記録
						_rotation_target_character = clicked
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
			_left_button_pressed = true
			_left_click_start_pos = event.position
			_long_press_timer = 0.0
			# _path_mode_just_ended は _process でリセット（同一フレーム内のイベントを防ぐため）

			# キャラクターがタッチされたか確認して、長押し回転用に記録
			var clicked = game_manager.raycast_character(event.position)
			if clicked and not PlayerState.is_enemy(clicked):
				_rotation_target_character = clicked
			else:
				_rotation_target_character = null

			# パス未設定キャラクターなら即座にパスモード開始（描画はドラッグ時に開始）
			if _try_start_immediate_path_mode(event.position):
				_immediate_path_mode_started = true
				_immediate_path_drawing_started = false
				get_viewport().set_input_as_handled()
				return

			# 確認済みパス上の長押しを検出
			if _try_start_confirmed_path_longpress(event.position):
				get_viewport().set_input_as_handled()
				return

			# パス先端近くをタップした場合、ドラッグ開始待機状態にする
			_path_endpoint_extension_pending = true
			_path_endpoint_extension_started = false
		else:
			_left_button_pressed = false
			# 回転モード中だった場合は終了
			if _is_rotation_mode:
				_end_rotation_mode()
				get_viewport().set_input_as_handled()
				return
			# 移動中パスVision描画中だった場合、ポイントを確定
			if _moving_path_vision_drawing:
				_finish_moving_path_vision_point(event.position)
				get_viewport().set_input_as_handled()
				return
			# 確認済みパス長押し待機中だった場合（タップ判定）
			if _confirmed_path_longpress_pending:
				# 長押しにならなかった = タップ → コンテキストメニュー表示
				_show_path_context_menu_for_confirmed_path()
				_reset_confirmed_path_longpress()
				get_viewport().set_input_as_handled()
				return
			# 移動中パス長押し待機中だった場合（タップ判定）
			if _moving_path_longpress_pending:
				# 長押しにならなかった = タップ → コンテキストメニュー表示
				_show_path_context_menu_for_moving_path()
				_reset_moving_path_longpress()
				get_viewport().set_input_as_handled()
				return
			_rotation_target_character = null
			_long_press_timer = 0.0
			_hide_progress_ring()
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
			# パス先端継続モードが開始された場合はタップ処理をスキップ
			if _path_endpoint_extension_started:
				var path_drawer = _get_path_drawer()
				if path_drawer:
					path_drawer._handle_drawing_release()
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
		# 回転モード中のドラッグ処理（タッチ）
		if _is_rotation_mode:
			_process_rotation_drag(event.position)
			get_viewport().set_input_as_handled()
			return

		# 移動中パスVision描画中のプレビュー更新
		if _moving_path_vision_drawing:
			_update_moving_path_vision_preview(event.position)
			get_viewport().set_input_as_handled()
			return

		# 確認済みパス長押し待機中にドラッグが検出された場合、キャンセルしてカメラパンへ
		if _confirmed_path_longpress_pending:
			var move_dist = event.position.distance_to(_confirmed_path_longpress_screen_pos)
			if move_dist > 20.0:
				_reset_confirmed_path_longpress()
				camera_pan_controller.start_potential_touch_pan(_left_click_start_pos)

		# 移動中パス長押し待機中にドラッグが検出された場合
		if _moving_path_longpress_pending:
			var move_dist = event.position.distance_to(_moving_path_longpress_screen_pos)
			if move_dist > 20.0:
				# エンドポイント（path_ratio == 1.0）の場合はパス延長を試みる
				var path_ratio: float = _moving_path_longpress_data.get("path_ratio", 0.0)
				if path_ratio >= 0.99:  # 1.0（終点）付近
					print("[PointDebug] non-path_mode: longpress cancelled, trying path extension (touch)")
					_reset_moving_path_longpress()
					if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
						_path_endpoint_extension_started = true
						print("[PointDebug] non-path_mode: ext_started=true (from longpress cancel touch)")
						var path_drawer = _get_path_drawer()
						if path_drawer:
							path_drawer.handle_drawing_press(_left_click_start_pos)
						return
				# エンドポイント以外または延長失敗時はカメラパンへ
				_reset_moving_path_longpress()
				camera_pan_controller.start_potential_touch_pan(_left_click_start_pos)

		# 即座パスモードでドラッグが検出された場合、パスモード開始
		if _immediate_path_mode_started and not _immediate_path_drawing_started:
			# 回転長押しをキャンセル（パス描画が優先）
			_rotation_target_character = null
			_long_press_timer = 0.0
			_hide_progress_ring()
			game_manager.start_move_mode()
			var path_drawer = _get_path_drawer()
			if path_drawer:
				path_drawer.handle_drawing_press(_left_click_start_pos)
			_immediate_path_drawing_started = true
			return
		# パス先端延長の待機中にドラッグが開始された場合
		# ただし、パスモード終了直後（同一フレーム）は禁止
		var just_ended_touch = (Engine.get_process_frames() == _path_mode_ended_frame)
		if _path_endpoint_extension_pending and not _path_endpoint_extension_started and not just_ended_touch:
			print("[PointDebug] non-path_mode: trying path extension from pending (touch drag)")
			if _try_start_path_continuation_from_endpoint(_left_click_start_pos):
				_path_endpoint_extension_started = true
				_path_endpoint_extension_pending = false
				print("[PointDebug] non-path_mode: ext_started=true (touch drag)")
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
	var result := game_manager.path_execution_manager.find_path_endpoint_at_position(ground_pos, 1.2)
	return not result.is_empty()


## 確認済みパスまたは移動中パス上かをチェックし、長押し待機を開始
## @return: 長押し待機を開始した場合true
func _try_start_confirmed_path_longpress(screen_pos: Vector2) -> bool:
	print("[PointDebug] _try_start_confirmed_path_longpress: called")
	if not game_manager or not game_manager.path_execution_manager or not game_manager.camera:
		print("[PointDebug] _try_start_confirmed_path_longpress: no manager")
		return false

	# パスモード中は処理しない（PathDrawerが処理する）
	if game_manager.is_path_mode():
		print("[PointDebug] _try_start_confirmed_path_longpress: is_path_mode=true, skipping")
		return false

	# 地面位置を取得
	var ground_plane := Plane(Vector3.UP, 0.0)
	var ray_origin := game_manager.camera.project_ray_origin(screen_pos)
	var ray_dir := game_manager.camera.project_ray_normal(screen_pos)
	var intersect = ground_plane.intersects_ray(ray_origin, ray_dir)
	if not intersect:
		return false

	var ground_pos: Vector3 = intersect as Vector3
	print("[PointDebug] _try_start_confirmed_path_longpress: ground_pos=%s" % [ground_pos])

	# 確認済みパス上かチェック（先端は除外 - 先端はパス延長用）
	var result := game_manager.path_execution_manager.find_path_point_at_position(ground_pos, 1.2)
	print("[PointDebug] _try_start_confirmed_path_longpress: find_path_point result=%s" % [result])
	if not result.is_empty():
		print("[PointDebug] _try_start_confirmed_path_longpress: starting longpress for confirmed path")
		# 長押し待機を開始（確認済みパス）
		_confirmed_path_longpress_pending = true
		_confirmed_path_longpress_timer = 0.0
		_confirmed_path_longpress_screen_pos = screen_pos
		_confirmed_path_longpress_ground_pos = ground_pos
		_confirmed_path_tap_path_data = result  # コンテキストメニュー用に保存
		return true

	# 移動中パス上かチェック（先端は除外 - 先端はパス延長用）
	var moving_result := game_manager.try_start_vision_point_on_moving_path(screen_pos, ground_pos)
	print("[PointDebug] _try_start_confirmed_path_longpress: moving_result=%s" % [moving_result])
	if not moving_result.is_empty():
		print("[PointDebug] _try_start_confirmed_path_longpress: starting longpress for moving path")
		# 長押し待機を開始（移動中パス）
		_moving_path_longpress_pending = true
		_moving_path_longpress_timer = 0.0
		_moving_path_longpress_screen_pos = screen_pos
		_moving_path_longpress_data = moving_result
		_moving_path_tap_path_data = moving_result  # コンテキストメニュー用に保存
		return true

	print("[PointDebug] _try_start_confirmed_path_longpress: no path found, returning false")
	return false


## 確認済みパス上でVisionモードを開始
func _start_vision_mode_on_confirmed_path() -> void:
	_confirmed_path_longpress_pending = false
	_confirmed_path_longpress_timer = 0.0

	print("[PointDebug] _start_vision_mode_on_confirmed_path: attempting")
	if game_manager.try_start_vision_point_on_confirmed_path(
		_confirmed_path_longpress_screen_pos,
		_confirmed_path_longpress_ground_pos
	):
		print("[PointDebug] _start_vision_mode_on_confirmed_path: success")
		# 成功した場合、他の状態をクリア
		_path_endpoint_extension_pending = false
		_path_endpoint_extension_started = false
	else:
		print("[PointDebug] _start_vision_mode_on_confirmed_path: failed")


## 確認済みパス長押し状態をリセット
func _reset_confirmed_path_longpress() -> void:
	_confirmed_path_longpress_pending = false
	_confirmed_path_longpress_timer = 0.0
	_confirmed_path_longpress_screen_pos = Vector2.ZERO
	_confirmed_path_longpress_ground_pos = Vector3.ZERO
	_confirmed_path_tap_path_data = {}
	_hide_progress_ring()


## 確認済みパス上タップ時にコンテキストメニューを表示
func _show_path_context_menu_for_confirmed_path() -> void:
	if _confirmed_path_tap_path_data.is_empty():
		return
	if not game_manager:
		return

	game_manager.show_path_context_menu(
		_confirmed_path_longpress_screen_pos,
		_confirmed_path_tap_path_data
	)


## 移動中パス上でVisionモードを開始
func _start_vision_mode_on_moving_path() -> void:
	_moving_path_longpress_pending = false
	_moving_path_longpress_timer = 0.0

	if _moving_path_longpress_data.is_empty():
		print("[PointDebug] _start_vision_mode_on_moving_path: no data")
		return

	print("[PointDebug] _start_vision_mode_on_moving_path: started, ratio=%.3f" % _moving_path_longpress_data.get("path_ratio", 0.0))
	# 移動中パスへのVision描画モードを開始
	_moving_path_vision_drawing = true


## 移動中パスへのVisionポイント配置を完了
func _finish_moving_path_vision_point(screen_pos: Vector2) -> void:
	if not _moving_path_vision_drawing or _moving_path_longpress_data.is_empty():
		print("[PointDebug] _finish_moving_path_vision_point: not drawing or no data")
		_reset_moving_path_longpress()
		return

	# 地面位置を取得
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

	# 視線方向が短すぎる場合はキャンセル
	var direction = target_point - anchor
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		print("[PointDebug] _finish_moving_path_vision_point: direction too short")
		_reset_moving_path_longpress()
		return

	print("[PointDebug] _finish_moving_path_vision_point: adding point, ratio=%.3f, char_valid=%s" % [
		path_ratio, str(is_instance_valid(character))
	])
	# 移動中パスにVisionポイントを追加
	game_manager.add_vision_point_to_moving_path(character, path_ratio, anchor, target_point)

	_reset_moving_path_longpress()


## 移動中パスVisionポイントのプレビューを更新
func _update_moving_path_vision_preview(screen_pos: Vector2) -> void:
	if _moving_path_longpress_data.is_empty():
		return

	# 地面位置を取得
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

	# プレビューを更新（path_ratioも渡す）
	game_manager.update_moving_path_vision_preview(character, anchor, target_point, path_ratio)


## 移動中パス長押し状態をリセット
func _reset_moving_path_longpress() -> void:
	_moving_path_longpress_pending = false
	_moving_path_longpress_timer = 0.0
	_moving_path_longpress_screen_pos = Vector2.ZERO
	_moving_path_longpress_data = {}
	_moving_path_vision_drawing = false
	_moving_path_tap_path_data = {}
	_hide_progress_ring()
	# プレビューをクリア
	if game_manager:
		game_manager.clear_moving_path_vision_preview()


## 移動中パス上タップ時にコンテキストメニューを表示
func _show_path_context_menu_for_moving_path() -> void:
	if _moving_path_tap_path_data.is_empty():
		return
	if not game_manager:
		return

	game_manager.show_path_context_menu(
		_moving_path_longpress_screen_pos,
		_moving_path_tap_path_data
	)


## パスモード終了時のハンドラ（フラグをリセット）
func _on_path_mode_ended() -> void:
	var current_frame = Engine.get_process_frames()
	print("[PointDebug] _on_path_mode_ended: frame=%d, resetting flags" % current_frame)
	_path_endpoint_extension_pending = false
	_path_endpoint_extension_started = false
	_immediate_path_mode_started = false
	_immediate_path_drawing_started = false
	_left_button_pressed = false
	_rotation_target_character = null
	_long_press_timer = 0.0
	_hide_progress_ring()
	# パスモード終了したフレームを記録（同一フレーム内のパス延長を禁止）
	_path_mode_ended_frame = current_frame


## パス先端近くでドラッグが検出された際のハンドラ（パス延長を開始）
func _on_endpoint_drag_detected(screen_pos: Vector2) -> void:
	print("[PointDebug] _on_endpoint_drag_detected: screen_pos=%s" % str(screen_pos))
	# パスモード中のみ処理
	if not game_manager.is_path_mode():
		return

	# 現在のパスを確定してからパス延長を開始
	game_manager.confirm_path()
	if _try_start_path_continuation_from_endpoint(screen_pos):
		_path_endpoint_extension_started = true
		_path_endpoint_extension_pending = false
		var path_drawer = _get_path_drawer()
		if path_drawer:
			path_drawer.handle_drawing_press(screen_pos)
		print("[PointDebug] _on_endpoint_drag_detected: path continuation started")
