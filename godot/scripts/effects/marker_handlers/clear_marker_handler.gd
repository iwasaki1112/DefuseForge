class_name ClearMarkerHandler
extends MarkerHandlerBase

## Clearマーカーハンドラ
## パス上のClearポイント（Vision/Runリセット地点）を管理するマーカーの入力・管理を担当


const ClearMarkerScript = preload("res://scripts/effects/clear_marker.gd")


## Clearポイントデータ配列
var _clear_points: Array[Dictionary] = []

## Clearマーカーメッシュ配列
var _clear_meshes: Array[MeshInstance3D] = []


## 入力処理
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			return _handle_click(mouse_event.position)

	return false


## クリック処理
func _handle_click(screen_pos: Vector2) -> bool:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos == null:
		return false

	var result = _find_closest_point_on_path(ground_pos)
	if result.distance > _get_path_click_threshold():
		return false

	# Clearポイントを追加（path_ratio順にソート）
	var new_point = { "path_ratio": result.ratio }

	var insert_idx = 0
	for i in range(_clear_points.size()):
		if _clear_points[i].path_ratio > result.ratio:
			break
		insert_idx = i + 1

	_clear_points.insert(insert_idx, new_point)

	# マーカーを作成
	var marker = _create_clear_marker_node(result.point)
	_clear_meshes.insert(insert_idx, marker)

	marker_added.emit(new_point)
	_notify_timeline_changed()
	return true


## Clearマーカーノード作成
func _create_clear_marker_node(pos: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(ClearMarkerScript)
	_add_child_to_drawer(marker)
	marker.set_marker_position(pos)
	marker.set_colors(_character_color, Color.WHITE)
	return marker


func has_markers() -> bool:
	return _clear_points.size() > 0


func get_marker_count() -> int:
	return _clear_points.size()


func get_markers() -> Array[Dictionary]:
	return _clear_points


func take_markers() -> Array[MeshInstance3D]:
	var markers = _clear_meshes.duplicate()
	_clear_meshes.clear()
	return markers


func undo_last() -> Dictionary:
	if _clear_points.size() == 0:
		return {}

	var removed_data = _clear_points.pop_back()
	if _clear_meshes.size() > 0:
		var mesh = _clear_meshes.pop_back()
		mesh.queue_free()

	return removed_data


func clear_all() -> void:
	_clear_points.clear()
	for mesh in _clear_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_clear_meshes.clear()
