class_name PathDrawer
extends Node3D

## 地面にパスを描画するコンポーネント
## マウスドラッグでパスを描き、キャラクター移動に使用
## Slice the Pie: パス上の任意の点から視線方向を設定可能

## 描画モード
enum DrawingMode { MOVEMENT, VISION_POINT }

## 視線ポイントデータ
## { "path_ratio": float, "anchor": Vector3, "direction": Vector3 }

signal drawing_started()
signal drawing_updated(points: PackedVector3Array)
signal drawing_finished(points: PackedVector3Array)
signal path_execution_started(character: CharacterBody3D)
signal path_execution_completed(character: CharacterBody3D)

## 視線ポイント用シグナル
signal vision_point_added(anchor: Vector3, direction: Vector3)
signal vision_point_drawing(anchor: Vector3, direction: Vector3)
signal mode_changed(mode: int)  # 0=MOVEMENT, 1=VISION_POINT

@export var min_point_distance: float = 0.2  # ポイント間の最小距離
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)  # 白
@export var vision_line_color: Color = Color(0.7, 0.3, 0.9, 0.9)  # 紫
@export var vision_line_length: float = 2.0  # 視線ラインの長さ
@export var line_width: float = 0.04
@export var ground_plane_height: float = 0.0
@export var max_points: int = 500
@export var path_click_threshold: float = 0.5  # パスクリック判定距離

const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")
const VisionMarkerScript = preload("res://scripts/effects/vision_marker.gd")

var _camera: Camera3D
var _character: Node3D
var _ground_plane: Plane
var _is_drawing: bool = false
var _is_enabled: bool = false
var _drawing_mode: DrawingMode = DrawingMode.MOVEMENT
var _path_points: PackedVector3Array = PackedVector3Array()
var _path_mesh: MeshInstance3D

## 視線ポイント用
var _vision_points: Array[Dictionary] = []  # { path_ratio, anchor, direction }
var _vision_meshes: Array[MeshInstance3D] = []
var _current_vision_anchor: Vector3 = Vector3.ZERO
var _current_vision_ratio: float = 0.0
var _is_drawing_vision: bool = false

## パス実行管理
var _pending_path: PackedVector3Array = PackedVector3Array()
var _pending_character: CharacterBody3D = null
var _executing_character: CharacterBody3D = null


func _ready() -> void:
	_ground_plane = Plane(Vector3.UP, ground_plane_height)
	_setup_mesh()


func _setup_mesh() -> void:
	_path_mesh = MeshInstance3D.new()
	_path_mesh.set_script(PathLineMeshScript)
	_path_mesh.line_color = line_color
	_path_mesh.line_width = line_width
	add_child(_path_mesh)


func setup(camera: Camera3D, character: Node3D = null) -> void:
	_camera = camera
	_character = character


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or not _is_enabled:
		return

	if _drawing_mode == DrawingMode.MOVEMENT:
		_handle_movement_input(event)
	else:
		_handle_vision_point_input(event)


## 移動パス描画の入力処理
func _handle_movement_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				var start_pos: Vector3
				if _character:
					start_pos = Vector3(_character.global_position.x, 0, _character.global_position.z)
				else:
					var ground_pos = _get_ground_position(mouse_event.position)
					if ground_pos == null:
						return
					start_pos = ground_pos
				_start_drawing(start_pos)
				get_viewport().set_input_as_handled()
			else:
				if _is_drawing:
					_finish_drawing()
					get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _is_drawing:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null:
				_add_point(ground_pos)


## 視線ポイント設定の入力処理
func _handle_vision_point_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# パス上の最も近い点を見つける
				var ground_pos = _get_ground_position(mouse_event.position)
				if ground_pos == null:
					return

				var result = _find_closest_point_on_path(ground_pos)
				if result.distance > path_click_threshold:
					print("[PathDrawer] Click too far from path")
					return

				_current_vision_anchor = result.point
				_current_vision_ratio = result.ratio
				_is_drawing_vision = true
				get_viewport().set_input_as_handled()
			else:
				if _is_drawing_vision:
					var ground_pos = _get_ground_position(mouse_event.position)
					if ground_pos != null:
						_finish_vision_point(ground_pos)
					_is_drawing_vision = false
					get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _is_drawing_vision:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null:
				var direction = (ground_pos - _current_vision_anchor).normalized()
				direction.y = 0
				vision_point_drawing.emit(_current_vision_anchor, direction)
				_update_temp_vision_marker(_current_vision_anchor, direction)


func _get_ground_position(screen_pos: Vector2) -> Variant:
	var ray_origin = _camera.project_ray_origin(screen_pos)
	var ray_direction = _camera.project_ray_normal(screen_pos)

	var intersection = _ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		return intersection as Vector3
	return null


## パス上で最も近い点を見つける
func _find_closest_point_on_path(pos: Vector3) -> Dictionary:
	if _pending_path.size() < 2:
		return { "point": Vector3.ZERO, "distance": INF, "ratio": 0.0 }

	var closest_point: Vector3 = _pending_path[0]
	var closest_distance: float = INF
	var closest_ratio: float = 0.0

	var total_length: float = 0.0
	var lengths: Array[float] = [0.0]

	# パスの総距離を計算
	for i in range(1, _pending_path.size()):
		var segment_length = _pending_path[i - 1].distance_to(_pending_path[i])
		total_length += segment_length
		lengths.append(total_length)

	# 各セグメントで最も近い点を探す
	for i in range(1, _pending_path.size()):
		var p1 = _pending_path[i - 1]
		var p2 = _pending_path[i]

		# セグメント上の最近点を計算
		var segment = p2 - p1
		var segment_length = segment.length()
		if segment_length < 0.001:
			continue

		var t = clampf((pos - p1).dot(segment) / (segment_length * segment_length), 0.0, 1.0)
		var point_on_segment = p1 + segment * t

		var distance = pos.distance_to(point_on_segment)
		if distance < closest_distance:
			closest_distance = distance
			closest_point = point_on_segment
			# このセグメント上での進行率を計算
			var distance_to_point = lengths[i - 1] + segment_length * t
			closest_ratio = distance_to_point / total_length if total_length > 0 else 0.0

	return { "point": closest_point, "distance": closest_distance, "ratio": closest_ratio }


## 視線ポイントの設定を完了
func _finish_vision_point(end_pos: Vector3) -> void:
	var direction = (end_pos - _current_vision_anchor).normalized()
	direction.y = 0

	if direction.length_squared() < 0.001:
		print("[PathDrawer] Vision direction too short")
		return

	# 視線ポイントを追加（path_ratio順にソート）
	var new_point = {
		"path_ratio": _current_vision_ratio,
		"anchor": _current_vision_anchor,
		"direction": direction
	}

	# 挿入位置を見つける
	var insert_index = 0
	for i in range(_vision_points.size()):
		if _vision_points[i].path_ratio > _current_vision_ratio:
			break
		insert_index = i + 1

	_vision_points.insert(insert_index, new_point)

	# 視線マーカーを作成
	_create_vision_marker(_current_vision_anchor, direction)

	vision_point_added.emit(_current_vision_anchor, direction)
	print("[PathDrawer] Vision point added at ratio %.2f" % _current_vision_ratio)


## 視線マーカーを作成
func _create_vision_marker(anchor: Vector3, direction: Vector3) -> void:
	var marker = MeshInstance3D.new()
	marker.set_script(VisionMarkerScript)
	add_child(marker)
	_vision_meshes.append(marker)

	# マーカーの位置と方向を設定
	marker.set_position_and_direction(anchor, direction)


## 一時的な視線マーカーを更新（ドラッグ中）
func _update_temp_vision_marker(anchor: Vector3, direction: Vector3) -> void:
	# 最後のマーカーが一時的なものかチェック
	if _vision_meshes.size() > _vision_points.size():
		var temp_marker = _vision_meshes[-1]
		temp_marker.set_position_and_direction(anchor, direction)
	else:
		# 一時的なマーカーを作成
		var marker = MeshInstance3D.new()
		marker.set_script(VisionMarkerScript)
		add_child(marker)
		_vision_meshes.append(marker)
		marker.set_position_and_direction(anchor, direction)


func _start_drawing(start_pos: Vector3) -> void:
	_is_drawing = true
	_path_points.clear()
	_path_points.append(start_pos)
	_path_mesh.update_from_points(_path_points)
	drawing_started.emit()


func _add_point(pos: Vector3) -> void:
	if _path_points.size() >= max_points:
		return

	var last_point = _path_points[_path_points.size() - 1]
	if pos.distance_to(last_point) < min_point_distance:
		return

	_path_points.append(pos)
	_path_mesh.update_from_points(_path_points)
	drawing_updated.emit(_path_points)


func _finish_drawing() -> void:
	_is_drawing = false

	if _path_points.size() >= 2 and _character:
		_pending_path = _path_points.duplicate()
		_pending_character = _character as CharacterBody3D

	drawing_finished.emit(_path_points)
	print("[PathDrawer] Movement path finished with %d points" % _path_points.size())


## パスをクリア
func clear() -> void:
	_path_points.clear()
	_path_mesh.clear()
	_is_drawing = false
	_is_drawing_vision = false
	_drawing_mode = DrawingMode.MOVEMENT
	_clear_vision_points()


func _clear_vision_points() -> void:
	_vision_points.clear()
	for mesh in _vision_meshes:
		mesh.queue_free()
	_vision_meshes.clear()


func get_drawn_path() -> PackedVector3Array:
	return _path_points


func is_drawing() -> bool:
	return _is_drawing or _is_drawing_vision


func set_line_color(color: Color) -> void:
	line_color = color
	if _path_mesh:
		_path_mesh.set_line_color(color)


func enable(character: Node3D) -> void:
	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	clear()
	print("[PathDrawer] Enabled for character (movement mode)")


func disable() -> void:
	_is_enabled = false
	_is_drawing = false
	_is_drawing_vision = false
	print("[PathDrawer] Disabled")


func is_enabled() -> bool:
	return _is_enabled


func get_drawing_mode() -> DrawingMode:
	return _drawing_mode


## ========================================
## 視線ポイントモード API
## ========================================

## 視線ポイント設定モードに切り替え
func start_vision_mode() -> bool:
	if _pending_path.size() < 2:
		print("[PathDrawer] Cannot start vision mode: no movement path set")
		return false

	_drawing_mode = DrawingMode.VISION_POINT
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.VISION_POINT))
	print("[PathDrawer] Switched to vision point mode - click on path to set look direction")
	return true


## 移動パス描画モードに戻る
func start_movement_mode() -> void:
	_drawing_mode = DrawingMode.MOVEMENT
	_path_points.clear()
	mode_changed.emit(int(DrawingMode.MOVEMENT))
	print("[PathDrawer] Switched to movement mode")


## 視線ポイントがあるか
func has_vision_points() -> bool:
	return _vision_points.size() > 0


## 視線ポイントを取得
func get_vision_points() -> Array[Dictionary]:
	return _vision_points


## 視線ポイント数を取得
func get_vision_point_count() -> int:
	return _vision_points.size()


## 最後の視線ポイントを削除
func remove_last_vision_point() -> void:
	if _vision_points.size() > 0:
		_vision_points.pop_back()
		if _vision_meshes.size() > 0:
			var mesh = _vision_meshes.pop_back()
			mesh.queue_free()
		print("[PathDrawer] Last vision point removed")


## ========================================
## パス実行 API
## ========================================

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

	path_execution_started.emit(_executing_character)

	_pending_path.clear()
	_pending_character = null

	print("[PathDrawer] Path execution started")
	return true


## 視線ポイント付きでパスを実行
func execute_with_vision(run: bool = false) -> bool:
	if _pending_path.size() < 2 or _pending_character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _pending_path:
		path_array.append(point)

	# 視線ポイント付きで移動開始
	if _vision_points.size() > 0:
		_pending_character.set_path_with_vision_points(path_array, _vision_points.duplicate(), run)
	else:
		_pending_character.set_path(path_array, run)

	_executing_character = _pending_character

	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	path_execution_started.emit(_executing_character)

	var vision_count = _vision_points.size()
	_pending_path.clear()
	_vision_points.clear()
	_pending_character = null

	print("[PathDrawer] Path execution started with %d vision points" % vision_count)
	return true


func has_pending_path() -> bool:
	return _pending_path.size() >= 2 and _pending_character != null


func clear_pending() -> void:
	_pending_path.clear()
	_pending_character = null
	_clear_vision_points()


func _on_path_completed() -> void:
	if _executing_character:
		if _executing_character.path_completed.is_connected(_on_path_completed):
			_executing_character.path_completed.disconnect(_on_path_completed)

		path_execution_completed.emit(_executing_character)
		_executing_character = null

	clear()
	print("[PathDrawer] Path execution completed")
