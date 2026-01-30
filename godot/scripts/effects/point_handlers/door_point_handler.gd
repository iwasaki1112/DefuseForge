class_name DoorPointHandler
extends PointHandlerBase

## ドアポイントハンドラ
## パス上のドアキック位置を管理するポイントの入力・管理を担当


const DoorPointScript = preload("res://scripts/effects/door_point.gd")

## ドア近接判定距離
const DOOR_PROXIMITY_THRESHOLD: float = 0.6
## ドアキックオフセット距離
const DOOR_KICK_OFFSET: float = 0.6


## ドアポイントデータ配列
var _door_points: Array[Dictionary] = []

## ドアポイントメッシュ配列
var _door_meshes: Array[MeshInstance3D] = []


## 入力処理
func handle_input(event: InputEvent) -> bool:
	# マウス入力
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			return _process_door_click(mouse_event.position)

	# タッチ入力
	if event is InputEventScreenTouch and event.pressed:
		return _process_door_click(event.position)

	return false


## ドアクリック処理
func _process_door_click(screen_pos: Vector2) -> bool:
	# ドアをレイキャストで検出
	var door = _raycast_door(screen_pos)
	if not door:
		return false

	# ドア位置からパス上の最近点を計算
	var door_pos = door.global_position
	door_pos.y = 0
	var result = _find_closest_point_on_path(door_pos)

	# パスから遠すぎる場合はキャンセル
	if result.distance > DOOR_PROXIMITY_THRESHOLD:
		return false

	# ドアから離れた位置にポイントを配置（キック距離を確保）
	var offset_result = _find_offset_point_on_path(result.ratio, -DOOR_KICK_OFFSET)

	var new_point = {
		"path_ratio": offset_result.ratio,
		"anchor": offset_result.point,
		"door_node": door
	}

	_door_points.append(new_point)

	# ポイントメッシュを作成
	var point = _create_door_point_node(offset_result.point, door)
	_door_meshes.append(point)

	point_added.emit(new_point)
	return true


## ドアポイントノード作成
func _create_door_point_node(anchor: Vector3, door: Node3D) -> MeshInstance3D:
	var point = MeshInstance3D.new()
	point.set_script(DoorPointScript)
	_add_child_to_drawer(point)
	point.set_position_and_door(anchor, door)
	point.set_colors(_character_color, Color(0.8, 0.6, 0.3, 1.0))
	point.set_connection_color(Color(_character_color.r * 0.8, _character_color.g * 0.6, _character_color.b * 0.3, 0.8))
	return point


func has_points() -> bool:
	return _door_points.size() > 0


func get_point_count() -> int:
	return _door_points.size()


func get_points() -> Array[Dictionary]:
	return _door_points


func take_points() -> Array[MeshInstance3D]:
	var points = _door_meshes.duplicate()
	_door_meshes.clear()
	return points


func undo_last() -> Dictionary:
	if _door_points.size() == 0:
		return {}

	var removed_data = _door_points.pop_back()
	if _door_meshes.size() > 0:
		var mesh = _door_meshes.pop_back()
		if is_instance_valid(mesh):
			mesh.queue_free()

	return removed_data


func clear_all() -> void:
	_door_points.clear()
	for mesh in _door_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_door_meshes.clear()


## ポイントを復元
func restore_points(data: Array, meshes: Array) -> void:
	for d in data:
		_door_points.append(d)
	for m in meshes:
		if is_instance_valid(m):
			_add_child_to_drawer(m)
			_door_meshes.append(m)
