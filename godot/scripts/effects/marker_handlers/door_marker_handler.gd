class_name DoorMarkerHandler
extends MarkerHandlerBase

## ドアマーカーハンドラ
## パス上のドアキック位置を管理するマーカーの入力・管理を担当


const DoorMarkerScript = preload("res://scripts/effects/door_marker.gd")

## ドア近接判定距離
const DOOR_PROXIMITY_THRESHOLD: float = 0.6
## ドアキックオフセット距離
const DOOR_KICK_OFFSET: float = 0.6


## ドアマーカーデータ配列
var _door_markers: Array[Dictionary] = []

## ドアマーカーメッシュ配列
var _door_meshes: Array[MeshInstance3D] = []


## 入力処理
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			return _process_door_click(mouse_event.position)

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

	# ドアから離れた位置にマーカーを配置（キック距離を確保）
	var offset_result = _find_offset_point_on_path(result.ratio, -DOOR_KICK_OFFSET)

	var new_marker = {
		"path_ratio": offset_result.ratio,
		"anchor": offset_result.point,
		"door_node": door
	}

	_door_markers.append(new_marker)

	# マーカーメッシュを作成
	var marker = _create_door_marker_node(offset_result.point, door)
	_door_meshes.append(marker)

	marker_added.emit(new_marker)
	_notify_timeline_changed()
	return true


## ドアマーカーノード作成
func _create_door_marker_node(anchor: Vector3, door: Node3D) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(DoorMarkerScript)
	_add_child_to_drawer(marker)
	marker.set_position_and_door(anchor, door)
	marker.set_colors(_character_color, Color(0.8, 0.6, 0.3, 1.0))
	marker.set_connection_color(Color(_character_color.r * 0.8, _character_color.g * 0.6, _character_color.b * 0.3, 0.8))
	return marker


func has_markers() -> bool:
	return _door_markers.size() > 0


func get_marker_count() -> int:
	return _door_markers.size()


func get_markers() -> Array[Dictionary]:
	return _door_markers


func take_markers() -> Array[MeshInstance3D]:
	var markers = _door_meshes.duplicate()
	_door_meshes.clear()
	return markers


func undo_last() -> Dictionary:
	if _door_markers.size() == 0:
		return {}

	var removed_data = _door_markers.pop_back()
	if _door_meshes.size() > 0:
		var mesh = _door_meshes.pop_back()
		if is_instance_valid(mesh):
			mesh.queue_free()

	return removed_data


func clear_all() -> void:
	_door_markers.clear()
	for mesh in _door_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_door_meshes.clear()
