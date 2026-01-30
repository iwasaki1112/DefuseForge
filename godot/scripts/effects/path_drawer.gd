class_name PathDrawer
extends Node3D

## 地面にパスを描画するコンポーネント
## マウスドラッグでパスを描き、キャラクター移動に使用
## マーカー処理は各ハンドラに委譲

## 描画モード
enum DrawingMode { MOVEMENT, VISION_POINT, RUN_MARKER, CLEAR_MARKER, GRENADE_MARKER, DOOR_MARKER, WAIT_MARKER, SMOKE_GRENADE_MARKER }

## マーカー履歴用の種別
enum MarkerType { VISION, RUN, CLEAR, PATH, GRENADE, DOOR, PATH_EXTENSION, WAIT, SMOKE_GRENADE }

#region シグナル
signal drawing_finished(points: PackedVector3Array)
signal vision_point_added(anchor: Vector3, target_point: Vector3)
signal run_segment_added(start_ratio: float, end_ratio: float)
signal clear_point_added(path_ratio: float)
signal grenade_marker_added(path_ratio: float, target_pos: Vector3)
signal smoke_grenade_marker_added(path_ratio: float, target_pos: Vector3)
signal door_marker_added(path_ratio: float, door: Node3D)
signal wait_marker_added(path_ratio: float, wait_duration: float)
signal path_undone()
signal mode_changed(mode: int)
## パス外タップ時のシグナル（確定処理用）
signal off_path_tapped()
## 自動確定リクエスト（確認済みパスへのVisionマーカー配置後など）
signal auto_confirm_requested()
## パス上タップ時のシグナル（コンテキストメニュー表示用）
signal path_tapped(screen_pos: Vector2, path_data: Dictionary)
#endregion

#region エクスポート設定
@export var min_point_distance: float = 0.2
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var vision_line_color: Color = Color(0.7, 0.3, 0.9, 0.9)
@export var vision_line_length: float = 2.0
@export var line_width: float = 0.04
@export var ground_plane_height: float = 0.0
@export var max_points: int = 500
@export var path_click_threshold: float = 0.7
@export var path_endpoint_threshold: float = 0.3
@export_flags_3d_physics var wall_collision_mask: int = 2
@export var enable_wall_sliding: bool = true
@export var wall_slide_offset: float = 0.5  ## 壁からの距離
@export var enable_smoothing: bool = true
@export var smoothing_epsilon: float = 0.15
@export var smoothing_segments: int = 4
#endregion

#region 定数
const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")
const ActionMarkerDataScript = preload("res://scripts/effects/action_marker_data.gd")
#endregion

#region 内部変数
var _camera: Camera3D
var _character: Node3D
var _ground_plane: Plane
var _is_drawing: bool = false
var _is_extending_path: bool = false
var _is_enabled: bool = false
var _is_moving_extension_start: bool = false  ## 移動中延長の開始点が設定されているか
var _drawing_mode: DrawingMode = DrawingMode.MOVEMENT
var _path_points: PackedVector3Array = PackedVector3Array()
var _path_mesh: MeshInstance3D

var _pending_path: PackedVector3Array = PackedVector3Array()
var _pending_character: CharacterBody3D = null
var _executing_character: CharacterBody3D = null
var _path_extension_snapshots: Array[PackedVector3Array] = []
var _character_color: Color = Color(1.0, 1.0, 1.0)

var _marker_history: Array[int] = []
var _active_edit_character: Node = null

## 壁沿いモード状態
var _is_wall_sliding: bool = false           ## 壁沿いモード中か
var _wall_slide_normal: Vector3 = Vector3.ZERO  ## 壁の法線
var _wall_slide_direction: Vector3 = Vector3.ZERO  ## スライド方向

## パス上長押しでVisionマーカー配置用
var _path_longpress_pending: bool = false  ## 長押し待機中か
var _path_longpress_timer: float = 0.0     ## 長押しタイマー
var _path_longpress_threshold: float = 0.5  ## 長押し閾値（秒）
var _path_longpress_screen_pos: Vector2 = Vector2.ZERO  ## 長押し開始位置
var _path_longpress_ground_pos: Vector3 = Vector3.ZERO  ## 長押し開始のグラウンド位置
var _longpress_vision_mode: bool = false  ## 長押しからVisionモードに入ったか
var _auto_confirm_after_vision: bool = false  ## Visionマーカー配置後に自動確定するか

## マーカーハンドラ
var _vision_handler: VisionMarkerHandler
var _run_handler: RunMarkerHandler
var _clear_handler: ClearMarkerHandler
var _grenade_handler: GrenadeMarkerHandler
var _smoke_grenade_handler: SmokeGrenadeMarkerHandler
var _door_handler: DoorMarkerHandler
var _wait_handler: WaitMarkerHandler
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
	_vision_handler = VisionMarkerHandler.new()
	_run_handler = RunMarkerHandler.new()
	_clear_handler = ClearMarkerHandler.new()
	_grenade_handler = GrenadeMarkerHandler.new()
	_smoke_grenade_handler = SmokeGrenadeMarkerHandler.new()
	_door_handler = DoorMarkerHandler.new()
	_wait_handler = WaitMarkerHandler.new()

	# ハンドラのシグナル接続
	_vision_handler.marker_added.connect(_on_vision_marker_added)
	_run_handler.marker_added.connect(_on_run_marker_added)
	_clear_handler.marker_added.connect(_on_clear_marker_added)
	_grenade_handler.marker_added.connect(_on_grenade_marker_added)
	_smoke_grenade_handler.marker_added.connect(_on_smoke_grenade_marker_added)
	_door_handler.marker_added.connect(_on_door_marker_added)
	_wait_handler.marker_added.connect(_on_wait_marker_added)


func _setup_handlers_with_camera() -> void:
	var handlers = _get_all_handlers()
	for handler in handlers:
		handler.setup(self, _camera)
		handler.set_character_color(_character_color)


func _get_all_handlers() -> Array:
	return [_vision_handler, _run_handler, _clear_handler, _grenade_handler, _smoke_grenade_handler, _door_handler, _wait_handler]


func _get_handler_for_mode(mode: DrawingMode):
	match mode:
		DrawingMode.VISION_POINT:
			return _vision_handler
		DrawingMode.RUN_MARKER:
			return _run_handler
		DrawingMode.CLEAR_MARKER:
			return _clear_handler
		DrawingMode.GRENADE_MARKER:
			return _grenade_handler
		DrawingMode.SMOKE_GRENADE_MARKER:
			return _smoke_grenade_handler
		DrawingMode.DOOR_MARKER:
			return _door_handler
		DrawingMode.WAIT_MARKER:
			return _wait_handler
		_:
			return null


#region シグナルハンドラ
func _on_vision_marker_added(data: Dictionary) -> void:
	_marker_history.append(MarkerType.VISION)
	vision_point_added.emit(data.get("anchor", Vector3.ZERO), data.get("target_point", Vector3.ZERO))

	# 長押しからVisionモードに入った場合、マーカー配置後にMOVEMENTモードに戻る
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


func _on_run_marker_added(data: Dictionary) -> void:
	_marker_history.append(MarkerType.RUN)
	run_segment_added.emit(data.get("start_ratio", 0.0), data.get("end_ratio", 0.0))


func _on_clear_marker_added(data: Dictionary) -> void:
	_marker_history.append(MarkerType.CLEAR)
	clear_point_added.emit(data.get("path_ratio", 0.0))


func _on_grenade_marker_added(data: Dictionary) -> void:
	_marker_history.append(MarkerType.GRENADE)
	grenade_marker_added.emit(data.get("path_ratio", 0.0), data.get("target_pos", Vector3.ZERO))


func _on_smoke_grenade_marker_added(data: Dictionary) -> void:
	_marker_history.append(MarkerType.SMOKE_GRENADE)
	smoke_grenade_marker_added.emit(data.get("path_ratio", 0.0), data.get("target_pos", Vector3.ZERO))


func _on_door_marker_added(data: Dictionary) -> void:
	_marker_history.append(MarkerType.DOOR)
	door_marker_added.emit(data.get("path_ratio", 0.0), data.get("door_node", null))


func _on_wait_marker_added(data: Dictionary) -> void:
	_marker_history.append(MarkerType.WAIT)
	wait_marker_added.emit(data.get("path_ratio", 0.0), data.get("wait_duration", 0.0))
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


## 指定した開始点からパス描画を開始（移動中延長用）
## @param character: 対象キャラクター
## @param start_point: パス開始点
func enable_from_point(character: Node3D, start_point: Vector3) -> void:
	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	_pending_character = character as CharacterBody3D
	clear()

	# 移動中延長フラグを設定
	_is_moving_extension_start = true

	# 開始点を設定
	_path_points.append(start_point)
	_pending_path.append(start_point)

	# パスメッシュを更新
	if _path_mesh:
		_path_mesh.update_from_points(_path_points)


func disable() -> void:
	_is_enabled = false
	_is_drawing = false
	_is_extending_path = false
	_is_moving_extension_start = false


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

	# パス継続描画の入力処理（優先）
	if _handle_path_extension_input(event):
		return

	match _drawing_mode:
		DrawingMode.MOVEMENT:
			_handle_movement_input(event)
		_:
			# マーカーモードはハンドラに委譲
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


## パス外タップのチェック（マーカーモード用）
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
		if ground_pos != null and has_pending_path():
			if not is_point_on_path(ground_pos) and not _is_near_path_endpoint(ground_pos):
				off_path_tapped.emit()
				get_viewport().set_input_as_handled()


func _handle_path_extension_input(event: InputEvent) -> bool:
	if _is_extending_path:
		# ドラッグ中（マウスまたはタッチ）
		if event is InputEventMouseMotion or event is InputEventScreenDrag:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null:
				_add_extend_point(ground_pos)
			get_viewport().set_input_as_handled()
			return true
		# リリース（マウス）
		elif event is InputEventMouseButton:
			var mouse_event = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
				_finish_extending_path()
				get_viewport().set_input_as_handled()
				return true
		# リリース（タッチ）
		elif event is InputEventScreenTouch and not event.pressed:
			_finish_extending_path()
			get_viewport().set_input_as_handled()
			return true

	# 延長開始判定（マウス）
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if has_pending_path() and not _is_drawing:
				var ground_pos = _get_ground_position(mouse_event.position)
				if ground_pos != null and _is_near_path_endpoint(ground_pos):
					_start_extending_path()
					get_viewport().set_input_as_handled()
					return true

	# 延長開始判定（タッチ）
	if event is InputEventScreenTouch and event.pressed:
		if has_pending_path() and not _is_drawing:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null and _is_near_path_endpoint(ground_pos):
				_start_extending_path()
				get_viewport().set_input_as_handled()
				return true

	return false


func _handle_movement_input(event: InputEvent) -> void:
	# マウス入力
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

	# タッチ入力
	if event is InputEventScreenTouch:
		if event.pressed:
			handle_movement_press(event.position)
		else:
			handle_movement_release(event.position)
		get_viewport().set_input_as_handled()

	if event is InputEventScreenDrag:
		_handle_movement_motion(event.position)
		get_viewport().set_input_as_handled()


## 移動モードでのプレス処理（外部から呼び出し可能）
## @return: 長押し待機を開始した場合true（handle_clickをスキップすべき）
func handle_movement_press(screen_pos: Vector2) -> bool:
	var ground_pos = _get_ground_position(screen_pos)

	# 既存パスがある場合、パス上の長押しをチェック
	if has_pending_path() and ground_pos != null:
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
				"character": _pending_character
			}
			path_tapped.emit(screen_pos, path_data)
		return

	_handle_drawing_release()


## マーカーモードでのリリース処理（外部から呼び出し可能）
## Visionマーカー等のドラッグリリース時に呼ばれる
func handle_marker_release(screen_pos: Vector2) -> bool:
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
				"character": _pending_character
			}
			path_tapped.emit(tap_screen_pos, path_data)
		return true

	if _drawing_mode == DrawingMode.MOVEMENT:
		return false

	var handler = _get_handler_for_mode(_drawing_mode)
	if handler:
		# VisionMarkerHandler等のリリース処理を呼ぶ
		var fake_event = InputEventMouseButton.new()
		fake_event.button_index = MOUSE_BUTTON_LEFT
		fake_event.pressed = false
		fake_event.position = screen_pos
		return handler.handle_input(fake_event)
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
			if _is_extending_path:
				_add_extend_point(ground_pos)
			else:
				_add_point(ground_pos)


## 描画開始処理（マウス/タッチ共通）
func _handle_drawing_press(screen_pos: Vector2) -> void:
	# 既に延長モードが開始されている場合（外部からstart_extending_path()が呼ばれた場合）
	# _path_pointsは既にセットされているので、描画開始のみ行う
	if _is_extending_path:
		_is_drawing = true
		_marker_history.append(MarkerType.PATH_EXTENSION)
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
		if _is_extending_path:
			_finish_extending_path()
			_is_drawing = false
		else:
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

	# 移動中延長の場合は既存の開始点から続ける
	if _is_moving_extension_start:
		_is_drawing = true
		_is_moving_extension_start = false
		return

	if _character:
		var char_pos = Vector3(_character.global_position.x, ground_plane_height, _character.global_position.z)
		var hit_result = _check_wall_between(char_pos, start_pos)
		if hit_result.hit:
			return

	_is_drawing = true
	_path_points.clear()
	_path_points.append(start_pos)
	_path_mesh.update_from_points(_path_points)


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
					_path_points.append(pos)
					_path_mesh.update_from_points(_path_points)
			return
		if slide_result.new_point != Vector3.ZERO:
			_path_points.append(slide_result.new_point)
			_path_mesh.update_from_points(_path_points)
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
				else:
					# last_point から wall_slide_start への線が壁を通らないかチェック
					var check_hit = _check_wall_between(last_point, wall_slide_start)
					if check_hit.hit:
						var slide_safe_pos = check_hit.position + _wall_slide_normal * wall_slide_offset
						slide_safe_pos.y = ground_plane_height
						if slide_safe_pos.distance_to(last_point) >= min_point_distance:
							_path_points.append(slide_safe_pos)
							_path_mesh.update_from_points(_path_points)
					elif wall_slide_start.distance_to(last_point) >= min_point_distance:
						_path_points.append(wall_slide_start)
						_path_mesh.update_from_points(_path_points)
				return

		# スライドできない場合は壁の手前で停止
		var to_wall = (wall_pos - last_point).normalized()
		var safe_pos = wall_pos - to_wall * wall_slide_offset
		safe_pos.y = ground_plane_height
		if safe_pos.distance_to(last_point) >= min_point_distance:
			_path_points.append(safe_pos)
			_path_mesh.update_from_points(_path_points)
		_finish_drawing()
		return

	# 壁に近すぎないかチェックして補正
	var corrected_pos = _correct_position_away_from_wall(pos)
	_path_points.append(corrected_pos)
	_path_mesh.update_from_points(_path_points)


func _finish_drawing() -> void:
	_is_drawing = false
	_reset_wall_slide_state()
	_reset_path_longpress()  # パス描画終了時に長押し状態をリセット

	if _path_points.size() >= 2 and _character:
		if enable_smoothing and _path_points.size() >= 3:
			_pending_path = PathSmoother.smooth_path(_path_points, smoothing_epsilon, smoothing_segments * 2)
		else:
			_pending_path = _path_points.duplicate()
		_pending_character = _character as CharacterBody3D
		_marker_history.append(MarkerType.PATH)

	drawing_finished.emit(_path_points)
#endregion


#region パス継続描画
func can_extend_path() -> bool:
	return has_pending_path() and not _is_drawing and not _is_extending_path


func is_extending_path() -> bool:
	return _is_extending_path


## パス延長を開始（外部から呼び出し可能）
func start_extending_path() -> bool:
	if not can_extend_path():
		return false
	_start_extending_path()
	return true


func _start_extending_path() -> void:
	if not has_pending_path():
		return

	_is_extending_path = true
	_path_extension_snapshots.append(_pending_path.duplicate())
	_path_points = _pending_path.duplicate()
	_path_mesh.update_from_points(_path_points)


func _add_extend_point(pos: Vector3) -> void:
	if not _is_extending_path:
		return

	if _path_points.size() >= max_points:
		_reset_wall_slide_state()
		_finish_extending_path()
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
					_path_points.append(pos)
					_path_mesh.update_from_points(_path_points)
			return
		if slide_result.new_point != Vector3.ZERO:
			_path_points.append(slide_result.new_point)
			_path_mesh.update_from_points(_path_points)
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
				else:
					# last_point から wall_slide_start への線が壁を通らないかチェック
					var check_hit = _check_wall_between(last_point, wall_slide_start)
					if check_hit.hit:
						var slide_safe_pos = check_hit.position + _wall_slide_normal * wall_slide_offset
						slide_safe_pos.y = ground_plane_height
						if slide_safe_pos.distance_to(last_point) >= min_point_distance:
							_path_points.append(slide_safe_pos)
							_path_mesh.update_from_points(_path_points)
					elif wall_slide_start.distance_to(last_point) >= min_point_distance:
						_path_points.append(wall_slide_start)
						_path_mesh.update_from_points(_path_points)
				return

		# スライドできない場合は壁の手前で停止
		var to_wall = (wall_pos - last_point).normalized()
		var safe_pos = wall_pos - to_wall * wall_slide_offset
		safe_pos.y = ground_plane_height
		if safe_pos.distance_to(last_point) >= min_point_distance:
			_path_points.append(safe_pos)
			_path_mesh.update_from_points(_path_points)
		_finish_extending_path()
		return

	# 壁に近すぎないかチェックして補正
	var corrected_pos = _correct_position_away_from_wall(pos)
	_path_points.append(corrected_pos)
	_path_mesh.update_from_points(_path_points)


func _finish_extending_path() -> void:
	_is_extending_path = false
	_reset_wall_slide_state()

	if _path_points.size() >= 2 and _character:
		# 元のパス（既にスムージング済み）を取得
		var original_path: PackedVector3Array = PackedVector3Array()
		if _path_extension_snapshots.size() > 0:
			original_path = _path_extension_snapshots[_path_extension_snapshots.size() - 1]

		if original_path.size() > 0:
			# 延長部分のみを抽出（元のパスの終点から新しいポイントまで）
			var extension_points := PackedVector3Array()

			# 元のパスの終点を延長部分の開始点として追加（スムージングの接続用）
			extension_points.append(original_path[original_path.size() - 1])

			# 延長で追加されたポイントを追加
			for i in range(original_path.size(), _path_points.size()):
				extension_points.append(_path_points[i])

			if extension_points.size() >= 2:
				# 延長部分のみスムージング
				var smoothed_extension: PackedVector3Array
				if enable_smoothing and extension_points.size() >= 3:
					smoothed_extension = PathSmoother.smooth_path(extension_points, smoothing_epsilon, smoothing_segments * 2)
				else:
					smoothed_extension = extension_points.duplicate()

				# 元のパス + スムージング済み延長部分を結合（最初の点は重複するのでスキップ）
				_pending_path = original_path.duplicate()
				for i in range(1, smoothed_extension.size()):
					_pending_path.append(smoothed_extension[i])
			else:
				# 延長部分がない場合は元のパスをそのまま使用
				_pending_path = original_path.duplicate()
		else:
			# スナップショットがない場合は従来通り全体をスムージング
			if enable_smoothing and _path_points.size() >= 3:
				_pending_path = PathSmoother.smooth_path(_path_points, smoothing_epsilon, smoothing_segments * 2)
			else:
				_pending_path = _path_points.duplicate()

		_marker_history.append(MarkerType.PATH_EXTENSION)

	drawing_finished.emit(_path_points)
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
	return PathCalculator.find_closest_point_on_path(_pending_path, pos)


func _find_offset_point_on_path(base_ratio: float, offset_distance: float) -> Dictionary:
	return PathCalculator.find_offset_point_on_path(_pending_path, base_ratio, offset_distance)


func _get_path_endpoint() -> Vector3:
	return PathCalculator.get_path_endpoint(_pending_path)


func _is_near_path_endpoint(ground_pos: Vector3) -> bool:
	return PathCalculator.is_near_path_endpoint(_pending_path, ground_pos, path_endpoint_threshold)


func _raycast_wall_or_floor(screen_pos: Vector2) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	return PathRaycastHelper.raycast_wall_or_floor(_camera, space_state, screen_pos)


func _raycast_door(screen_pos: Vector2) -> Node3D:
	var space_state = get_world_3d().direct_space_state
	return PathRaycastHelper.raycast_door(_camera, space_state, screen_pos)


## パス上長押しからVisionモードを開始
func _start_vision_mode_from_longpress() -> void:
	_path_longpress_pending = false
	_path_longpress_timer = 0.0

	if _pending_path.size() < 2:
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
	if _pending_path.size() < 2:
		return false
	_drawing_mode = DrawingMode.VISION_POINT
	_is_enabled = true
	_longpress_vision_mode = false  # UIから開始した場合は自動復帰しない
	mode_changed.emit(int(DrawingMode.VISION_POINT))
	return true


func start_run_mode() -> bool:
	if _pending_path.size() < 2:
		return false
	_drawing_mode = DrawingMode.RUN_MARKER
	_is_enabled = true
	_run_handler.reset_state()
	mode_changed.emit(int(DrawingMode.RUN_MARKER))
	return true


func start_clear_mode() -> bool:
	if _pending_path.size() < 2:
		return false
	_drawing_mode = DrawingMode.CLEAR_MARKER
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.CLEAR_MARKER))
	return true


func start_grenade_mode() -> bool:
	if _pending_path.size() < 2:
		return false
	_drawing_mode = DrawingMode.GRENADE_MARKER
	_is_enabled = true
	_grenade_handler.reset_state()
	mode_changed.emit(int(DrawingMode.GRENADE_MARKER))
	return true


func start_smoke_grenade_mode() -> bool:
	if _pending_path.size() < 2:
		return false
	_drawing_mode = DrawingMode.SMOKE_GRENADE_MARKER
	_is_enabled = true
	_smoke_grenade_handler.reset_state()
	mode_changed.emit(int(DrawingMode.SMOKE_GRENADE_MARKER))
	return true


func start_door_mode() -> bool:
	if _pending_path.size() < 2:
		return false
	_drawing_mode = DrawingMode.DOOR_MARKER
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.DOOR_MARKER))
	return true


func start_wait_mode() -> bool:
	if _pending_path.size() < 2:
		return false
	_drawing_mode = DrawingMode.WAIT_MARKER
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.WAIT_MARKER))
	return true
#endregion


#region マーカー取得 API（ファサード）
func has_vision_points() -> bool:
	return _vision_handler.has_markers()


func get_vision_points() -> Array[Dictionary]:
	return _vision_handler.get_markers()


func get_vision_point_count() -> int:
	return _vision_handler.get_marker_count()


func take_vision_markers() -> Array[MeshInstance3D]:
	return _vision_handler.take_markers()


func has_run_segments() -> bool:
	return _run_handler.has_markers()


func get_run_segments() -> Array[Dictionary]:
	return _run_handler.get_markers()


func get_run_segment_count() -> int:
	return _run_handler.get_marker_count()


func has_incomplete_run_start() -> bool:
	return _run_handler.has_incomplete_run_start()


func take_run_markers() -> Array[MeshInstance3D]:
	return _run_handler.take_markers()


func has_clear_points() -> bool:
	return _clear_handler.has_markers()


func get_clear_points() -> Array[Dictionary]:
	return _clear_handler.get_markers()


func get_clear_point_count() -> int:
	return _clear_handler.get_marker_count()


func take_clear_markers() -> Array[MeshInstance3D]:
	return _clear_handler.take_markers()


func has_grenade_markers() -> bool:
	return _grenade_handler.has_markers()


func get_grenade_markers() -> Array[Dictionary]:
	return _grenade_handler.get_markers()


func get_grenade_marker_count() -> int:
	return _grenade_handler.get_marker_count()


func take_grenade_markers() -> Array[MeshInstance3D]:
	return _grenade_handler.take_markers()


func has_smoke_grenade_markers() -> bool:
	return _smoke_grenade_handler.has_markers()


func get_smoke_grenade_markers() -> Array[Dictionary]:
	return _smoke_grenade_handler.get_markers()


func get_smoke_grenade_marker_count() -> int:
	return _smoke_grenade_handler.get_marker_count()


func take_smoke_grenade_markers() -> Array[MeshInstance3D]:
	return _smoke_grenade_handler.take_markers()


func has_door_markers() -> bool:
	return _door_handler.has_markers()


func get_door_markers() -> Array[Dictionary]:
	return _door_handler.get_markers()


func get_door_marker_count() -> int:
	return _door_handler.get_marker_count()


func take_door_markers() -> Array[MeshInstance3D]:
	return _door_handler.take_markers()


func has_wait_markers() -> bool:
	return _wait_handler.has_markers()


func get_wait_markers() -> Array[Dictionary]:
	return _wait_handler.get_markers()


func get_wait_marker_count() -> int:
	return _wait_handler.get_marker_count()


func take_wait_markers() -> Array[MeshInstance3D]:
	return _wait_handler.take_markers()


## 同期Waitマーカーを追加（コンテキストメニューから呼ばれる）
## @param path_ratio: パス上の位置（0.0〜1.0）
## @param anchor: マーカーの3D位置
func add_sync_wait_marker(path_ratio: float, anchor: Vector3) -> void:
	_wait_handler.add_sync_marker(path_ratio, anchor)
	_marker_history.append(int(MarkerType.WAIT))
#endregion


#region 全キャラクター用 API（後方互換）
func get_all_vision_points() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_vision_points() }
	return {}


func get_all_run_segments() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_run_segments() }
	return {}


func get_all_clear_points() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_clear_points() }
	return {}


func get_all_grenade_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_grenade_markers() }
	return {}


func get_all_smoke_grenade_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_smoke_grenade_markers() }
	return {}


func get_all_door_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_door_markers() }
	return {}


func get_all_wait_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): get_wait_markers() }
	return {}


func take_all_vision_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_vision_markers() }
	return {}


func take_all_run_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_run_markers() }
	return {}


func take_all_clear_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_clear_markers() }
	return {}


func take_all_grenade_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_grenade_markers() }
	return {}


func take_all_smoke_grenade_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_smoke_grenade_markers() }
	return {}


func take_all_door_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_door_markers() }
	return {}


func take_all_wait_markers() -> Dictionary:
	if _active_edit_character:
		return { _active_edit_character.get_instance_id(): take_wait_markers() }
	return {}
#endregion


#region Undo API
func undo_last_marker() -> int:
	if _marker_history.is_empty():
		return -1

	var last_type = _marker_history.pop_back()

	match last_type:
		MarkerType.VISION:
			_vision_handler.undo_last()
		MarkerType.RUN:
			_run_handler.undo_last()
		MarkerType.CLEAR:
			_clear_handler.undo_last()
		MarkerType.GRENADE:
			_grenade_handler.undo_last()
		MarkerType.SMOKE_GRENADE:
			_smoke_grenade_handler.undo_last()
		MarkerType.DOOR:
			_door_handler.undo_last()
		MarkerType.WAIT:
			_wait_handler.undo_last()
		MarkerType.PATH:
			_undo_path()
		MarkerType.PATH_EXTENSION:
			_undo_path_extension()

	return last_type


func _undo_path() -> void:
	_path_points.clear()
	_path_mesh.clear()
	_pending_path.clear()
	_pending_character = null
	_path_extension_snapshots.clear()
	_is_drawing = false
	_drawing_mode = DrawingMode.MOVEMENT

	# 全ハンドラをクリア
	for handler in _get_all_handlers():
		handler.clear_all()

	_marker_history.clear()

	path_undone.emit()


func _undo_path_extension() -> void:
	if _path_extension_snapshots.is_empty():
		return

	var previous_path = _path_extension_snapshots.pop_back()
	_pending_path = previous_path
	_path_points = previous_path.duplicate()

	if _path_mesh:
		_path_mesh.update_from_points(_path_points)


func remove_last_vision_point() -> void:
	_vision_handler.undo_last()


func remove_last_run_segment() -> void:
	_run_handler.undo_last()


func remove_last_clear_point() -> void:
	_clear_handler.undo_last()
#endregion


#region クリア
func clear() -> void:
	_path_points.clear()
	_path_mesh.clear()
	_is_drawing = false
	_is_extending_path = false
	_is_moving_extension_start = false
	_reset_wall_slide_state()
	_drawing_mode = DrawingMode.MOVEMENT
	_pending_path.clear()
	_pending_character = null
	_path_extension_snapshots.clear()
	_marker_history.clear()
	_active_edit_character = null

	for handler in _get_all_handlers():
		handler.clear_all()


func clear_pending() -> void:
	_pending_path.clear()
	_pending_character = null
	for handler in _get_all_handlers():
		handler.clear_all()
#endregion


#region パス取得 API
func get_drawn_path() -> PackedVector3Array:
	return _path_points


func get_smoothed_path() -> PackedVector3Array:
	return _pending_path


func get_relative_path() -> PackedVector3Array:
	if _pending_path.size() < 2:
		return PackedVector3Array()
	var start = _pending_path[0]
	var relative = PackedVector3Array()
	for point in _pending_path:
		relative.append(point - start)
	return relative


func get_relative_vision_points() -> Array[Dictionary]:
	if _pending_path.size() < 2:
		return []
	var start = _pending_path[0]
	var relative_points: Array[Dictionary] = []
	for vp in get_vision_points():
		relative_points.append({
			"path_ratio": vp.path_ratio,
			"anchor": vp.anchor - start,
			"target_point": vp.target_point - start
		})
	return relative_points


func is_drawing() -> bool:
	return _is_drawing or _is_extending_path


func is_point_on_path(ground_pos: Vector3) -> bool:
	if _pending_path.size() < 2:
		return false
	var result = _find_closest_point_on_path(ground_pos)
	return result.distance <= path_click_threshold


func is_near_path_endpoint(ground_pos: Vector3) -> bool:
	return _is_near_path_endpoint(ground_pos)


func is_marker_mode() -> bool:
	return _drawing_mode != DrawingMode.MOVEMENT


func has_pending_path() -> bool:
	return _pending_path.size() >= 2 and _pending_character != null


func has_preview_path() -> bool:
	if _is_drawing or _is_extending_path:
		return _path_points.size() >= 2 and _character != null
	return has_pending_path()


func get_preview_path() -> PackedVector3Array:
	if _is_drawing or _is_extending_path:
		return _path_points
	return _pending_path
#endregion


#region 実行 API
func execute(run: bool = false) -> bool:
	if _pending_path.size() < 2 or _pending_character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _pending_path:
		path_array.append(point)
	_pending_character.set_path(path_array, run)

	_executing_character = _pending_character

	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	_pending_path.clear()
	_pending_character = null

	return true


func execute_with_vision(run: bool = false) -> bool:
	if _pending_path.size() < 2 or _pending_character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _pending_path:
		path_array.append(point)

	var vision_points = get_vision_points()
	if vision_points.size() > 0:
		_pending_character.set_path_with_vision_points(path_array, vision_points.duplicate(), run)
	else:
		_pending_character.set_path(path_array, run)

	_executing_character = _pending_character

	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	_pending_path.clear()
	_pending_character = null

	return true


func _on_path_completed() -> void:
	if _executing_character:
		if _executing_character.path_completed.is_connected(_on_path_completed):
			_executing_character.path_completed.disconnect(_on_path_completed)
		_executing_character = null

	clear()
#endregion


#region 統一マーカー API
func get_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Array[Dictionary]:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return get_vision_points()
		ActionMarkerDataScript.Type.RUN:
			return get_run_segments()
		ActionMarkerDataScript.Type.CLEAR:
			return get_clear_points()
		ActionMarkerDataScript.Type.GRENADE:
			return get_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return get_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return get_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return get_smoke_grenade_markers()
		_:
			return []


func take_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Array[MeshInstance3D]:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return take_vision_markers()
		ActionMarkerDataScript.Type.RUN:
			return take_run_markers()
		ActionMarkerDataScript.Type.CLEAR:
			return take_clear_markers()
		ActionMarkerDataScript.Type.GRENADE:
			return take_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return take_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return take_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return take_smoke_grenade_markers()
		_:
			return []


func get_all_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Dictionary:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return get_all_vision_points()
		ActionMarkerDataScript.Type.RUN:
			return get_all_run_segments()
		ActionMarkerDataScript.Type.CLEAR:
			return get_all_clear_points()
		ActionMarkerDataScript.Type.GRENADE:
			return get_all_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return get_all_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return get_all_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return get_all_smoke_grenade_markers()
		_:
			return {}


func take_all_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Dictionary:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return take_all_vision_markers()
		ActionMarkerDataScript.Type.RUN:
			return take_all_run_markers()
		ActionMarkerDataScript.Type.CLEAR:
			return take_all_clear_markers()
		ActionMarkerDataScript.Type.GRENADE:
			return take_all_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return take_all_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return take_all_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return take_all_smoke_grenade_markers()
		_:
			return {}


func get_all_marker_types_data() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionMarkerDataScript.Type.values():
		result[type_value] = get_markers_by_type(type_value)
	return result


func take_all_marker_types_meshes() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionMarkerDataScript.Type.values():
		result[type_value] = take_markers_by_type(type_value)
	return result
#endregion


#region 復元 API
func restore_pending_path(character: Node3D, path_data: Dictionary) -> bool:
	if path_data.is_empty():
		return false

	clear()

	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	_pending_character = character as CharacterBody3D

	if path_data.has("path"):
		_pending_path.clear()
		for point in path_data["path"]:
			_pending_path.append(point)
		_path_points = _pending_path.duplicate()
	if _path_points.size() < 2:
		return false

	if _path_mesh and _path_points.size() > 0:
		_path_mesh.update_from_points(_path_points)

	if path_data.has("path_mesh") and is_instance_valid(path_data["path_mesh"]):
		path_data["path_mesh"].queue_free()

	_marker_history.append(MarkerType.PATH)

	# マーカーをハンドラに復元
	_restore_all_markers(path_data)

	call_deferred("_emit_drawing_finished_after_restore")
	return true


## 全マーカーをハンドラに復元
func _restore_all_markers(path_data: Dictionary) -> void:
	# Vision markers
	var vision_data = path_data.get("vision_points", [])
	var vision_meshes = path_data.get("vision_markers", [])
	if vision_data.size() > 0:
		_vision_handler.restore_markers(vision_data, vision_meshes)
		for _i in range(vision_data.size()):
			_marker_history.append(MarkerType.VISION)

	# Run markers
	var run_data = path_data.get("run_segments", [])
	var run_meshes = path_data.get("run_markers", [])
	if run_data.size() > 0:
		_run_handler.restore_markers(run_data, run_meshes)
		for _i in range(run_data.size()):
			_marker_history.append(MarkerType.RUN)

	# Clear markers
	var clear_data = path_data.get("clear_points", [])
	var clear_meshes = path_data.get("clear_markers", [])
	if clear_data.size() > 0:
		_clear_handler.restore_markers(clear_data, clear_meshes)
		for _i in range(clear_data.size()):
			_marker_history.append(MarkerType.CLEAR)

	# Grenade markers
	var grenade_data = path_data.get("grenade_markers_data", [])
	var grenade_meshes = path_data.get("grenade_markers", [])
	if grenade_data.size() > 0:
		_grenade_handler.restore_markers(grenade_data, grenade_meshes)
		for _i in range(grenade_data.size()):
			_marker_history.append(MarkerType.GRENADE)

	# Smoke grenade markers
	var smoke_data = path_data.get("smoke_grenade_markers_data", [])
	var smoke_meshes = path_data.get("smoke_grenade_markers", [])
	if smoke_data.size() > 0:
		_smoke_grenade_handler.restore_markers(smoke_data, smoke_meshes)
		for _i in range(smoke_data.size()):
			_marker_history.append(MarkerType.SMOKE_GRENADE)

	# Door markers
	var door_data = path_data.get("door_markers_data", [])
	var door_meshes = path_data.get("door_markers", [])
	if door_data.size() > 0:
		_door_handler.restore_markers(door_data, door_meshes)
		for _i in range(door_data.size()):
			_marker_history.append(MarkerType.DOOR)

	# Wait markers
	var wait_data = path_data.get("wait_markers_data", [])
	var wait_meshes = path_data.get("wait_markers", [])
	if wait_data.size() > 0:
		_wait_handler.restore_markers(wait_data, wait_meshes)
		for _i in range(wait_data.size()):
			_marker_history.append(MarkerType.WAIT)


func _emit_drawing_finished_after_restore() -> void:
	if _path_points.size() >= 2:
		drawing_finished.emit(_path_points)
#endregion


#region 後方互換
func is_multi_character_mode() -> bool:
	return false
#endregion
