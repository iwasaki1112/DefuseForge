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


## タップダウン時にパス未設定キャラクターを即座に選択してパスモード開始
## @return: パスモードが開始された場合true
func _try_start_immediate_path_mode(screen_pos: Vector2) -> bool:
	var clicked = game_manager.raycast_character(screen_pos)
	if not clicked:
		return false
	if PlayerState.is_enemy(clicked):
		return false
	if game_manager.path_service and game_manager.path_service.is_character_following_path(clicked):
		return false
	if not _is_character_without_path(clicked):
		return false

	game_manager.selection_manager.deselect_all()
	game_manager.selection_manager.add_to_selection(clicked)
	game_manager.start_move_mode()
	return true


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
	# Macトラックパッドジェスチャー（ピンチズーム、2本指パン）
	# 微小なジェスチャーは無視（クリック時のノイズ対策）
	# ========================================
	if event is InputEventMagnifyGesture:
		# factor が 1.0 から十分離れている場合のみ処理
		if absf(event.factor - 1.0) > 0.01 and camera_pan_controller:
			camera_pan_controller.handle_magnify_gesture(event.factor)
			get_viewport().set_input_as_handled()
			return
		# 微小な場合は無視して次の処理へ（returnしない）

	if event is InputEventPanGesture:
		# すべてのパンジェスチャーをそのまま処理
		if camera_pan_controller:
			camera_pan_controller.handle_pan_gesture(event.delta)
			get_viewport().set_input_as_handled()
		return

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

		# マウスボタンリリース時：カメラドラッグ状態をクリア
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_left_button_pressed = false
			# 即座パスモードのフラグをリセット
			_immediate_path_mode_started = false
			_immediate_path_drawing_started = false
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
				# パス未設定キャラクターなら即座パスモード開始（キャラクター切り替え）
				if _is_character_without_path(clicked) and not PlayerState.is_enemy(clicked):
					if not (game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)):
						# 現在のパスを確定してから切り替え
						game_manager.confirm_path()
						game_manager.selection_manager.deselect_all()
						game_manager.selection_manager.add_to_selection(clicked)
						game_manager.start_move_mode()
						_immediate_path_mode_started = true
						_immediate_path_drawing_started = false
						get_viewport().set_input_as_handled()
						return
				# それ以外はGameManagerに委譲
				game_manager.handle_click(event.position, MOUSE_BUTTON_LEFT)
				get_viewport().set_input_as_handled()
				return
		# それ以外はPathDrawerに委譲
		return

	# ========================================
	# 左クリック処理（PC向け・非パスモード）
	# 1本指はタップのみ、カメラパンは2本指ジェスチャーで行う
	# ========================================
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_button_pressed = true
			_left_click_start_pos = event.position

			# パス未設定キャラクターなら即座にパスモード開始（描画はドラッグ時に開始）
			if _try_start_immediate_path_mode(event.position):
				_immediate_path_mode_started = true
				_immediate_path_drawing_started = false
				get_viewport().set_input_as_handled()
				return
		else:
			_left_button_pressed = false
			# 即座にパスモードを開始した場合はタップ処理をスキップ
			# （パスモードに入った状態で、その後のドラッグでパスを描ける）
			if _immediate_path_mode_started:
				_immediate_path_mode_started = false
				_immediate_path_drawing_started = false
				return
			# タップ判定（ドラッグ距離が閾値以下ならタップ）
			var distance = _left_click_start_pos.distance_to(event.position)
			if distance < 50.0:  # トラックパッドのクリックブレを考慮して閾値を大きめに
				_handle_tap(event.position)
		return

	# 1本指マウスドラッグは無視（PathDrawerに委譲させる or 2本指ジェスチャーでカメラ操作）
	# パスモード以外での1本指ドラッグは何もしない
	if event is InputEventMouseMotion and _left_button_pressed:
		# 非パスモードでは1本指ドラッグを無視（カメラパンしない）
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

		# タッチ終了時：カメラパン状態をクリア
		if event is InputEventScreenTouch and not event.pressed:
			# 即座パスモードのフラグをリセット
			_immediate_path_mode_started = false
			_immediate_path_drawing_started = false
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
				# パス未設定キャラクターなら即座パスモード開始（キャラクター切り替え）
				if _is_character_without_path(clicked) and not PlayerState.is_enemy(clicked):
					if not (game_manager.path_service and game_manager.path_service.is_character_following_path(clicked)):
						# 現在のパスを確定してから切り替え
						game_manager.confirm_path()
						game_manager.selection_manager.deselect_all()
						game_manager.selection_manager.add_to_selection(clicked)
						game_manager.start_move_mode()
						_immediate_path_mode_started = true
						_immediate_path_drawing_started = false
						get_viewport().set_input_as_handled()
						return
				# それ以外はGameManagerに委譲
				game_manager.handle_click(event.position, MOUSE_BUTTON_LEFT)
				get_viewport().set_input_as_handled()
				return
		# それ以外はPathDrawerに委譲
		return

	# 1本指タッチ（非パスモード）- タップのみ、パンは2本指で行う
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
		else:
			# 即座にパスモードを開始した場合はタップ処理をスキップ
			# （パスモードに入った状態で、その後のドラッグでパスを描ける）
			if _immediate_path_mode_started:
				_immediate_path_mode_started = false
				_immediate_path_drawing_started = false
				get_viewport().set_input_as_handled()
				return
			# タッチ終了：タップ判定
			var distance = _left_click_start_pos.distance_to(event.position)
			if distance < 20.0:  # タップ判定閾値
				_handle_tap(event.position)
			get_viewport().set_input_as_handled()
		return

	# 1本指ドラッグは非パスモードでは無視（2本指パンのみ許可）
	if event is InputEventScreenDrag:
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
