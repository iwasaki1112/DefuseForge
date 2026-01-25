class_name MarkerCollection
extends RefCounted

## マーカーコレクション
## 複数種類のマーカーを統一的に管理するクラス

## マーカーが変更された時のシグナル（追加・削除・クリア時に発火）
signal marker_changed()

const ActionMarkerDataScript = preload("res://scripts/effects/action_marker_data.gd")

## マーカーデータ（タイプ別）
## { Type: Array[ActionMarkerData] }
var _markers_by_type: Dictionary = {}

## マーカーメッシュ（タイプ別）
## { Type: Array[MeshInstance3D] }
var _meshes_by_type: Dictionary = {}

## マーカー追加履歴（Undo用）
var _history: Array[int] = []  # ActionMarkerData.Type の配列


func _init() -> void:
	_init_type_arrays()


## タイプ別の配列を初期化
func _init_type_arrays() -> void:
	for type_value in ActionMarkerDataScript.Type.values():
		_markers_by_type[type_value] = []
		_meshes_by_type[type_value] = []


## マーカーを追加
func add_marker(data: ActionMarkerDataScript, mesh: MeshInstance3D = null) -> void:
	var type = data.type
	_markers_by_type[type].append(data)
	if mesh:
		_meshes_by_type[type].append(mesh)
	_history.append(type)
	marker_changed.emit()


## 指定タイプのマーカーデータを取得
func get_markers(type: ActionMarkerDataScript.Type) -> Array:
	if _markers_by_type.has(type):
		return _markers_by_type[type]
	return []


## 指定タイプのマーカーメッシュを取得
func get_meshes(type: ActionMarkerDataScript.Type) -> Array:
	if _meshes_by_type.has(type):
		return _meshes_by_type[type]
	return []


## 指定タイプのマーカーメッシュを取得して所有権を移譲
func take_meshes(type: ActionMarkerDataScript.Type) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if _meshes_by_type.has(type):
		for mesh in _meshes_by_type[type]:
			result.append(mesh)
		_meshes_by_type[type] = []
	return result


## 全マーカーデータを取得
func get_all_markers() -> Array:
	var result = []
	for type in _markers_by_type:
		result.append_array(_markers_by_type[type])
	return result


## 全マーカーメッシュを取得して所有権を移譲
func take_all_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for type in _meshes_by_type:
		for mesh in _meshes_by_type[type]:
			result.append(mesh)
		_meshes_by_type[type] = []
	return result


## 指定タイプのマーカーをDictionary配列として取得（後方互換用）
func get_markers_as_dicts(type: ActionMarkerDataScript.Type) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker in get_markers(type):
		result.append(marker.to_dict())
	return result


## 最後に追加したマーカーのタイプを取得
func get_last_marker_type() -> int:
	if _history.is_empty():
		return -1
	return _history.back()


## 最後に追加したマーカーを削除（Undo）
func undo_last_marker() -> Dictionary:
	if _history.is_empty():
		return { "success": false }

	var type = _history.pop_back()
	var markers = _markers_by_type.get(type, [])
	var meshes = _meshes_by_type.get(type, [])

	if markers.is_empty():
		return { "success": false, "type": type }

	var removed_marker = markers.pop_back()
	var removed_mesh: MeshInstance3D = null

	if not meshes.is_empty():
		removed_mesh = meshes.pop_back()

	marker_changed.emit()
	return {
		"success": true,
		"type": type,
		"marker": removed_marker,
		"mesh": removed_mesh
	}


## 指定タイプのマーカーをクリア
func clear_type(type: ActionMarkerDataScript.Type) -> void:
	var had_markers = not _markers_by_type.get(type, []).is_empty()
	# メッシュを削除
	for mesh in _meshes_by_type.get(type, []):
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	_markers_by_type[type] = []
	_meshes_by_type[type] = []
	# 履歴からも該当タイプを削除
	_history = _history.filter(func(t): return t != type)
	if had_markers:
		marker_changed.emit()


## 全マーカーをクリア
func clear_all() -> void:
	var had_markers = get_total_marker_count() > 0
	for type in _meshes_by_type:
		for mesh in _meshes_by_type[type]:
			if mesh and is_instance_valid(mesh):
				mesh.queue_free()
	_init_type_arrays()
	_history.clear()
	if had_markers:
		marker_changed.emit()


## マーカー数を取得
func get_marker_count(type: ActionMarkerDataScript.Type) -> int:
	return _markers_by_type.get(type, []).size()


## 全マーカー数を取得
func get_total_marker_count() -> int:
	var count = 0
	for type in _markers_by_type:
		count += _markers_by_type[type].size()
	return count


## 履歴が空かどうか
func is_history_empty() -> bool:
	return _history.is_empty()


## 履歴をクリア
func clear_history() -> void:
	_history.clear()


#region Vision専用メソッド（後方互換）
func get_vision_points() -> Array[Dictionary]:
	return get_markers_as_dicts(ActionMarkerDataScript.Type.VISION)

func take_vision_meshes() -> Array[MeshInstance3D]:
	return take_meshes(ActionMarkerDataScript.Type.VISION)
#endregion


#region Run専用メソッド（後方互換）
func get_run_segments() -> Array[Dictionary]:
	return get_markers_as_dicts(ActionMarkerDataScript.Type.RUN)

func take_run_meshes() -> Array[MeshInstance3D]:
	return take_meshes(ActionMarkerDataScript.Type.RUN)
#endregion


#region Clear専用メソッド（後方互換）
func get_clear_points() -> Array[Dictionary]:
	return get_markers_as_dicts(ActionMarkerDataScript.Type.CLEAR)

func take_clear_meshes() -> Array[MeshInstance3D]:
	return take_meshes(ActionMarkerDataScript.Type.CLEAR)
#endregion


#region Grenade専用メソッド（後方互換）
func get_grenade_markers() -> Array[Dictionary]:
	return get_markers_as_dicts(ActionMarkerDataScript.Type.GRENADE)

func take_grenade_meshes() -> Array[MeshInstance3D]:
	return take_meshes(ActionMarkerDataScript.Type.GRENADE)
#endregion


#region Door専用メソッド（後方互換）
func get_door_markers() -> Array[Dictionary]:
	return get_markers_as_dicts(ActionMarkerDataScript.Type.DOOR)

func take_door_meshes() -> Array[MeshInstance3D]:
	return take_meshes(ActionMarkerDataScript.Type.DOOR)
#endregion
