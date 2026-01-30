class_name RunPointHandler
extends PointHandlerBase

## Runポイントハンドラ
## パス上のRun（ダッシュ）区間の開始・終了を管理するポイントの入力・管理を担当


const RunPointScript = preload("res://scripts/effects/run_point.gd")


## Run区間データ配列
var _run_segments: Array[Dictionary] = []

## Runポイントメッシュ配列
var _run_meshes: Array[MeshInstance3D] = []

## 未完成のRun開始点
var _current_run_start: Dictionary = {}


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

	if _current_run_start.is_empty():
		# 開始点を設定
		_current_run_start = { "ratio": result.ratio, "position": result.point }
		_create_run_point(result.point, RunPointScript.RunPointType.START)
		return true
	else:
		# 終点を設定してセグメントを完成
		var start_ratio = _current_run_start.ratio
		var end_ratio = result.ratio

		# 開始点と終点が近すぎる場合は無視（ダブルタップ防止）
		const MIN_SEGMENT_RATIO: float = 0.02  # パス全長の2%以上必要
		if absf(end_ratio - start_ratio) < MIN_SEGMENT_RATIO:
			return true  # イベントは処理済みとして返すが、セグメントは作成しない

		# 開始点が終点より後ろなら入れ替え
		if start_ratio > end_ratio:
			var tmp = start_ratio
			start_ratio = end_ratio
			end_ratio = tmp

		# Run区間を追加
		var new_segment = { "start_ratio": start_ratio, "end_ratio": end_ratio }
		_run_segments.append(new_segment)

		# 終点ポイントを作成
		_create_run_point(result.point, RunPointScript.RunPointType.END)

		point_added.emit(new_segment)

		# 開始点をクリア
		_current_run_start = {}
		return true


## Runポイント作成
func _create_run_point(pos: Vector3, type: int) -> void:
	var point = MeshInstance3D.new()
	point.set_script(RunPointScript)
	_add_child_to_drawer(point)
	point.set_position_and_type(pos, type)
	point.set_colors(_character_color, Color.WHITE)
	_run_meshes.append(point)


func has_points() -> bool:
	return _run_segments.size() > 0


func get_point_count() -> int:
	return _run_segments.size()


func get_points() -> Array[Dictionary]:
	return _run_segments


func take_points() -> Array[MeshInstance3D]:
	var points = _run_meshes.duplicate()
	_run_meshes.clear()
	return points


func undo_last() -> Dictionary:
	if _run_segments.size() > 0:
		var removed_data = _run_segments.pop_back()
		# 終点ポイントを削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		# 開始点ポイントも削除
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
	# 未完成の開始点があればポイントを削除
	if not _current_run_start.is_empty():
		_current_run_start = {}
		if _run_meshes.size() > _run_segments.size() * 2:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()


## 未完成のRun開始点があるか
func has_incomplete_run_start() -> bool:
	return not _current_run_start.is_empty()


## ポイントを復元
func restore_points(data: Array, meshes: Array) -> void:
	for d in data:
		_run_segments.append(d)
	for m in meshes:
		if is_instance_valid(m):
			_add_child_to_drawer(m)
			_run_meshes.append(m)
