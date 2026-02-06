class_name PointCollection
extends RefCounted

## ポイントコレクション
## 複数種類のポイントを統一的に管理するクラス

## ポイントが変更された時のシグナル（追加・削除・クリア時に発火）
signal point_changed()

## ポイントデータ（タイプ別）
## { Type: Array[ActionPointData] }
var _points_by_type: Dictionary = {}

## ポイントメッシュ（タイプ別）
## { Type: Array[MeshInstance3D] }
var _meshes_by_type: Dictionary = {}

## ポイント追加履歴（Undo用）
var _history: Array[int] = []  # ActionPointData.Type の配列


func _init() -> void:
	_init_type_arrays()


## タイプ別の配列を初期化
func _init_type_arrays() -> void:
	for type_value in ActionPointData.Type.values():
		_points_by_type[type_value] = []
		_meshes_by_type[type_value] = []


## ポイントを追加
func add_point(data: ActionPointData, mesh: MeshInstance3D = null) -> void:
	var type = data.type
	_points_by_type[type].append(data)
	if mesh:
		_meshes_by_type[type].append(mesh)
	_history.append(type)
	point_changed.emit()


## 指定タイプのポイントデータを取得
func get_points(type: ActionPointData.Type) -> Array:
	if _points_by_type.has(type):
		return _points_by_type[type]
	return []


## 指定タイプのポイントメッシュを取得
func get_meshes(type: ActionPointData.Type) -> Array:
	if _meshes_by_type.has(type):
		return _meshes_by_type[type]
	return []


## 指定タイプのポイントメッシュを取得して所有権を移譲
func take_meshes(type: ActionPointData.Type) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if _meshes_by_type.has(type):
		for mesh in _meshes_by_type[type]:
			result.append(mesh)
		_meshes_by_type[type] = []
	return result


## 全ポイントデータを取得
func get_all_points() -> Array:
	var result = []
	for type in _points_by_type:
		result.append_array(_points_by_type[type])
	return result


## 全ポイントメッシュを取得して所有権を移譲
func take_all_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for type in _meshes_by_type:
		for mesh in _meshes_by_type[type]:
			result.append(mesh)
		_meshes_by_type[type] = []
	return result


## 指定タイプのポイントをDictionary配列として取得（後方互換用）
func get_points_as_dicts(type: ActionPointData.Type) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point in get_points(type):
		result.append(point.to_dict())
	return result


## 最後に追加したポイントのタイプを取得
func get_last_point_type() -> int:
	if _history.is_empty():
		return -1
	return _history.back()


## 最後に追加したポイントを削除（Undo）
func undo_last_point() -> Dictionary:
	if _history.is_empty():
		return { "success": false }

	var type = _history.pop_back()
	var points = _points_by_type.get(type, [])
	var meshes = _meshes_by_type.get(type, [])

	if points.is_empty():
		return { "success": false, "type": type }

	var removed_point = points.pop_back()
	var removed_mesh: MeshInstance3D = null

	if not meshes.is_empty():
		removed_mesh = meshes.pop_back()

	point_changed.emit()
	return {
		"success": true,
		"type": type,
		"point": removed_point,
		"mesh": removed_mesh
	}


## 指定タイプのポイントをクリア
func clear_type(type: ActionPointData.Type) -> void:
	var had_points = not _points_by_type.get(type, []).is_empty()
	# メッシュを削除
	for mesh in _meshes_by_type.get(type, []):
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	_points_by_type[type] = []
	_meshes_by_type[type] = []
	# 履歴からも該当タイプを削除
	_history = _history.filter(func(t): return t != type)
	if had_points:
		point_changed.emit()


## 全ポイントをクリア
func clear_all() -> void:
	var had_points = get_total_point_count() > 0
	for type in _meshes_by_type:
		for mesh in _meshes_by_type[type]:
			if mesh and is_instance_valid(mesh):
				mesh.queue_free()
	_init_type_arrays()
	_history.clear()
	if had_points:
		point_changed.emit()


## ポイント数を取得
func get_point_count(type: ActionPointData.Type) -> int:
	return _points_by_type.get(type, []).size()


## 全ポイント数を取得
func get_total_point_count() -> int:
	var count = 0
	for type in _points_by_type:
		count += _points_by_type[type].size()
	return count


## 履歴が空かどうか
func is_history_empty() -> bool:
	return _history.is_empty()


## 履歴をクリア
func clear_history() -> void:
	_history.clear()


#region Vision専用メソッド（後方互換）
func get_vision_points() -> Array[Dictionary]:
	return get_points_as_dicts(ActionPointData.Type.VISION)

func take_vision_meshes() -> Array[MeshInstance3D]:
	return take_meshes(ActionPointData.Type.VISION)
#endregion


#region Wait専用メソッド（後方互換）
func get_wait_points() -> Array[Dictionary]:
	return get_points_as_dicts(ActionPointData.Type.WAIT)

func take_wait_meshes() -> Array[MeshInstance3D]:
	return take_meshes(ActionPointData.Type.WAIT)
#endregion
