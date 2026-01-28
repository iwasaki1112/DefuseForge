class_name RunMarkerHandler
extends MarkerHandlerBase

## Runマーカーハンドラ
## パス上のRun（ダッシュ）区間の開始・終了を管理するマーカーの入力・管理を担当


const RunMarkerScript = preload("res://scripts/effects/run_marker.gd")


## Run区間データ配列
var _run_segments: Array[Dictionary] = []

## Runマーカーメッシュ配列
var _run_meshes: Array[MeshInstance3D] = []

## 未完成のRun開始点
var _current_run_start: Dictionary = {}


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

	if _current_run_start.is_empty():
		# 開始点を設定
		_current_run_start = { "ratio": result.ratio, "position": result.point }
		_create_run_marker(result.point, RunMarkerScript.RunMarkerType.START)
		return true
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
		_run_segments.append(new_segment)

		# 終点マーカーを作成
		_create_run_marker(result.point, RunMarkerScript.RunMarkerType.END)

		marker_added.emit(new_segment)

		# 開始点をクリア
		_current_run_start = {}
		return true


## Runマーカー作成
func _create_run_marker(pos: Vector3, type: int) -> void:
	var marker = MeshInstance3D.new()
	marker.set_script(RunMarkerScript)
	_add_child_to_drawer(marker)
	marker.set_position_and_type(pos, type)
	marker.set_colors(_character_color, Color.WHITE)
	_run_meshes.append(marker)


func has_markers() -> bool:
	return _run_segments.size() > 0


func get_marker_count() -> int:
	return _run_segments.size()


func get_markers() -> Array[Dictionary]:
	return _run_segments


func take_markers() -> Array[MeshInstance3D]:
	var markers = _run_meshes.duplicate()
	_run_meshes.clear()
	return markers


func undo_last() -> Dictionary:
	if _run_segments.size() > 0:
		var removed_data = _run_segments.pop_back()
		# 終点マーカーを削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		# 開始点マーカーも削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		return removed_data
	elif not _current_run_start.is_empty():
		# 未完成の開始点がある場合
		var removed_data = _current_run_start.duplicate()
		_current_run_start = {}
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		return removed_data
	return {}


func clear_all() -> void:
	_run_segments.clear()
	_current_run_start = {}
	for mesh in _run_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_run_meshes.clear()


func reset_state() -> void:
	# 未完成の開始点があればマーカーを削除
	if not _current_run_start.is_empty():
		_current_run_start = {}
		if _run_meshes.size() > _run_segments.size() * 2:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()


## 未完成のRun開始点があるか
func has_incomplete_run_start() -> bool:
	return not _current_run_start.is_empty()
