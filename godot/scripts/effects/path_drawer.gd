class_name PathDrawer
extends Node3D

## 地面にパスを描画するコンポーネント
## マウスドラッグでパスを描き、キャラクター移動に使用
## Slice the Pie: パス上の任意の点から視線方向を設定可能

## 描画モード
enum DrawingMode { MOVEMENT, VISION_POINT, RUN_MARKER }

## 視線ポイントデータ
## { "path_ratio": float, "anchor": Vector3, "direction": Vector3 }

## Run区間データ
## { "start_ratio": float, "end_ratio": float }

signal drawing_finished(points: PackedVector3Array)

## 視線ポイント用シグナル
signal vision_point_added(anchor: Vector3, direction: Vector3)
signal mode_changed(mode: int)  # 0=MOVEMENT, 1=VISION_POINT, 2=RUN_MARKER

## Runマーカー用シグナル
signal run_segment_added(start_ratio: float, end_ratio: float)

@export var min_point_distance: float = 0.2  # ポイント間の最小距離
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)  # 白
@export var vision_line_color: Color = Color(0.7, 0.3, 0.9, 0.9)  # 紫
@export var vision_line_length: float = 2.0  # 視線ラインの長さ
@export var line_width: float = 0.04
@export var ground_plane_height: float = 0.0
@export var max_points: int = 500
@export var path_click_threshold: float = 0.5  # パスクリック判定距離
@export var wall_collision_mask: int = 2  # 壁検出用のコリジョンマスク

const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")
const VisionMarkerScript = preload("res://scripts/effects/vision_marker.gd")
const RunMarkerScript = preload("res://scripts/effects/run_marker.gd")

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

## Runマーカー用
var _run_segments: Array[Dictionary] = []  # { start_ratio, end_ratio }
var _run_meshes: Array[MeshInstance3D] = []
var _current_run_start: Dictionary = {}  # 未完成のrun開始点 { ratio, position }

## キャラクター別マーカー管理（マルチセレクト対応）
## { char_id: { "vision_points": Array[Dictionary], "vision_meshes": Array[MeshInstance3D],
##              "run_segments": Array[Dictionary], "run_meshes": Array[MeshInstance3D] } }
var _character_markers: Dictionary = {}
var _active_edit_character: Node = null  # 現在編集中のキャラクター
var _multi_character_mode: bool = false  # マルチキャラクターモード

## パス実行管理
var _pending_path: PackedVector3Array = PackedVector3Array()
var _pending_character: CharacterBody3D = null
var _executing_character: CharacterBody3D = null

## キャラクター色
var _character_color: Color = Color(1.0, 1.0, 1.0)  # デフォルト白


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

	match _drawing_mode:
		DrawingMode.MOVEMENT:
			_handle_movement_input(event)
		DrawingMode.VISION_POINT:
			_handle_vision_point_input(event)
		DrawingMode.RUN_MARKER:
			_handle_run_marker_input(event)


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
				_update_temp_vision_marker(_current_vision_anchor, direction)


## Runマーカー設定の入力処理
func _handle_run_marker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# パス上の最も近い点を見つける
			var ground_pos = _get_ground_position(mouse_event.position)
			if ground_pos == null:
				return

			var result = _find_closest_point_on_path(ground_pos)
			if result.distance > path_click_threshold:
				print("[PathDrawer] Click too far from path for run marker")
				return

			if _current_run_start.is_empty():
				# 開始点を設定
				_current_run_start = { "ratio": result.ratio, "position": result.point }
				_create_run_marker(result.point, RunMarkerScript.MarkerType.START)
				print("[PathDrawer] Run start point set at ratio %.2f" % result.ratio)
			else:
				# 終点を設定してセグメントを完成
				var start_ratio = _current_run_start.ratio
				var end_ratio = result.ratio

				# 開始点が終点より後ろなら入れ替え
				if start_ratio > end_ratio:
					var tmp = start_ratio
					start_ratio = end_ratio
					end_ratio = tmp

				# Run区間を追加
				var new_segment = { "start_ratio": start_ratio, "end_ratio": end_ratio }

				# マルチキャラクターモードの場合、アクティブキャラクターのデータに追加
				if _multi_character_mode and _active_edit_character:
					var char_id = _active_edit_character.get_instance_id()
					if _character_markers.has(char_id):
						var char_data = _character_markers[char_id]
						char_data.run_segments.append(new_segment)
				else:
					_run_segments.append(new_segment)

				# 終点マーカーを作成
				_create_run_marker(result.point, RunMarkerScript.MarkerType.END)

				run_segment_added.emit(start_ratio, end_ratio)
				print("[PathDrawer] Run segment added: %.2f - %.2f" % [start_ratio, end_ratio])

				# 開始点をクリア
				_current_run_start = {}

			get_viewport().set_input_as_handled()


## Runマーカーを作成
func _create_run_marker(pos: Vector3, type: int) -> void:
	var marker = MeshInstance3D.new()
	marker.set_script(RunMarkerScript)
	add_child(marker)

	# マーカーの位置とタイプを設定
	marker.set_position_and_type(pos, type)

	# キャラクター色を適用
	marker.set_colors(_character_color, Color.WHITE)

	# マルチキャラクターモードの場合、アクティブキャラクターのメッシュ配列に追加
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			_character_markers[char_id].run_meshes.append(marker)
			return

	# シングルモードの場合
	_run_meshes.append(marker)


func _get_ground_position(screen_pos: Vector2) -> Variant:
	var ray_origin = _camera.project_ray_origin(screen_pos)
	var ray_direction = _camera.project_ray_normal(screen_pos)

	var intersection = _ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		return intersection as Vector3
	return null


## 2点間に壁があるかチェック
## @return: { "hit": bool, "position": Vector3 (ヒット位置、hitがtrueの場合) }
func _check_wall_between(from: Vector3, to: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return { "hit": false }

	# 地面ギリギリを避けるため、少し高さを上げてレイキャスト
	var check_from = from + Vector3(0, 0.5, 0)
	var check_to = to + Vector3(0, 0.5, 0)

	var query = PhysicsRayQueryParameters3D.create(check_from, check_to, wall_collision_mask)
	var result = space_state.intersect_ray(query)

	if result:
		# ヒット位置を地面高さに補正
		var hit_pos = result.position
		hit_pos.y = ground_plane_height
		return { "hit": true, "position": hit_pos }
	return { "hit": false }


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
		# 一時マーカーがあれば削除
		_remove_temp_vision_marker()
		return

	# 一時マーカーを削除（新しいマーカーを正しい位置に挿入するため）
	_remove_temp_vision_marker()

	# 視線ポイントを追加（path_ratio順にソート）
	var new_point = {
		"path_ratio": _current_vision_ratio,
		"anchor": _current_vision_anchor,
		"direction": direction
	}

	# マルチキャラクターモードの場合、アクティブキャラクターのデータに追加
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			var vision_points: Array[Dictionary] = char_data.vision_points
			var vision_meshes: Array[MeshInstance3D] = char_data.vision_meshes

			# 挿入位置を見つける
			var insert_index = 0
			for i in range(vision_points.size()):
				if vision_points[i].path_ratio > _current_vision_ratio:
					break
				insert_index = i + 1

			vision_points.insert(insert_index, new_point)

			# 視線マーカーを作成
			var marker = _create_vision_marker_node(_current_vision_anchor, direction)
			vision_meshes.insert(insert_index, marker)

			vision_point_added.emit(_current_vision_anchor, direction)
			print("[PathDrawer] Vision point added for %s at ratio %.2f" % [_active_edit_character.name, _current_vision_ratio])
			return

	# シングルモードの場合は従来通り
	var insert_index = 0
	for i in range(_vision_points.size()):
		if _vision_points[i].path_ratio > _current_vision_ratio:
			break
		insert_index = i + 1

	_vision_points.insert(insert_index, new_point)

	# 視線マーカーを作成（同じ挿入位置に）
	_create_vision_marker_at_index(_current_vision_anchor, direction, insert_index)

	vision_point_added.emit(_current_vision_anchor, direction)
	print("[PathDrawer] Vision point added at ratio %.2f" % _current_vision_ratio)


## 視線マーカーを作成（末尾に追加）
func _create_vision_marker(anchor: Vector3, direction: Vector3) -> void:
	_create_vision_marker_at_index(anchor, direction, _vision_meshes.size())


## 視線マーカーノードを作成して返す（マルチキャラクター用）
func _create_vision_marker_node(anchor: Vector3, direction: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(VisionMarkerScript)
	add_child(marker)

	# マーカーの位置と方向を設定
	marker.set_position_and_direction(anchor, direction)

	# キャラクター色を適用
	marker.set_colors(_character_color, Color.WHITE)

	return marker


## 視線マーカーを指定位置に作成
func _create_vision_marker_at_index(anchor: Vector3, direction: Vector3, index: int) -> void:
	var marker = _create_vision_marker_node(anchor, direction)
	_vision_meshes.insert(index, marker)


## 一時的な視線マーカーを削除
func _remove_temp_vision_marker() -> void:
	# 一時マーカーは _vision_meshes.size() > _vision_points.size() の場合に存在
	if _vision_meshes.size() > _vision_points.size():
		var temp_marker = _vision_meshes.pop_back()
		temp_marker.queue_free()


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
		# キャラクター色を適用
		marker.set_colors(_character_color, Color.WHITE)


func _start_drawing(start_pos: Vector3) -> void:
	# キャラクターが設定されている場合、キャラクター位置→開始点間の壁チェック
	if _character:
		var char_pos = Vector3(_character.global_position.x, ground_plane_height, _character.global_position.z)
		var hit_result = _check_wall_between(char_pos, start_pos)
		if hit_result.hit:
			print("[PathDrawer] Cannot start drawing: wall between character and start position")
			return  # 描画開始を拒否

	_is_drawing = true
	_path_points.clear()
	_path_points.append(start_pos)
	_path_mesh.update_from_points(_path_points)


func _add_point(pos: Vector3) -> void:
	if _path_points.size() >= max_points:
		return

	var last_point = _path_points[_path_points.size() - 1]
	if pos.distance_to(last_point) < min_point_distance:
		return

	# 壁検出: 前のポイントから新しいポイントへ壁がないかチェック
	var hit_result = _check_wall_between(last_point, pos)
	if hit_result.hit:
		# 壁直前のポイントを追加して描画終了
		var wall_pos = hit_result.position
		# 壁に少し手前で止まる（0.1m手前）
		var to_wall = (wall_pos - last_point).normalized()
		var safe_pos = wall_pos - to_wall * 0.1
		safe_pos.y = ground_plane_height
		_path_points.append(safe_pos)
		_path_mesh.update_from_points(_path_points)
		print("[PathDrawer] Path stopped at wall")
		_finish_drawing()
		return

	_path_points.append(pos)
	_path_mesh.update_from_points(_path_points)


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
	_clear_run_markers()
	# マルチキャラクターモードもクリア
	_clear_multi_character_markers()


func _clear_vision_points() -> void:
	_vision_points.clear()
	for mesh in _vision_meshes:
		mesh.queue_free()
	_vision_meshes.clear()


func _clear_run_markers() -> void:
	_run_segments.clear()
	_current_run_start = {}
	for mesh in _run_meshes:
		mesh.queue_free()
	_run_meshes.clear()


## 視線マーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_vision_markers() -> Array[MeshInstance3D]:
	var markers = _vision_meshes.duplicate()
	_vision_meshes.clear()
	return markers


## Runマーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_run_markers() -> Array[MeshInstance3D]:
	var markers = _run_meshes.duplicate()
	_run_meshes.clear()
	return markers


func get_drawn_path() -> PackedVector3Array:
	return _path_points


## 基準位置からの相対パスを取得
## 各キャラクターの開始位置にオフセットして使用可能
func get_relative_path() -> PackedVector3Array:
	if _pending_path.size() < 2:
		return PackedVector3Array()
	var start = _pending_path[0]
	var relative = PackedVector3Array()
	for point in _pending_path:
		relative.append(point - start)
	return relative


## 相対視線ポイントを取得（アンカー位置を相対座標に変換）
func get_relative_vision_points() -> Array[Dictionary]:
	if _pending_path.size() < 2:
		return []
	var start = _pending_path[0]
	var relative_points: Array[Dictionary] = []
	for vp in _vision_points:
		relative_points.append({
			"path_ratio": vp.path_ratio,
			"anchor": vp.anchor - start,  # 相対座標に変換
			"direction": vp.direction  # 方向はそのまま
		})
	return relative_points


func is_drawing() -> bool:
	return _is_drawing or _is_drawing_vision


func set_line_color(color: Color) -> void:
	line_color = color
	if _path_mesh:
		_path_mesh.set_line_color(color)


## キャラクター色を設定（パス線・マーカーに適用）
## @param color: キャラクター固有色
func set_character_color(color: Color) -> void:
	_character_color = color
	# パス線の色も更新
	set_line_color(Color(color.r, color.g, color.b, 0.9))


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


## 視線ポイント数を取得（マルチモードの場合はアクティブキャラクターのカウント）
func get_vision_point_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_vision_point_count_for_character(_active_edit_character)
	return _vision_points.size()


## 最後の視線ポイントを削除
func remove_last_vision_point() -> void:
	# マルチキャラクターモードの場合、アクティブキャラクターのデータから削除
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.vision_points.size() > 0:
				char_data.vision_points.pop_back()
				if char_data.vision_meshes.size() > 0:
					var mesh = char_data.vision_meshes.pop_back()
					mesh.queue_free()
				print("[PathDrawer] Last vision point removed for %s" % _active_edit_character.name)
		return

	# シングルモード
	if _vision_points.size() > 0:
		_vision_points.pop_back()
		if _vision_meshes.size() > 0:
			var mesh = _vision_meshes.pop_back()
			mesh.queue_free()
		print("[PathDrawer] Last vision point removed")


## ========================================
## Runマーカーモード API
## ========================================

## Runマーカー設定モードに切り替え
func start_run_mode() -> bool:
	if _pending_path.size() < 2:
		print("[PathDrawer] Cannot start run mode: no movement path set")
		return false

	_drawing_mode = DrawingMode.RUN_MARKER
	_is_enabled = true
	_current_run_start = {}  # 未完成の開始点をクリア
	mode_changed.emit(int(DrawingMode.RUN_MARKER))
	print("[PathDrawer] Switched to run marker mode - click to set run start/end points")
	return true


## Run区間があるか
func has_run_segments() -> bool:
	return _run_segments.size() > 0


## Run区間を取得
func get_run_segments() -> Array[Dictionary]:
	return _run_segments


## Run区間数を取得（マルチモードの場合はアクティブキャラクターのカウント）
func get_run_segment_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_run_segment_count_for_character(_active_edit_character)
	return _run_segments.size()


## 最後のRun区間を削除
func remove_last_run_segment() -> void:
	# マルチキャラクターモードの場合、アクティブキャラクターのデータから削除
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.run_segments.size() > 0:
				char_data.run_segments.pop_back()
				# 終点マーカーを削除
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
				# 開始点マーカーも削除
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
				print("[PathDrawer] Last run segment removed for %s" % _active_edit_character.name)
			elif not _current_run_start.is_empty():
				# 未完成の開始点がある場合はそれを削除
				_current_run_start = {}
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
				print("[PathDrawer] Incomplete run start point removed for %s" % _active_edit_character.name)
		return

	# シングルモード
	if _run_segments.size() > 0:
		_run_segments.pop_back()
		# 終点マーカーを削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		# 開始点マーカーも削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		print("[PathDrawer] Last run segment removed")
	elif not _current_run_start.is_empty():
		# 未完成の開始点がある場合はそれを削除
		_current_run_start = {}
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		print("[PathDrawer] Incomplete run start point removed")


## 未完成のRun開始点があるか
func has_incomplete_run_start() -> bool:
	return not _current_run_start.is_empty()


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
	_clear_run_markers()


func _on_path_completed() -> void:
	if _executing_character:
		if _executing_character.path_completed.is_connected(_on_path_completed):
			_executing_character.path_completed.disconnect(_on_path_completed)
		_executing_character = null

	clear()
	print("[PathDrawer] Path execution completed")


## ========================================
## マルチキャラクターマーカー管理 API
## ========================================

## マルチキャラクターモードを開始
## @param characters: 対象キャラクター配列
func start_multi_character_mode(characters: Array[Node]) -> void:
	_multi_character_mode = true
	_character_markers.clear()

	# 各キャラクター用のマーカーストレージを初期化
	for character in characters:
		var char_id = character.get_instance_id()
		_character_markers[char_id] = {
			"character": character,
			"vision_points": [] as Array[Dictionary],
			"vision_meshes": [] as Array[MeshInstance3D],
			"run_segments": [] as Array[Dictionary],
			"run_meshes": [] as Array[MeshInstance3D]
		}

	# 最初のキャラクターをアクティブに設定
	if characters.size() > 0:
		set_active_edit_character(characters[0])

	print("[PathDrawer] Multi-character mode started with %d characters" % characters.size())


## マルチキャラクターモードを終了
func end_multi_character_mode() -> void:
	_multi_character_mode = false
	_active_edit_character = null
	# マーカーデータはclear時にクリーンアップ
	print("[PathDrawer] Multi-character mode ended")


## 編集対象キャラクターを設定
## @param character: 編集対象キャラクター
func set_active_edit_character(character: Node) -> void:
	if not _multi_character_mode:
		_active_edit_character = character
		return

	if not character:
		return

	var char_id = character.get_instance_id()
	if not _character_markers.has(char_id):
		print("[PathDrawer] Character not in multi-character mode: %s" % character.name)
		return

	_active_edit_character = character

	# キャラクター色を適用
	var char_color = CharacterColorManager.get_character_color(character)
	_character_color = char_color

	print("[PathDrawer] Active edit character: %s" % character.name)


## アクティブな編集キャラクターを取得
func get_active_edit_character() -> Node:
	return _active_edit_character


## マルチキャラクターモードかどうか
func is_multi_character_mode() -> bool:
	return _multi_character_mode


## キャラクター別の視線ポイント数を取得
func get_vision_point_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].vision_points.size()
	return 0


## キャラクター別のRun区間数を取得
func get_run_segment_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].run_segments.size()
	return 0


## キャラクター別の視線ポイントを取得
func get_vision_points_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].vision_points
	return []


## キャラクター別のRun区間を取得
func get_run_segments_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].run_segments
	return []


## 全キャラクターの視線ポイントを取得
## @return { char_id: Array[Dictionary] }
func get_all_vision_points() -> Dictionary:
	if not _multi_character_mode:
		# シングルモードの場合、現在のキャラクターIDで返す
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _vision_points }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].vision_points
	return result


## 全キャラクターのRun区間を取得
## @return { char_id: Array[Dictionary] }
func get_all_run_segments() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _run_segments }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].run_segments
	return result


## マルチキャラクターモードで全マーカーをクリア
func _clear_multi_character_markers() -> void:
	for char_id in _character_markers:
		var data = _character_markers[char_id]
		for mesh in data.vision_meshes:
			if is_instance_valid(mesh):
				mesh.queue_free()
		for mesh in data.run_meshes:
			if is_instance_valid(mesh):
				mesh.queue_free()
	_character_markers.clear()
	_active_edit_character = null
	_multi_character_mode = false


## 全キャラクターのVisionMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_vision_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _vision_meshes.duplicate()
			_vision_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].vision_meshes.duplicate()
		_character_markers[char_id].vision_meshes.clear()
	return result


## 全キャラクターのRunMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_run_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _run_meshes.duplicate()
			_run_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].run_meshes.duplicate()
		_character_markers[char_id].run_meshes.clear()
	return result
