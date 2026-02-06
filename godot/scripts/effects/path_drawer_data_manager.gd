class_name PathDrawerDataManager
extends RefCounted

## PathDrawerのデータ管理と外部API
## ポイント取得/転送、Undo、実行、復元などのデータ操作を担当

## PathDrawerへの参照（状態アクセス用）
var _drawer: PathDrawer = null


## セットアップ（PathDrawerから呼ばれる）
func setup(drawer: PathDrawer) -> void:
	_drawer = drawer


#region ポイント取得 API（ファサード）
func has_vision_points() -> bool:
	return _drawer._vision_handler.has_points()


func get_vision_points() -> Array[Dictionary]:
	return _drawer._vision_handler.get_points()


func get_vision_point_count() -> int:
	return _drawer._vision_handler.get_point_count()


func take_vision_points() -> Array[MeshInstance3D]:
	return _drawer._vision_handler.take_points()


func has_wait_points() -> bool:
	return _drawer._wait_handler.has_points()


func get_wait_points() -> Array[Dictionary]:
	return _drawer._wait_handler.get_points()


func get_wait_point_count() -> int:
	return _drawer._wait_handler.get_point_count()


func take_wait_points() -> Array[MeshInstance3D]:
	return _drawer._wait_handler.take_points()


## Visionポイントメッシュを指定親ノードに転送（データもクリア）
## @param parent: 転送先の親ノード
## @return: 転送されたメッシュの配列
func transfer_vision_meshes_to(parent: Node3D) -> Array[MeshInstance3D]:
	return _drawer._vision_handler.transfer_meshes_to(parent)


## Waitポイントメッシュを指定親ノードに転送（データもクリア）
## @param parent: 転送先の親ノード
## @return: 転送されたメッシュの配列
func transfer_wait_meshes_to(parent: Node3D) -> Array[MeshInstance3D]:
	return _drawer._wait_handler.transfer_meshes_to(parent)
#endregion


#region 全キャラクター用 API（後方互換）
func get_all_vision_points() -> Dictionary:
	if _drawer._active_edit_character:
		return { _drawer._active_edit_character.get_instance_id(): get_vision_points() }
	return {}


func get_all_wait_points() -> Dictionary:
	if _drawer._active_edit_character:
		return { _drawer._active_edit_character.get_instance_id(): get_wait_points() }
	return {}


func take_all_vision_points() -> Dictionary:
	if _drawer._active_edit_character:
		return { _drawer._active_edit_character.get_instance_id(): take_vision_points() }
	return {}


func take_all_wait_points() -> Dictionary:
	if _drawer._active_edit_character:
		return { _drawer._active_edit_character.get_instance_id(): take_wait_points() }
	return {}
#endregion


#region 統一ポイント API
func get_points_by_type(point_type: ActionPointData.Type) -> Array[Dictionary]:
	match point_type:
		ActionPointData.Type.VISION:
			return get_vision_points()
		ActionPointData.Type.WAIT:
			return get_wait_points()
		_:
			return []


func take_points_by_type(point_type: ActionPointData.Type) -> Array[MeshInstance3D]:
	match point_type:
		ActionPointData.Type.VISION:
			return take_vision_points()
		ActionPointData.Type.WAIT:
			return take_wait_points()
		_:
			return []


func get_all_points_by_type(point_type: ActionPointData.Type) -> Dictionary:
	match point_type:
		ActionPointData.Type.VISION:
			return get_all_vision_points()
		ActionPointData.Type.WAIT:
			return get_all_wait_points()
		_:
			return {}


func take_all_points_by_type(point_type: ActionPointData.Type) -> Dictionary:
	match point_type:
		ActionPointData.Type.VISION:
			return take_all_vision_points()
		ActionPointData.Type.WAIT:
			return take_all_wait_points()
		_:
			return {}


func get_all_point_types_data() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionPointData.Type.values():
		result[type_value] = get_points_by_type(type_value)
	return result


func take_all_point_types_meshes() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionPointData.Type.values():
		result[type_value] = take_points_by_type(type_value)
	return result
#endregion


#region Undo API
func undo_last_point() -> int:
	if _drawer._point_history.is_empty():
		return -1

	var last_type = _drawer._point_history.pop_back()

	match last_type:
		PathDrawer.PointType.VISION:
			_drawer._vision_handler.undo_last()
		PathDrawer.PointType.WAIT:
			_drawer._wait_handler.undo_last()
		PathDrawer.PointType.PATH:
			_undo_path()

	return last_type


func _undo_path() -> void:
	_drawer._path_points.clear()
	_drawer._path_mesh.clear()
	_drawer._is_drawing = false
	_drawer._drawing_mode = PathDrawer.DrawingMode.MOVEMENT

	# 全ハンドラをクリア
	for handler in _drawer._get_all_handlers():
		handler.clear_all()

	_drawer._point_history.clear()

	_drawer.path_undone.emit()


func remove_last_vision_point() -> void:
	_drawer._vision_handler.undo_last()
#endregion


#region 実行 API
func execute(run: bool = false) -> bool:
	if _drawer._path_points.size() < 2 or _drawer._character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _drawer._path_points:
		path_array.append(point)
	_drawer._character.set_path(path_array, run)

	_drawer._executing_character = _drawer._character

	if not _drawer._executing_character.path_completed.is_connected(_on_path_completed):
		_drawer._executing_character.path_completed.connect(_on_path_completed)

	_drawer._path_points.clear()
	_drawer._character = null

	return true


func execute_with_vision(run: bool = false) -> bool:
	if _drawer._path_points.size() < 2 or _drawer._character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _drawer._path_points:
		path_array.append(point)

	var vision_points = get_vision_points()
	if vision_points.size() > 0:
		_drawer._character.set_path_with_vision_points(path_array, vision_points.duplicate(), run)
	else:
		_drawer._character.set_path(path_array, run)

	_drawer._executing_character = _drawer._character

	if not _drawer._executing_character.path_completed.is_connected(_on_path_completed):
		_drawer._executing_character.path_completed.connect(_on_path_completed)

	_drawer._path_points.clear()
	_drawer._character = null

	return true


func _on_path_completed() -> void:
	if _drawer._executing_character:
		if _drawer._executing_character.path_completed.is_connected(_on_path_completed):
			_drawer._executing_character.path_completed.disconnect(_on_path_completed)
		_drawer._executing_character = null

	_drawer.clear()
#endregion


#region パスデータ取得
func get_relative_path() -> PackedVector3Array:
	if _drawer._path_points.size() < 2:
		return PackedVector3Array()
	var start = _drawer._path_points[0]
	var relative = PackedVector3Array()
	for point in _drawer._path_points:
		relative.append(point - start)
	return relative


func get_relative_vision_points() -> Array[Dictionary]:
	if _drawer._path_points.size() < 2:
		return []
	var start = _drawer._path_points[0]
	var relative_points: Array[Dictionary] = []
	for vp in get_vision_points():
		relative_points.append({
			"path_ratio": vp.path_ratio,
			"anchor": vp.anchor - start,
			"target_point": vp.target_point - start
		})
	return relative_points
#endregion


#region 復元 API
func restore_path_points(character: Node3D, path_data: Dictionary) -> bool:
	if path_data.is_empty():
		return false

	_drawer.clear()

	_drawer._character = character
	_drawer._is_enabled = true
	_drawer._drawing_mode = PathDrawer.DrawingMode.MOVEMENT
	_drawer._character = character as CharacterBody3D

	if path_data.has("path"):
		_drawer._path_points.clear()
		for point in path_data["path"]:
			_drawer._path_points.append(point)
		_drawer._path_points = _drawer._path_points.duplicate()
	if _drawer._path_points.size() < 2:
		return false

	if _drawer._path_mesh and _drawer._path_points.size() > 0:
		_drawer._path_mesh.update_from_points(_drawer._path_points)

	if path_data.has("path_mesh") and is_instance_valid(path_data["path_mesh"]):
		path_data["path_mesh"].queue_free()

	_drawer._point_history.append(PathDrawer.PointType.PATH)

	# ポイントをハンドラに復元
	_restore_all_points(path_data)

	_drawer.call_deferred("_emit_drawing_finished_after_restore")
	return true


## 全ポイントをハンドラに復元
func _restore_all_points(path_data: Dictionary) -> void:
	# Vision points
	var vision_data = path_data.get("vision_points_data", [])
	var vision_meshes = path_data.get("vision_points", [])
	if vision_data.size() > 0:
		_drawer._vision_handler.restore_points(vision_data, vision_meshes)
		for _i in range(vision_data.size()):
			_drawer._point_history.append(PathDrawer.PointType.VISION)

	# Wait points
	var wait_data = path_data.get("wait_points_data", [])
	var wait_meshes = path_data.get("wait_points", [])
	if wait_data.size() > 0:
		_drawer._wait_handler.restore_points(wait_data, wait_meshes)
		for _i in range(wait_data.size()):
			_drawer._point_history.append(PathDrawer.PointType.WAIT)


#endregion
