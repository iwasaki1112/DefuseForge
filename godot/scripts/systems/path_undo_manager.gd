class_name PathUndoManager
extends RefCounted
## パス操作のUndo履歴を管理するクラス

signal undo_state_changed(can_undo: bool)

## 操作タイプ
enum OperationType {
	PATH_START,      ## パス開始
	PATH_POINT,      ## パスポイント追加
	VISION_POINT,    ## Visionポイント追加
	WAIT_POINT,      ## Waitポイント追加
}

## 履歴スタック
var _undo_stack: Array = []

## 最大履歴数
const MAX_HISTORY: int = 100

## PathExecutionManagerへの参照（Undo処理に必要）
var _path_execution_manager: Node = null

## PathDrawerへの参照（Undo処理に必要）
var _path_drawer: Node = null


## セットアップ
func setup(path_execution_manager: Node, path_drawer: Node) -> void:
	_path_execution_manager = path_execution_manager
	_path_drawer = path_drawer


## 操作を履歴に追加
## @param operation: 操作タイプ
## @param character: 対象キャラクター
## @param data: 操作データ（操作タイプによって内容が異なる）
func push(operation: OperationType, character: Node, data: Dictionary) -> void:
	if not is_instance_valid(character):
		return

	var entry := {
		"type": operation,
		"character": character,
		"char_id": character.get_instance_id(),
		"data": data.duplicate()
	}

	_undo_stack.push_back(entry)

	# 最大履歴数を超えたら古いものを削除
	while _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()

	undo_state_changed.emit(can_undo())


## 最後の操作をUndo
## @return: Undoが成功した場合true
func undo() -> bool:
	if _undo_stack.is_empty():
		return false

	var entry: Dictionary = _undo_stack.pop_back()
	var character: Node = entry.get("character")
	var char_id: int = entry.get("char_id", 0)

	# キャラクターが無効な場合は次をUndo
	if not is_instance_valid(character):
		undo_state_changed.emit(can_undo())
		return undo()

	var success := false
	match entry.type:
		OperationType.PATH_START:
			success = _undo_path_start(character, char_id, entry.data)
		OperationType.PATH_POINT:
			success = _undo_path_point(character, char_id, entry.data)
		OperationType.VISION_POINT:
			success = _undo_vision_point(character, char_id, entry.data)
		OperationType.WAIT_POINT:
			success = _undo_wait_point(character, char_id, entry.data)

	undo_state_changed.emit(can_undo())
	return success


## Undo可能かどうか
func can_undo() -> bool:
	return not _undo_stack.is_empty()


## デバッグ: 現在のスタック状態を出力
func debug_print_stack() -> void:
	print("[UndoDebug] Stack size: %d" % _undo_stack.size())
	for i in range(_undo_stack.size()):
		var entry = _undo_stack[i]
		print("[UndoDebug]   [%d] type=%d, char_id=%d" % [i, entry.type, entry.char_id])


## 履歴をクリア
func clear() -> void:
	_undo_stack.clear()
	undo_state_changed.emit(false)


## 現在の履歴数を取得
func get_history_count() -> int:
	return _undo_stack.size()


## ========================================
## 各操作のUndo処理
## ========================================

## パス開始のUndo
## パス全体を削除
func _undo_path_start(character: Node, char_id: int, _data: Dictionary) -> bool:
	if not _path_execution_manager:
		return false

	# PathDrawerをクリア
	if _path_drawer:
		_path_drawer.clear()

	# pending_pathsからパスを削除
	if _path_execution_manager.has_method("clear_pending_path_for_character"):
		_path_execution_manager.clear_pending_path_for_character(character)
		return true

	# 内部メソッドを使用
	if _path_execution_manager.pending_paths.has(char_id):
		if _path_execution_manager.has_method("_free_pending_path_data"):
			_path_execution_manager._free_pending_path_data(_path_execution_manager.pending_paths[char_id])
		_path_execution_manager.pending_paths.erase(char_id)
		return true

	return false


## パスポイントのUndo
## 最後のポイントを削除
func _undo_path_point(character: Node, char_id: int, _data: Dictionary) -> bool:
	if not _path_execution_manager:
		return false

	if not _path_execution_manager.pending_paths.has(char_id):
		return false

	var path_data: Dictionary = _path_execution_manager.pending_paths[char_id]
	var path: Array = path_data.get("path", [])

	if path.size() <= 1:
		# パスが1ポイント以下になる場合はパス全体を削除
		return _undo_path_start(character, char_id, _data)

	# 最後のポイントを削除
	path.pop_back()
	path_data["path"] = path

	# パスメッシュを更新
	var path_mesh = path_data.get("path_mesh")
	if path_mesh and is_instance_valid(path_mesh):
		var packed_path := PackedVector3Array()
		for p in path:
			packed_path.append(p)
		if path.size() >= 2:
			path_mesh.update_from_points(packed_path)
		else:
			path_mesh.clear()

	# PathDrawerの内部状態も更新（描画中の場合）
	if _path_drawer and _path_drawer._path_points.size() > 1:
		_path_drawer._path_points.resize(_path_drawer._path_points.size() - 1)
		if _path_drawer._path_mesh:
			_path_drawer._path_mesh.update_from_points(_path_drawer._path_points)

	return true


## Visionポイントの Undo
## 最後のVisionポイントを削除
func _undo_vision_point(_character: Node, char_id: int, _data: Dictionary) -> bool:
	if not _path_execution_manager:
		if Debug.enabled: print("[UndoDebug] _undo_vision_point: no path_execution_manager")
		return false

	if not _path_execution_manager.pending_paths.has(char_id):
		if Debug.enabled: print("[UndoDebug] _undo_vision_point: no pending_path for char_id=%d" % char_id)
		return false

	var path_data: Dictionary = _path_execution_manager.pending_paths[char_id]

	# Visionポイントデータを削除
	var vision_data: Array = path_data.get("vision_points_data", [])
	if Debug.enabled: print("[UndoDebug] _undo_vision_point: vision_data size=%d" % vision_data.size())
	if not vision_data.is_empty():
		vision_data.pop_back()
		path_data["vision_points_data"] = vision_data

	# Visionポイントメッシュを削除
	var vision_meshes: Array = path_data.get("vision_points", [])
	if Debug.enabled: print("[UndoDebug] _undo_vision_point: vision_meshes size=%d" % vision_meshes.size())
	if not vision_meshes.is_empty():
		var mesh = vision_meshes.pop_back()
		if Debug.enabled: print("[UndoDebug] _undo_vision_point: mesh valid=%s" % str(is_instance_valid(mesh)))
		if is_instance_valid(mesh):
			mesh.queue_free()
		path_data["vision_points"] = vision_meshes
	else:
		if Debug.enabled: print("[UndoDebug] _undo_vision_point: vision_meshes is EMPTY!")

	return true


## Waitポイントの Undo
## 最後のWaitポイントを削除
func _undo_wait_point(_character: Node, char_id: int, _data: Dictionary) -> bool:
	if not _path_execution_manager:
		if Debug.enabled: print("[UndoDebug] _undo_wait_point: no path_execution_manager")
		return false

	if not _path_execution_manager.pending_paths.has(char_id):
		if Debug.enabled: print("[UndoDebug] _undo_wait_point: no pending_path for char_id=%d" % char_id)
		return false

	var path_data: Dictionary = _path_execution_manager.pending_paths[char_id]

	# Waitポイントデータを削除
	var wait_data: Array = path_data.get("wait_points_data", [])
	if Debug.enabled: print("[UndoDebug] _undo_wait_point: wait_data size=%d" % wait_data.size())
	if not wait_data.is_empty():
		wait_data.pop_back()
		path_data["wait_points_data"] = wait_data

	# Waitポイントメッシュを削除
	var wait_meshes: Array = path_data.get("wait_points", [])
	if Debug.enabled: print("[UndoDebug] _undo_wait_point: wait_meshes size=%d" % wait_meshes.size())
	if not wait_meshes.is_empty():
		var mesh = wait_meshes.pop_back()
		if Debug.enabled: print("[UndoDebug] _undo_wait_point: mesh valid=%s" % str(is_instance_valid(mesh)))
		if is_instance_valid(mesh):
			mesh.queue_free()
		path_data["wait_points"] = wait_meshes
	else:
		if Debug.enabled: print("[UndoDebug] _undo_wait_point: wait_meshes is EMPTY!")

	return true
