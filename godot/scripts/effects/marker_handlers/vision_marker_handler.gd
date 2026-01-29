class_name VisionMarkerHandler
extends MarkerHandlerBase

## 視線マーカーハンドラ
## パス上の任意の点から視線方向を設定するマーカーの入力・管理を担当


const VisionMarkerScript = preload("res://scripts/effects/vision_marker.gd")


## 視線ポイントデータ配列
var _vision_points: Array[Dictionary] = []

## 視線マーカーメッシュ配列
var _vision_meshes: Array[MeshInstance3D] = []

## 現在の視線アンカー位置
var _current_anchor: Vector3 = Vector3.ZERO

## 現在の視線比率
var _current_ratio: float = 0.0

## 視線描画中フラグ
var _is_drawing: bool = false


## 入力処理
func handle_input(event: InputEvent) -> bool:
	# マウス入力
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				return _handle_press(mouse_event.position)
			else:
				return _handle_release(mouse_event.position)

	if event is InputEventMouseMotion:
		if _is_drawing:
			_handle_motion(event.position)
			return true

	# タッチ入力
	if event is InputEventScreenTouch:
		if event.pressed:
			return _handle_press(event.position)
		else:
			return _handle_release(event.position)

	if event is InputEventScreenDrag:
		if _is_drawing:
			_handle_motion(event.position)
			return true

	return false


## マウス押下処理
func _handle_press(screen_pos: Vector2) -> bool:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos == null:
		return false

	var result = _find_closest_point_on_path(ground_pos)
	if result.distance > _get_path_click_threshold():
		return false

	_current_anchor = result.point
	_current_ratio = result.ratio
	_is_drawing = true
	return true


## マウス解放処理
func _handle_release(screen_pos: Vector2) -> bool:
	if not _is_drawing:
		return false

	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos != null:
		_finish_vision_point(ground_pos)

	_is_drawing = false
	return true


## マウス移動処理
func _handle_motion(screen_pos: Vector2) -> void:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos != null:
		_update_temp_marker(_current_anchor, ground_pos)


## 視線ポイント設定完了
func _finish_vision_point(end_pos: Vector3) -> void:
	var target_point = end_pos
	target_point.y = 0

	var direction = (target_point - _current_anchor)
	direction.y = 0

	if direction.length_squared() < 0.001:
		_remove_temp_marker()
		return

	_remove_temp_marker()

	# 挿入位置を見つける（path_ratio順にソート）
	var insert_idx = 0
	for i in range(_vision_points.size()):
		if _vision_points[i].path_ratio > _current_ratio:
			break
		insert_idx = i + 1

	# 視線ポイントを追加
	var new_point = {
		"path_ratio": _current_ratio,
		"anchor": _current_anchor,
		"target_point": target_point
	}
	_vision_points.insert(insert_idx, new_point)

	# マーカーを作成
	var marker = _create_vision_marker_node(_current_anchor, target_point)
	_vision_meshes.insert(insert_idx, marker)

	marker_added.emit(new_point)


## 視線マーカーノード作成
func _create_vision_marker_node(anchor: Vector3, target_point: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(VisionMarkerScript)
	_add_child_to_drawer(marker)
	marker.set_position_and_target(anchor, target_point)
	marker.set_colors(_character_color, Color.WHITE)
	marker.set_target_line_color(Color(_character_color.r, _character_color.g * 0.7, _character_color.b * 0.5, 0.8))
	return marker


## 一時マーカー更新
func _update_temp_marker(anchor: Vector3, target_point: Vector3) -> void:
	if _vision_meshes.size() > _vision_points.size():
		var temp_marker = _vision_meshes[-1]
		temp_marker.set_position_and_target(anchor, target_point)
	else:
		var marker = MeshInstance3D.new()
		marker.set_script(VisionMarkerScript)
		_add_child_to_drawer(marker)
		_vision_meshes.append(marker)
		marker.set_position_and_target(anchor, target_point)
		marker.set_colors(_character_color, Color.WHITE)
		marker.set_target_line_color(Color(_character_color.r, _character_color.g * 0.7, _character_color.b * 0.5, 0.8))


## 一時マーカー削除
func _remove_temp_marker() -> void:
	if _vision_meshes.size() > _vision_points.size():
		var temp_marker = _vision_meshes.pop_back()
		temp_marker.queue_free()


func has_markers() -> bool:
	return _vision_points.size() > 0


func get_marker_count() -> int:
	return _vision_points.size()


func get_markers() -> Array[Dictionary]:
	return _vision_points


func take_markers() -> Array[MeshInstance3D]:
	var markers = _vision_meshes.duplicate()
	_vision_meshes.clear()
	return markers


func undo_last() -> Dictionary:
	if _vision_points.size() == 0:
		return {}

	var removed_data = _vision_points.pop_back()
	if _vision_meshes.size() > 0:
		var mesh = _vision_meshes.pop_back()
		mesh.queue_free()

	return removed_data


func clear_all() -> void:
	_vision_points.clear()
	for mesh in _vision_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_vision_meshes.clear()


func reset_state() -> void:
	_is_drawing = false
	_current_anchor = Vector3.ZERO
	_current_ratio = 0.0
	_remove_temp_marker()


## マーカーを復元
func restore_markers(data: Array, meshes: Array) -> void:
	for d in data:
		_vision_points.append(d)
	for m in meshes:
		if is_instance_valid(m):
			_add_child_to_drawer(m)
			_vision_meshes.append(m)
