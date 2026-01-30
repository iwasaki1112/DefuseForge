class_name ClearPointHandler
extends PointHandlerBase

## Clearポイントハンドラ
## パス上のClearポイント（Vision/Runリセット地点）を管理するポイントの入力・管理を担当


const ClearPointScript = preload("res://scripts/effects/clear_point.gd")


## Clearポイントデータ配列
var _clear_points: Array[Dictionary] = []

## Clearポイントメッシュ配列
var _clear_meshes: Array[MeshInstance3D] = []


## 入力処理
func handle_input(event: InputEvent) -> bool:
	# マウス入力
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			return _handle_click(mouse_event.position)

	# タッチ入力
	if event is InputEventScreenTouch and event.pressed:
		return _handle_click(event.position)

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

	# ポイントを作成
	var point = _create_clear_point_node(result.point)
	_clear_meshes.insert(insert_idx, point)

	point_added.emit(new_point)
	return true


## Clearポイントノード作成
func _create_clear_point_node(pos: Vector3) -> MeshInstance3D:
	var point = MeshInstance3D.new()
	point.set_script(ClearPointScript)
	_add_child_to_drawer(point)
	point.set_point_position(pos)
	point.set_colors(_character_color, Color.WHITE)
	return point


func has_points() -> bool:
	return _clear_points.size() > 0


func get_point_count() -> int:
	return _clear_points.size()


func get_points() -> Array[Dictionary]:
	return _clear_points


func take_points() -> Array[MeshInstance3D]:
	var points = _clear_meshes.duplicate()
	_clear_meshes.clear()
	return points


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


## ポイントを復元
func restore_points(data: Array, meshes: Array) -> void:
	for d in data:
		_clear_points.append(d)
	for m in meshes:
		if is_instance_valid(m):
			_add_child_to_drawer(m)
			_clear_meshes.append(m)
