class_name PathDrawer
extends Node3D

## 地面にパスを描画するコンポーネント
## マウスドラッグでパスを描き、キャラクター移動に使用
## ポイント処理は各ハンドラに委譲

## 描画モード
enum DrawingMode { MOVEMENT, VISION_POINT, WAIT_POINT }

## ポイント履歴用の種別
enum PointType { VISION, PATH, WAIT }

#region シグナル
signal drawing_finished(points: PackedVector3Array)
signal vision_point_added(anchor: Vector3, target_point: Vector3)
signal wait_point_added(path_ratio: float, wait_duration: float)
signal path_undone()
signal mode_changed(mode: int)
## パス外タップ時のシグナル（モード終了用）
signal off_path_tapped()
## 自動確定リクエスト（確認済みパスへのVisionポイント配置後など）
signal auto_confirm_requested()
## パス上タップ時のシグナル（コンテキストメニュー表示用）
signal path_tapped(screen_pos: Vector2, path_data: Dictionary)
## パスポイント追加シグナル（リアルタイム確定用 - ポイント追加のたびに発火）
signal path_point_added(character: Node, point: Vector3)
## パス描画開始シグナル（新規パス開始時に発火）
signal path_started(character: Node, start_point: Vector3)
#endregion

#region エクスポート設定
@export var min_point_distance: float = 0.2
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var vision_line_color: Color = Color(0.7, 0.3, 0.9, 0.9)
@export var vision_line_length: float = 2.0
@export var line_width: float = 0.04
@export var ground_plane_height: float = 0.0
@export var max_points: int = 500
@export var path_click_threshold: float = 1.2
@export var path_endpoint_threshold: float = 0.3
@export_flags_3d_physics var wall_collision_mask: int = 2
@export var enable_wall_sliding: bool = true
@export var wall_slide_offset: float = 0.5  ## 壁からの距離
@export var enable_smoothing: bool = false
@export var smoothing_epsilon: float = 0.15
@export var smoothing_segments: int = 4
#endregion

#region 定数
const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")
const ActionPointDataScript = preload("res://scripts/effects/action_point_data.gd")
#endregion

#region 内部変数
var _camera: Camera3D
var _character: Node3D
var _ground_plane: Plane
var _is_drawing: bool = false
var _is_enabled: bool = false
var _drawing_mode: DrawingMode = DrawingMode.MOVEMENT
## 現在描画中のパスポイント（リアルタイムで確定済み）
var _path_points: PackedVector3Array = PackedVector3Array()
var _path_mesh: MeshInstance3D

var _character_color: Color = Color(1.0, 1.0, 1.0)

var _point_history: Array[int] = []
var _active_edit_character: Node = null

## 壁沿いモード状態
var _is_wall_sliding: bool = false           ## 壁沿いモード中か
var _wall_slide_normal: Vector3 = Vector3.ZERO  ## 壁の法線
var _wall_slide_direction: Vector3 = Vector3.ZERO  ## スライド方向

## 最後のタッチ時刻（エミュレートマウスイベント対策）
var _last_touch_time: int = 0

## タッチイベントとマウスイベントの間隔閾値（ミリ秒）
const TOUCH_MOUSE_INTERVAL_MS: int = 100

## パス上長押しでVisionポイント配置用
var _path_longpress_pending: bool = false  ## 長押し待機中か
var _path_longpress_timer: float = 0.0     ## 長押しタイマー
var _path_longpress_threshold: float = 0.5  ## 長押し閾値（秒）
var _path_longpress_screen_pos: Vector2 = Vector2.ZERO  ## 長押し開始位置
var _path_longpress_ground_pos: Vector3 = Vector3.ZERO  ## 長押し開始のグラウンド位置
var _longpress_vision_mode: bool = false  ## 長押しからVisionモードに入ったか
var _auto_confirm_after_vision: bool = false  ## Visionポイント配置後に自動確定するか

## ポイントハンドラ
var _vision_handler: VisionPointHandler
var _wait_handler: WaitPointHandler

## 実行中のキャラクター（パス完了シグナル接続用）
var _executing_character: Node = null
#endregion


func _ready() -> void:
	_ground_plane = Plane(Vector3.UP, ground_plane_height)
	_setup_mesh()
	_setup_handlers()


func _process(delta: float) -> void:
	if _wait_handler and _wait_handler.is_pressing():
		_wait_handler.update_preview()

	# パス上長押し検出（1フレーム遅延させて入力イベント処理を優先）
	if _path_longpress_pending:
		if _path_longpress_timer >= _path_longpress_threshold:
			_start_vision_mode_from_longpress()
		else:
			_path_longpress_timer += delta


func _setup_mesh() -> void:
	_path_mesh = MeshInstance3D.new()
	_path_mesh.set_script(PathLineMeshScript)
	_path_mesh.line_color = line_color
	_path_mesh.line_width = line_width
	add_child(_path_mesh)


func _setup_handlers() -> void:
	_vision_handler = VisionPointHandler.new()
	_wait_handler = WaitPointHandler.new()

	# ハンドラのシグナル接続
	_vision_handler.point_added.connect(_on_vision_point_added)
	_wait_handler.point_added.connect(_on_wait_point_added)


func _setup_handlers_with_camera() -> void:
	var handlers = _get_all_handlers()
	for handler in handlers:
		handler.setup(self, _camera)
		handler.set_character_color(_character_color)


func _get_all_handlers() -> Array:
	return [_vision_handler, _wait_handler]


func _get_handler_for_mode(mode: DrawingMode):
	match mode:
		DrawingMode.VISION_POINT:
			return _vision_handler
		DrawingMode.WAIT_POINT:
			return _wait_handler
		_:
			return null


#region シグナルハンドラ
func _on_vision_point_added(data: Dictionary) -> void:
	_point_history.append(PointType.VISION)
	vision_point_added.emit(data.get("anchor", Vector3.ZERO), data.get("target_point", Vector3.ZERO))

	# 長押しからVisionモードに入った場合、ポイント配置後にMOVEMENTモードに戻る
	if _longpress_vision_mode:
		_longpress_vision_mode = false
		_drawing_mode = DrawingMode.MOVEMENT
		mode_changed.emit(int(DrawingMode.MOVEMENT))

	# 自動確定フラグが立っている場合（確認済みパスからの長押し）は確定をリクエスト
	# _longpress_vision_modeとは独立してチェック（_unhandled_inputで先にリセットされる場合があるため）
	if _auto_confirm_after_vision:
		_auto_confirm_after_vision = false
		_drawing_mode = DrawingMode.MOVEMENT
		mode_changed.emit(int(DrawingMode.MOVEMENT))
		auto_confirm_requested.emit()


func _on_wait_point_added(data: Dictionary) -> void:
	_point_history.append(PointType.WAIT)
	wait_point_added.emit(data.get("path_ratio", 0.0), data.get("wait_duration", 0.0))
#endregion


#region セットアップ API
func setup(camera: Camera3D, character: Node3D = null) -> void:
	_camera = camera
	_character = character
	_setup_handlers_with_camera()


func enable(character: Node3D) -> void:
	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	clear()


## 指定した開始点からパス描画を開始
## @param character: 対象キャラクター
## @param start_point: パス開始点
func enable_from_point(character: Node3D, start_point: Vector3) -> void:
	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	clear()

	# 開始点を設定（パス開始シグナルも発火）
	_path_points.append(start_point)
	if _path_mesh:
		_path_mesh.update_from_points(_path_points)
	path_started.emit(_character, start_point)


func disable() -> void:
	_is_enabled = false
	_is_drawing = false


func is_enabled() -> bool:
	return _is_enabled


func set_character_color(color: Color) -> void:
	_character_color = color
	set_line_color(Color(color.r, color.g, color.b, 0.9))
	for handler in _get_all_handlers():
		handler.set_character_color(color)


func set_line_color(color: Color) -> void:
	line_color = color
	if _path_mesh:
		_path_mesh.set_line_color(color)


func set_active_edit_character(character: Node) -> void:
	_active_edit_character = character
	if character:
		var char_color = CharacterColorManager.get_character_color(character)
		set_character_color(char_color)


func get_active_edit_character() -> Node:
	return _active_edit_character
#endregion


#region 入力処理
func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or not _is_enabled:
		return

	match _drawing_mode:
		DrawingMode.MOVEMENT:
			_handle_movement_input(event)
		_:
			# ポイントモードはハンドラに委譲
			var handler = _get_handler_for_mode(_drawing_mode)
			if handler and handler.handle_input(event):
				get_viewport().set_input_as_handled()
				# 長押しVisionモードでリリース後、描画が終了したらMOVEMENTに戻る
				if _longpress_vision_mode and _drawing_mode == DrawingMode.VISION_POINT:
					if not _vision_handler._is_drawing:
						_longpress_vision_mode = false
						_drawing_mode = DrawingMode.MOVEMENT
						mode_changed.emit(int(DrawingMode.MOVEMENT))
			else:
				# ハンドラがイベントを処理しなかった場合、パス外タップをチェック
				_check_off_path_tap(event)


## パス外タップのチェック（ポイントモード用）
func _check_off_path_tap(event: InputEvent) -> void:
	var screen_pos: Vector2
	var is_press: bool = false

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			screen_pos = mouse_event.position
			is_press = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			screen_pos = event.position
			is_press = true

	if is_press:
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos != null and has_path():
			if not is_point_on_path(ground_pos) and not _is_near_path_endpoint(ground_pos):
				off_path_tapped.emit()
				get_viewport().set_input_as_handled()


func _handle_movement_input(event: InputEvent) -> void:
	# タッチ入力（優先処理）
	# タッチ入力
	if event is InputEventScreenTouch:
		_last_touch_time = Time.get_ticks_msec()
		if event.pressed:
			handle_movement_press(event.position)
		else:
			handle_movement_release(event.position)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		_handle_movement_motion(event.position)
		get_viewport().set_input_as_handled()
		return

	# マウス入力（タッチ直後のエミュレートイベントはスキップ）
	if Time.get_ticks_msec() - _last_touch_time < TOUCH_MOUSE_INTERVAL_MS:
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				handle_movement_press(mouse_event.position)
			else:
				handle_movement_release(mouse_event.position)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		_handle_movement_motion(event.position)


## 移動モードでのプレス処理（外部から呼び出し可能）
## @return: 長押し待機を開始した場合true（handle_clickをスキップすべき）
func handle_movement_press(screen_pos: Vector2) -> bool:
	# 既にプレス中の場合は無視（重複イベント対策）
	if _path_longpress_pending or _is_drawing:
		return true

	var ground_pos = _get_ground_position(screen_pos)

	# 既存パスがある場合、パス上の長押しをチェック
	if has_path() and ground_pos != null:
		var on_path = is_point_on_path(ground_pos)
		var near_endpoint = _is_near_path_endpoint(ground_pos)
		if on_path and not near_endpoint:
			# パス上での長押し待機を開始
			_path_longpress_pending = true
			_path_longpress_timer = 0.0
			_path_longpress_screen_pos = screen_pos
			_path_longpress_ground_pos = ground_pos
			return true  # handle_clickをスキップ
		# パス外をタップした場合は何もしない（handle_clickに任せる）
		return false

	# パスがない場合のみ、通常の描画開始
	_handle_drawing_press(screen_pos)
	return false


## 移動モードでのリリース処理（外部から呼び出し可能）
func handle_movement_release(_screen_pos: Vector2) -> void:
	# 長押し待機中だった場合はタップ判定 → コンテキストメニュー表示
	if _path_longpress_pending:
		var screen_pos := _path_longpress_screen_pos
		var ground_pos := _path_longpress_ground_pos
		_reset_path_longpress()
		# パス上タップをシグナル発火（コンテキストメニュー表示用）
		var result := _find_closest_point_on_path(ground_pos)
		if not result.is_empty():
			var path_data := {
				"point": result.point,
				"path_ratio": result.ratio,
				"character": _character
			}
			path_tapped.emit(screen_pos, path_data)
		return

	_handle_drawing_release()


## ポイントモードでのリリース処理（外部から呼び出し可能）
## Visionポイント等のドラッグリリース時に呼ばれる
func handle_point_release(screen_pos: Vector2) -> bool:
	# 長押し待機中だった場合はタップ判定 → コンテキストメニュー表示
	if _path_longpress_pending:
		var tap_screen_pos := _path_longpress_screen_pos
		var tap_ground_pos := _path_longpress_ground_pos
		_reset_path_longpress()
		# パス上タップをシグナル発火（コンテキストメニュー表示用）
		var result := _find_closest_point_on_path(tap_ground_pos)
		if not result.is_empty():
			var path_data := {
				"point": result.point,
				"path_ratio": result.ratio,
				"character": _character
			}
			path_tapped.emit(tap_screen_pos, path_data)
		return true

	if _drawing_mode == DrawingMode.MOVEMENT:
		return false

	var handler = _get_handler_for_mode(_drawing_mode)
	if handler:
		# VisionPointHandler等のリリース処理を呼ぶ
		var fake_event = InputEventMouseButton.new()
		fake_event.button_index = MOUSE_BUTTON_LEFT
		fake_event.pressed = false
		fake_event.position = screen_pos
		return handler.handle_input(fake_event)
	return false


## ポイントモードでのタッチ入力処理（外部から呼び出し可能）
## InputControllerからタッチイベントを直接受け取り、ハンドラに委譲する
func handle_point_touch_input(event: InputEvent) -> bool:
	if _drawing_mode == DrawingMode.MOVEMENT:
		return false

	var handler = _get_handler_for_mode(_drawing_mode)
	if handler and handler.handle_input(event):
		# 長押しVisionモードでリリース後、描画が終了したらMOVEMENTに戻る
		if _longpress_vision_mode and _drawing_mode == DrawingMode.VISION_POINT:
			if not _vision_handler._is_drawing:
				_longpress_vision_mode = false
				_drawing_mode = DrawingMode.MOVEMENT
				mode_changed.emit(int(DrawingMode.MOVEMENT))
		return true
	return false


## 移動モードでのモーション処理
func _handle_movement_motion(screen_pos: Vector2) -> void:
	# 長押し待機中の場合、移動が大きければキャンセルして描画開始
	if _path_longpress_pending:
		var move_dist = screen_pos.distance_to(_path_longpress_screen_pos)
		if move_dist > 20.0:  # 20ピクセル以上移動したらキャンセル
			_reset_path_longpress()
			_handle_drawing_press(_path_longpress_screen_pos)
			# すぐにポイントを追加
			var ground_pos = _get_ground_position(screen_pos)
			if ground_pos != null and _is_drawing:
				_add_point(ground_pos)
		return

	if _is_drawing:
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos != null:
			_add_point(ground_pos)


## 描画開始処理（マウス/タッチ共通）
func _handle_drawing_press(screen_pos: Vector2) -> void:
	# 既に描画中の場合は無視（重複イベント対策）
	if _is_drawing:
		return

	# 既にパスポイントがある場合（継続モードで終点から開始）、描画開始のみ行う
	# enable_from_point で1点追加されているので >= 1 でチェック
	if _path_points.size() >= 1:
		_is_drawing = true
		return

	var start_pos: Vector3
	if _character:
		start_pos = Vector3(_character.global_position.x, 0, _character.global_position.z)
	else:
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos == null:
			return
		start_pos = ground_pos
	_start_drawing(start_pos)


## 描画終了処理（マウス/タッチ共通）
func _handle_drawing_release() -> void:
	if _is_drawing:
		_finish_drawing()
	# Note: 描画が開始されていない場合（パスモード開始直後のリリース等）は何もしない
	# キャンセルはユーザーが明示的にESCキーなどで行う


## 描画開始処理（外部から呼び出し可能）
func handle_drawing_press(screen_pos: Vector2) -> void:
	_handle_drawing_press(screen_pos)
#endregion


#region パス描画
func _start_drawing(start_pos: Vector3) -> void:
	# パス描画開始時に長押し状態をリセット
	_reset_path_longpress()

	if _character:
		var char_pos = Vector3(_character.global_position.x, ground_plane_height, _character.global_position.z)
		var hit_result = _check_wall_between(char_pos, start_pos)
		if hit_result.hit:
			return

	_is_drawing = true
	_path_points.clear()
	_path_points.append(start_pos)
	_path_mesh.update_from_points(_path_points)

	# パス開始シグナルを発火（リアルタイム確定）
	path_started.emit(_character, start_pos)


func _add_point(pos: Vector3) -> void:
	if _path_points.size() >= max_points:
		_reset_wall_slide_state()
		return

	var last_point = _path_points[_path_points.size() - 1]
	if pos.distance_to(last_point) < min_point_distance:
		return

	# 壁沿いモード中の処理
	if _is_wall_sliding:
		var slide_result = _process_wall_slide(pos)
		if slide_result.should_exit:
			_reset_wall_slide_state()
			# 壁沿いモード終了後、通常の描画に戻る
			if not slide_result.corner_hit:
				# 壁から離れる場合は通常のポイント追加を試みる
				var exit_hit_result = _check_wall_between(last_point, pos)
				if not exit_hit_result.hit:
					_append_point_and_emit(pos)
			return
		if slide_result.new_point != Vector3.ZERO:
			_append_point_and_emit(slide_result.new_point)
		return

	# 通常モードの処理
	var hit_result = _check_wall_between(last_point, pos)
	if hit_result.hit:
		var wall_pos = hit_result.position

		if enable_wall_sliding:
			# 壁沿いモードに入る
			var move_dir = (pos - last_point).normalized()
			if _enter_wall_slide_mode(hit_result, move_dir):
				# 壁沿いの開始位置（壁の法線方向にオフセット）
				var wall_slide_start = wall_pos + _wall_slide_normal * wall_slide_offset
				wall_slide_start.y = ground_plane_height

				# last_point が壁に近すぎる場合は修正
				var last_to_wall_dist = last_point.distance_to(wall_pos)
				if last_to_wall_dist < wall_slide_offset and _path_points.size() > 1:
					# 最後のポイントを壁から離れた位置に修正
					var corrected_last = wall_pos + _wall_slide_normal * wall_slide_offset
					corrected_last.y = ground_plane_height
					_path_points[_path_points.size() - 1] = corrected_last
					_path_mesh.update_from_points(_path_points)
					# 修正されたポイントを通知
					path_point_added.emit(_character, corrected_last)
				else:
					# last_point から wall_slide_start への線が壁を通らないかチェック
					var check_hit = _check_wall_between(last_point, wall_slide_start)
					if check_hit.hit:
						var slide_safe_pos = check_hit.position + _wall_slide_normal * wall_slide_offset
						slide_safe_pos.y = ground_plane_height
						if slide_safe_pos.distance_to(last_point) >= min_point_distance:
							_append_point_and_emit(slide_safe_pos)
					elif wall_slide_start.distance_to(last_point) >= min_point_distance:
						_append_point_and_emit(wall_slide_start)
				return

		# スライドできない場合は壁の手前で停止
		var to_wall = (wall_pos - last_point).normalized()
		var safe_pos = wall_pos - to_wall * wall_slide_offset
		safe_pos.y = ground_plane_height
		if safe_pos.distance_to(last_point) >= min_point_distance:
			_append_point_and_emit(safe_pos)
		_finish_drawing()
		return

	# 壁に近すぎないかチェックして補正
	var corrected_pos = _correct_position_away_from_wall(pos)
	_append_point_and_emit(corrected_pos)


## ポイントを追加してシグナルを発火（リアルタイム確定）
func _append_point_and_emit(pos: Vector3) -> void:
	_path_points.append(pos)
	_path_mesh.update_from_points(_path_points)
	# リアルタイムでパスポイント追加を通知
	path_point_added.emit(_character, pos)


func _finish_drawing() -> void:
	_is_drawing = false
	_reset_wall_slide_state()
	_reset_path_longpress()  # パス描画終了時に長押し状態をリセット

	if _path_points.size() >= 2 and _character:
		_point_history.append(PointType.PATH)

	# パスは既にリアルタイムで確定済み - 描画終了を通知
	drawing_finished.emit(_path_points)


## パスの先端から続けて描画可能かどうか
func can_continue_path() -> bool:
	return _path_points.size() >= 2 and not _is_drawing


## パスの先端から描画を継続開始
func start_continue_from_endpoint() -> bool:
	if not can_continue_path():
		return false
	_is_drawing = true
	return true
#endregion


#region ユーティリティ
func _get_ground_position(screen_pos: Vector2) -> Variant:
	return PathRaycastHelper.get_ground_position(_camera, _ground_plane, screen_pos)


func _check_wall_between(from: Vector3, to: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	return PathRaycastHelper.check_wall_between(space_state, from, to, wall_collision_mask, ground_plane_height)


## 壁沿いにスライドした位置を計算
## @param from: 開始位置
## @param to: 目標位置（壁にぶつかった）
## @param hit_result: 壁ヒット結果 { position, normal }
## @return: スライド後の位置（スライド不可の場合はVector3.ZERO）
func _calculate_wall_slide_position(from: Vector3, to: Vector3, hit_result: Dictionary) -> Vector3:
	var wall_normal: Vector3 = hit_result.get("normal", Vector3.ZERO)
	if wall_normal.length() < 0.001:
		return Vector3.ZERO

	# 移動方向
	var move_dir := (to - from).normalized()

	# スライド方向 = 移動方向から壁法線成分を除去
	var slide_dir := move_dir - wall_normal * move_dir.dot(wall_normal)
	if slide_dir.length() < 0.001:
		# 壁に真正面から当たった
		return Vector3.ZERO
	slide_dir = slide_dir.normalized()

	# 壁の手前位置（安全な距離を確保）
	# wall_normalは壁から離れる方向を向いているので、その方向にオフセット
	var wall_pos: Vector3 = hit_result.position
	var safe_wall_pos := wall_pos + wall_normal * wall_slide_offset
	safe_wall_pos.y = ground_plane_height

	# スライド方向への移動量（元の目標までの残り距離を使用）
	var remaining_distance := wall_pos.distance_to(to)
	var slide_target := safe_wall_pos + slide_dir * remaining_distance
	slide_target.y = ground_plane_height

	# スライド先が壁にぶつからないかチェック
	var slide_hit := _check_wall_between(safe_wall_pos, slide_target)
	if slide_hit.hit:
		# 壁角に当たった - スライド先の壁の手前で止める
		var slide_wall_pos: Vector3 = slide_hit.position
		var slide_wall_normal: Vector3 = slide_hit.get("normal", Vector3.ZERO)
		if slide_wall_normal.length() > 0.001:
			var corner_pos := slide_wall_pos + slide_wall_normal * wall_slide_offset
			corner_pos.y = ground_plane_height
			# 最低距離を確保
			if corner_pos.distance_to(from) >= min_point_distance:
				return corner_pos
		return Vector3.ZERO

	# 最低距離を確保
	if slide_target.distance_to(from) < min_point_distance:
		return Vector3.ZERO

	return slide_target


## 壁沿いモードに入る
## @param hit_result: 壁ヒット結果 { position, normal }
## @param move_dir: 移動方向
## @return: 成功した場合true
func _enter_wall_slide_mode(hit_result: Dictionary, move_dir: Vector3) -> bool:
	var wall_normal: Vector3 = hit_result.get("normal", Vector3.ZERO)
	if wall_normal.length() < 0.001:
		return false

	# Y成分を除去して水平方向のみで計算
	wall_normal.y = 0
	wall_normal = wall_normal.normalized()
	if wall_normal.length() < 0.001:
		return false

	# スライド方向 = 移動方向から壁法線成分を除去
	var slide_dir := move_dir - wall_normal * move_dir.dot(wall_normal)
	slide_dir.y = 0
	if slide_dir.length() < 0.001:
		# 壁に真正面から当たった
		return false
	slide_dir = slide_dir.normalized()

	_is_wall_sliding = true
	_wall_slide_normal = wall_normal
	_wall_slide_direction = slide_dir

	return true


## 壁沿いモード中の処理
## @param user_pos: ユーザーの入力位置
## @return: { should_exit: bool, corner_hit: bool, new_point: Vector3 }
func _process_wall_slide(user_pos: Vector3) -> Dictionary:
	var result = { "should_exit": false, "corner_hit": false, "new_point": Vector3.ZERO }

	if _path_points.size() == 0:
		result.should_exit = true
		return result

	var last_point = _path_points[_path_points.size() - 1]

	# ユーザーの移動方向を計算
	var user_move_dir = (user_pos - last_point)
	user_move_dir.y = 0
	if user_move_dir.length() < 0.001:
		return result  # 動いていない
	user_move_dir = user_move_dir.normalized()

	# 壁沿いモード終了判定
	if _should_exit_wall_slide(user_pos, user_move_dir):
		result.should_exit = true
		result.corner_hit = false
		return result

	# スライド方向への移動量を計算
	var slide_amount = user_move_dir.dot(_wall_slide_direction)
	if slide_amount < 0.1:
		# スライド方向にほとんど動いていない
		return result

	# スライド方向に沿って新しい位置を計算
	var move_distance = user_pos.distance_to(last_point) * slide_amount
	var new_pos = last_point + _wall_slide_direction * move_distance
	new_pos.y = ground_plane_height

	# 最低距離チェック
	if new_pos.distance_to(last_point) < min_point_distance:
		return result

	# スライド先が壁にぶつからないかチェック（角の検出）
	var slide_hit = _check_wall_between(last_point, new_pos)
	if slide_hit.hit:
		# 角に当たった - 壁沿いモード終了
		var corner_wall_pos: Vector3 = slide_hit.position
		var corner_wall_normal: Vector3 = slide_hit.get("normal", Vector3.ZERO)
		if corner_wall_normal.length() > 0.001:
			corner_wall_normal.y = 0
			corner_wall_normal = corner_wall_normal.normalized()
			var corner_pos = corner_wall_pos + corner_wall_normal * wall_slide_offset
			corner_pos.y = ground_plane_height
			if corner_pos.distance_to(last_point) >= min_point_distance:
				result.new_point = corner_pos
		result.should_exit = true
		result.corner_hit = true
		return result

	# 新しい位置から壁方向にレイキャストして、壁が近すぎないかチェック
	var wall_check_pos = new_pos - _wall_slide_normal * (wall_slide_offset * 2)
	var wall_distance_hit = _check_wall_between(new_pos, wall_check_pos)
	if wall_distance_hit.hit:
		# 壁が近い場合は壁から離れた位置に補正
		var nearby_wall_pos: Vector3 = wall_distance_hit.position
		var nearby_wall_normal: Vector3 = wall_distance_hit.get("normal", _wall_slide_normal)
		nearby_wall_normal.y = 0
		if nearby_wall_normal.length() > 0.001:
			nearby_wall_normal = nearby_wall_normal.normalized()
			new_pos = nearby_wall_pos + nearby_wall_normal * wall_slide_offset
			new_pos.y = ground_plane_height
			# 壁法線を更新（壁が曲がっている場合に対応）
			_wall_slide_normal = nearby_wall_normal

	result.new_point = new_pos
	return result


## 壁沿いモード終了判定
## @param _user_pos: ユーザーの入力位置（将来の拡張用、現在未使用）
## @param user_move_dir: ユーザーの移動方向（正規化済み）
## @return: 終了すべき場合true
func _should_exit_wall_slide(_user_pos: Vector3, user_move_dir: Vector3) -> bool:
	# ユーザーが壁から離れる方向に動いているかチェック
	# 壁法線とユーザー移動方向のドット積が正なら、壁から離れている
	var away_from_wall = user_move_dir.dot(_wall_slide_normal)

	# スライド方向との角度をチェック
	var slide_alignment = abs(user_move_dir.dot(_wall_slide_direction))

	# 壁から離れる方向に明確に動いている場合（閾値: 0.3）
	# かつスライド方向との整合性が低い場合
	if away_from_wall > 0.3 and slide_alignment < 0.5:
		return true

	# ユーザーがスライド方向と逆方向に大きく動いている場合も終了
	var reverse_slide = user_move_dir.dot(_wall_slide_direction)
	if reverse_slide < -0.5:
		return true

	return false


## 壁沿い状態をリセット
func _reset_wall_slide_state() -> void:
	_is_wall_sliding = false
	_wall_slide_normal = Vector3.ZERO
	_wall_slide_direction = Vector3.ZERO


## 位置が壁に近すぎる場合は壁から離れた位置に補正
## @param pos: チェックする位置
## @return: 補正後の位置（壁が近くない場合はそのまま返す）
func _correct_position_away_from_wall(pos: Vector3) -> Vector3:
	var corrected = pos
	var check_distance = wall_slide_offset * 2

	# 4方向にレイキャストして壁をチェック
	var directions = [
		Vector3(1, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(0, 0, 1),
		Vector3(0, 0, -1)
	]

	for dir in directions:
		var check_target = pos + dir * check_distance
		var hit = _check_wall_between(pos, check_target)
		if hit.hit:
			var wall_pos: Vector3 = hit.position
			var wall_normal: Vector3 = hit.get("normal", -dir)
			wall_normal.y = 0
			if wall_normal.length() > 0.001:
				wall_normal = wall_normal.normalized()
				var dist_to_wall = pos.distance_to(wall_pos)
				if dist_to_wall < wall_slide_offset:
					# 壁から離れた位置に補正
					corrected = wall_pos + wall_normal * wall_slide_offset
					corrected.y = ground_plane_height
					break

	return corrected


func _find_closest_point_on_path(pos: Vector3) -> Dictionary:
	return PathCalculator.find_closest_point_on_path(_path_points, pos)


func _find_offset_point_on_path(base_ratio: float, offset_distance: float) -> Dictionary:
	return PathCalculator.find_offset_point_on_path(_path_points, base_ratio, offset_distance)


func _get_path_endpoint() -> Vector3:
	return PathCalculator.get_path_endpoint(_path_points)


func _is_near_path_endpoint(ground_pos: Vector3) -> bool:
	return PathCalculator.is_near_path_endpoint(_path_points, ground_pos, path_endpoint_threshold)


func _raycast_wall_or_floor(screen_pos: Vector2) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	return PathRaycastHelper.raycast_wall_or_floor(_camera, space_state, screen_pos)


## パス上長押しからVisionモードを開始
func _start_vision_mode_from_longpress() -> void:
	_path_longpress_pending = false
	_path_longpress_timer = 0.0

	if _path_points.size() < 2:
		return

	# パス上の最も近い点を見つける
	var result = _find_closest_point_on_path(_path_longpress_ground_pos)
	if result.is_empty() or result.distance > path_click_threshold:
		return

	# 長押しからVisionモードに入ったことを記録
	_longpress_vision_mode = true

	# Visionモードに切り替え
	_drawing_mode = DrawingMode.VISION_POINT
	mode_changed.emit(int(DrawingMode.VISION_POINT))

	# Visionハンドラにアンカーとしてのプレスをシミュレートするために
	# 内部状態を直接設定
	_vision_handler._current_anchor = result.point
	_vision_handler._current_ratio = result.ratio
	_vision_handler._is_drawing = true


## パス上長押し状態をリセット
func _reset_path_longpress() -> void:
	_path_longpress_pending = false
	_path_longpress_timer = 0.0
	_path_longpress_screen_pos = Vector2.ZERO
	_path_longpress_ground_pos = Vector3.ZERO
#endregion


#region モード切替 API
func get_drawing_mode() -> DrawingMode:
	return _drawing_mode


func start_movement_mode() -> void:
	_drawing_mode = DrawingMode.MOVEMENT
	_path_points.clear()
	_longpress_vision_mode = false
	_reset_path_longpress()
	mode_changed.emit(int(DrawingMode.MOVEMENT))


func start_vision_mode() -> bool:
	if _path_points.size() < 2:
		return false
	_drawing_mode = DrawingMode.VISION_POINT
	_is_enabled = true
	_longpress_vision_mode = false  # UIから開始した場合は自動復帰しない
	_vision_handler.reset_state()
	mode_changed.emit(int(DrawingMode.VISION_POINT))
	return true


func start_wait_mode() -> bool:
	if _path_points.size() < 2:
		return false
	_drawing_mode = DrawingMode.WAIT_POINT
	_is_enabled = true
	_wait_handler.reset_state()
	mode_changed.emit(int(DrawingMode.WAIT_POINT))
	return true
#endregion


#region ポイント取得 API（ファサード）
func has_vision_points() -> bool:
	return _vision_handler.has_points()


func get_vision_points() -> Array[Dictionary]:
	return _vision_handler.get_points()


func get_vision_point_count() -> int:
	return _vision_handler.get_point_count()


func take_vision_points() -> Array[MeshInstance3D]:
	return _vision_handler.take_points()


func has_wait_points() -> bool:
	return _wait_handler.has_points()


func get_wait_points() -> Array[Dictionary]:
	return _wait_handler.get_points()


func get_wait_point_count() -> int:
	return _wait_handler.get_point_count()


func take_wait_points() -> Array[MeshInstance3D]:
	return _wait_handler.take_points()


## 同期Waitポイントを追加（コンテキストメニューから呼ばれる）
## @param path_ratio: パス上の位置（0.0〜1.0）
## @param anchor: ポイントの3D位置
func add_sync_wait_point(path_ratio: float, anchor: Vector3) -> void:
	_wait_handler.add_sync_point(path_ratio, anchor)
	_point_history.append(int(PointType.WAIT))
#endregion


#region 全キャラクター用 API（後方互換）
func get_all_vision_points() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_vision_points() }
	return {}


func get_all_wait_points() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_wait_points() }
	return {}


func take_all_vision_points() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_vision_points() }
	return {}


func take_all_wait_points() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_wait_points() }
	return {}
#endregion


#region Undo API
func undo_last_point() -> int:
	if _point_history.is_empty():
		return -1

	var last_type = _point_history.pop_back()

	match last_type:
		PointType.VISION:
			_vision_handler.undo_last()
		PointType.WAIT:
			_wait_handler.undo_last()
		PointType.PATH:
			_undo_path()

	return last_type


func _undo_path() -> void:
	_path_points.clear()
	_path_mesh.clear()
	_is_drawing = false
	_drawing_mode = DrawingMode.MOVEMENT

	# 全ハンドラをクリア
	for handler in _get_all_handlers():
		handler.clear_all()

	_point_history.clear()

	path_undone.emit()


func remove_last_vision_point() -> void:
	_vision_handler.undo_last()
#endregion


#region クリア
func clear() -> void:
	_path_points.clear()
	if _path_mesh:
		_path_mesh.clear()
	_is_drawing = false
	_reset_wall_slide_state()
	_drawing_mode = DrawingMode.MOVEMENT
	_point_history.clear()
	_active_edit_character = null

	for handler in _get_all_handlers():
		handler.clear_all()


func clear_path() -> void:
	_path_points.clear()
	if _path_mesh:
		_path_mesh.clear()
	for handler in _get_all_handlers():
		handler.clear_all()
#endregion


#region パス取得 API
func get_drawn_path() -> PackedVector3Array:
	return _path_points


func get_smoothed_path() -> PackedVector3Array:
	return _path_points


func get_relative_path() -> PackedVector3Array:
	if _path_points.size() < 2:
		return PackedVector3Array()
	var start = _path_points[0]
	var relative = PackedVector3Array()
	for point in _path_points:
		relative.append(point - start)
	return relative


func get_relative_vision_points() -> Array[Dictionary]:
	if _path_points.size() < 2:
		return []
	var start = _path_points[0]
	var relative_points: Array[Dictionary] = []
	for vp in get_vision_points():
		relative_points.append({
			"path_ratio": vp.path_ratio,
			"anchor": vp.anchor - start,
			"target_point": vp.target_point - start
		})
	return relative_points


func is_drawing() -> bool:
	return _is_drawing


func is_point_on_path(ground_pos: Vector3) -> bool:
	if _path_points.size() < 2:
		return false
	var result = _find_closest_point_on_path(ground_pos)
	return result.distance <= path_click_threshold


func is_near_path_endpoint(ground_pos: Vector3) -> bool:
	return _is_near_path_endpoint(ground_pos)


func is_point_mode() -> bool:
	return _drawing_mode != DrawingMode.MOVEMENT


## パスが存在するかどうか（2点以上）
func has_path() -> bool:
	return _path_points.size() >= 2


func has_preview_path() -> bool:
	return _path_points.size() >= 2


func get_preview_path() -> PackedVector3Array:
	return _path_points
#endregion


#region 実行 API
func execute(run: bool = false) -> bool:
	if _path_points.size() < 2 or _character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _path_points:
		path_array.append(point)
	_character.set_path(path_array, run)

	_executing_character = _character

	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	_path_points.clear()
	_character = null

	return true


func execute_with_vision(run: bool = false) -> bool:
	if _path_points.size() < 2 or _character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _path_points:
		path_array.append(point)

	var vision_points = get_vision_points()
	if vision_points.size() > 0:
		_character.set_path_with_vision_points(path_array, vision_points.duplicate(), run)
	else:
		_character.set_path(path_array, run)

	_executing_character = _character

	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	_path_points.clear()
	_character = null

	return true


func _on_path_completed() -> void:
	if _executing_character:
		if _executing_character.path_completed.is_connected(_on_path_completed):
			_executing_character.path_completed.disconnect(_on_path_completed)
		_executing_character = null

	clear()
#endregion


#region 統一ポイント API
func get_points_by_type(point_type: ActionPointDataScript.Type) -> Array[Dictionary]:
	match point_type:
		ActionPointDataScript.Type.VISION:
			return get_vision_points()
		ActionPointDataScript.Type.WAIT:
			return get_wait_points()
		_:
			return []


func take_points_by_type(point_type: ActionPointDataScript.Type) -> Array[MeshInstance3D]:
	match point_type:
		ActionPointDataScript.Type.VISION:
			return take_vision_points()
		ActionPointDataScript.Type.WAIT:
			return take_wait_points()
		_:
			return []


func get_all_points_by_type(point_type: ActionPointDataScript.Type) -> Dictionary:
	match point_type:
		ActionPointDataScript.Type.VISION:
			return get_all_vision_points()
		ActionPointDataScript.Type.WAIT:
			return get_all_wait_points()
		_:
			return {}


func take_all_points_by_type(point_type: ActionPointDataScript.Type) -> Dictionary:
	match point_type:
		ActionPointDataScript.Type.VISION:
			return take_all_vision_points()
		ActionPointDataScript.Type.WAIT:
			return take_all_wait_points()
		_:
			return {}


func get_all_point_types_data() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionPointDataScript.Type.values():
		result[type_value] = get_points_by_type(type_value)
	return result


func take_all_point_types_meshes() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionPointDataScript.Type.values():
		result[type_value] = take_points_by_type(type_value)
	return result
#endregion


#region 復元 API
func restore_path_points(character: Node3D, path_data: Dictionary) -> bool:
	if path_data.is_empty():
		return false

	clear()

	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	_character = character as CharacterBody3D

	if path_data.has("path"):
		_path_points.clear()
		for point in path_data["path"]:
			_path_points.append(point)
		_path_points = _path_points.duplicate()
	if _path_points.size() < 2:
		return false

	if _path_mesh and _path_points.size() > 0:
		_path_mesh.update_from_points(_path_points)

	if path_data.has("path_mesh") and is_instance_valid(path_data["path_mesh"]):
		path_data["path_mesh"].queue_free()

	_point_history.append(PointType.PATH)

	# ポイントをハンドラに復元
	_restore_all_points(path_data)

	call_deferred("_emit_drawing_finished_after_restore")
	return true


## 全ポイントをハンドラに復元
func _restore_all_points(path_data: Dictionary) -> void:
	# Vision points
	var vision_data = path_data.get("vision_points_data", [])
	var vision_meshes = path_data.get("vision_points", [])
	if vision_data.size() > 0:
		_vision_handler.restore_points(vision_data, vision_meshes)
		for _i in range(vision_data.size()):
			_point_history.append(PointType.VISION)

	# Wait points
	var wait_data = path_data.get("wait_points_data", [])
	var wait_meshes = path_data.get("wait_points", [])
	if wait_data.size() > 0:
		_wait_handler.restore_points(wait_data, wait_meshes)
		for _i in range(wait_data.size()):
			_point_history.append(PointType.WAIT)


func _emit_drawing_finished_after_restore() -> void:
	if _path_points.size() >= 2:
		drawing_finished.emit(_path_points)
#endregion


#region 後方互換
func is_multi_character_mode() -> bool:
	return false
#endregion


#region 移動中パス継続用
## パスメッシュを非表示にする（移動中継続モード用）
func hide_path_mesh() -> void:
	if _path_mesh:
		_path_mesh.visible = false
#endregion
