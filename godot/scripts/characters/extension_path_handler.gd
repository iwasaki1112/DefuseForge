class_name ExtensionPathHandler
extends RefCounted
## 延長パス管理ハンドラ
## PathFollowingControllerから延長パス関連ロジックを分離

## 延長パス用の変数
var _extension_path: Array[Vector3] = []
var _extension_vision_points: Array[Dictionary] = []
var _extension_run_segments: Array[Dictionary] = []
var _extension_clear_points: Array[Dictionary] = []
var _extension_grenade_points: Array[Dictionary] = []
var _extension_smoke_grenade_points: Array[Dictionary] = []
var _extension_door_points: Array[Dictionary] = []
var _extension_wait_points: Array[Dictionary] = []
var _has_extension: bool = false

## 親コントローラーへの参照
var _controller: Node = null


## セットアップ
func setup(controller: Node) -> void:
	_controller = controller


## 延長パスがあるか
func has_extension_path() -> bool:
	return _has_extension


## 延長パスの終点を取得
func get_extension_path_endpoint() -> Vector3:
	if not _has_extension or _extension_path.size() == 0:
		return Vector3.ZERO
	return _extension_path[_extension_path.size() - 1]


## 延長パスのデータを取得（さらなる延長用）
func get_extension_path_data() -> Dictionary:
	if not _has_extension or _extension_path.size() == 0:
		return {}

	var endpoint := get_extension_path_endpoint()

	return {
		"path": [endpoint],
		"endpoint": endpoint,
		"vision_points": [],
		"run_segments": [],
		"clear_points": [],
		"grenade_points_data": [],
		"smoke_grenade_points_data": [],
		"door_points_data": [],
		"wait_points_data": []
	}


## 移動中パスにVisionポイントを追加
func add_vision_point_to_extension(path_ratio: float, anchor: Vector3, target_point: Vector3) -> void:
	var new_vp := {
		"path_ratio": path_ratio,
		"anchor": anchor,
		"target_point": target_point
	}

	if _has_extension:
		new_vp["path_distance"] = _calculate_anchor_distance_on_path(_extension_path, anchor)
		_extension_vision_points.append(new_vp)
		_extension_vision_points.sort_custom(_compare_by_path_distance)
		if Debug.enabled: print("[PointDebug] ExtensionPathHandler.add_vision: added to pending (count=%d)" % _extension_vision_points.size())
	else:
		# 延長パスに切り替わっている場合はコントローラーのチェッカーに追加
		if _controller:
			_controller._vision_checker.add_point(new_vp)
			if Debug.enabled: print("[PointDebug] ExtensionPathHandler.add_vision: added to checker")


## Waitポイントを追加（実行中のパスに）
func add_wait_point(point_data: Dictionary) -> void:
	if not _controller or not _controller._is_following:
		return

	if _has_extension:
		if point_data.has("anchor") and not point_data.has("path_distance"):
			point_data["path_distance"] = _calculate_anchor_distance_on_path(_extension_path, point_data.anchor)
		_extension_wait_points.append(point_data)
		_extension_wait_points.sort_custom(_compare_by_path_distance)
	else:
		if _controller:
			_controller._wait_checker.add_point(point_data)


## 延長パスを設定
func set_extension_path(extension_path: Array[Vector3], markers: Dictionary, append_to_existing: bool = false) -> void:
	if extension_path.size() < 2:
		if Debug.enabled: print("[PointDebug] ExtensionPathHandler.set_extension_path: path too short (%d)" % extension_path.size())
		return

	if Debug.enabled: print("[PointDebug] ExtensionPathHandler.set_extension_path: path_len=%d, append=%s, has_ext=%s" % [
		extension_path.size(), str(append_to_existing), str(_has_extension)
	])

	if append_to_existing and _has_extension and _extension_path.size() > 0:
		var new_path: Array[Vector3] = _extension_path.duplicate()
		for i in range(1, extension_path.size()):
			new_path.append(extension_path[i])
		_extension_path = new_path

		var old_length := _calculate_extension_path_length_without_new()
		var new_length := _calculate_path_length_array(extension_path)
		var total_length := old_length + new_length
		if total_length > 0.001:
			if old_length > 0.001:
				_scale_existing_extension_points(old_length, total_length)
			_append_extension_points(markers, old_length, new_length, total_length)
	else:
		_extension_path = extension_path.duplicate()
		_extension_vision_points.clear()
		_extension_run_segments.clear()
		_extension_clear_points.clear()
		_extension_grenade_points.clear()
		_extension_smoke_grenade_points.clear()
		_extension_door_points.clear()
		_extension_wait_points.clear()
		for item in markers.get("vision_points", []):
			_extension_vision_points.append(item)
		for item in markers.get("run_segments", []):
			_extension_run_segments.append(item)
		for item in markers.get("clear_points", []):
			_extension_clear_points.append(item)
		for item in markers.get("grenade_points_data", []):
			_extension_grenade_points.append(item)
		for item in markers.get("smoke_grenade_points_data", []):
			_extension_smoke_grenade_points.append(item)
		for item in markers.get("door_points_data", []):
			_extension_door_points.append(item)
		for item in markers.get("wait_points_data", []):
			var wp = item.duplicate() if item is Dictionary else item
			if wp is Dictionary and wp.has("anchor") and not wp.has("path_distance"):
				wp["path_distance"] = _calculate_anchor_distance_on_path(_extension_path, wp.anchor)
			_extension_wait_points.append(wp)
		_extension_wait_points.sort_custom(_compare_by_path_distance)

	_has_extension = true
	if Debug.enabled: print("[PointDebug] ExtensionPathHandler.set_extension_path: done, vision=%d, wait=%d" % [
		_extension_vision_points.size(), _extension_wait_points.size()
	])


## 延長パスをキャンセル
func cancel_extension() -> void:
	_extension_path.clear()
	_extension_vision_points.clear()
	_extension_run_segments.clear()
	_extension_clear_points.clear()
	_extension_grenade_points.clear()
	_extension_smoke_grenade_points.clear()
	_extension_door_points.clear()
	_extension_wait_points.clear()
	_has_extension = false


## 延長パスに切り替え
## @return: 切り替え成功したらtrue
func switch_to_extension_path() -> bool:
	if not _has_extension or _extension_path.size() < 2:
		_has_extension = false
		return false

	if not _controller:
		return false

	# 延長パスを現在のパスに設定
	_controller._current_path = _extension_path.duplicate()
	_controller._run_segments = _extension_run_segments.duplicate()
	_controller._clear_points = _extension_clear_points.duplicate()
	_controller._grenade_points = _extension_grenade_points.duplicate()
	_controller._smoke_grenade_points = _extension_smoke_grenade_points.duplicate()
	_controller._door_points = _extension_door_points.duplicate()

	# インデックスをリセット
	_controller._path_index = 0
	_controller._door_index = 0
	_controller._last_distance_traveled = 0.0
	# ポイントハンドラーのインデックスもリセット
	if "_point_handler" in _controller and _controller._point_handler:
		_controller._point_handler.reset()

	# 延長パスの最初の有効セグメント方向を使用して向きを初期化
	var first_dir: Vector3 = _controller._get_first_segment_direction(_controller._current_path, 0)
	if first_dir.length_squared() > 0.001:
		_controller._last_move_direction = first_dir

	# 視線方向をリセット
	_controller._forced_look_direction = Vector3.ZERO
	_controller._active_target_point = Vector3.ZERO

	# パス長キャッシュを再構築
	_controller._build_path_length_cache()

	# 延長ポイントをチェッカーに設定
	_controller._vision_checker.set_points(_extension_vision_points)
	_controller._wait_checker.set_points(_extension_wait_points)

	# 延長データをクリア
	cancel_extension()

	# キャラクターの現在位置に最も近いパスポイントから開始
	if _controller._character and _controller._current_path.size() > 0:
		var char_pos = _controller._character.global_position
		char_pos.y = 0
		var first_point = _controller._current_path[0]
		first_point.y = 0
		if char_pos.distance_to(first_point) < 0.3:
			_controller._path_index = 1

	# 延長パスに切り替わったことを通知
	_controller.extension_path_activated.emit()
	return true


## ========================================
## 内部ヘルパー
## ========================================

func _calculate_extension_path_length_without_new() -> float:
	var length: float = 0.0
	for i in range(1, _extension_path.size()):
		length += _extension_path[i - 1].distance_to(_extension_path[i])
	return length


func _calculate_path_length_array(path: Array[Vector3]) -> float:
	var length: float = 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


func _append_extension_points(markers: Dictionary, old_length: float, new_length: float, total_length: float) -> void:
	var vision_points: Array = markers.get("vision_points", [])
	for vp in vision_points:
		var adjusted_ratio: float = (old_length + vp.path_ratio * new_length) / total_length
		var new_vp: Dictionary = vp.duplicate()
		new_vp["path_ratio"] = adjusted_ratio
		_extension_vision_points.append(new_vp)

	var run_segments: Array = markers.get("run_segments", [])
	for seg in run_segments:
		if seg.has("start_ratio") and seg.has("end_ratio"):
			var adjusted_start: float = (old_length + seg.start_ratio * new_length) / total_length
			var adjusted_end: float = (old_length + seg.end_ratio * new_length) / total_length
			_extension_run_segments.append({
				"start_ratio": adjusted_start,
				"end_ratio": adjusted_end
			})

	var clear_points: Array = markers.get("clear_points", [])
	for cp in clear_points:
		var adjusted_ratio: float = (old_length + cp.path_ratio * new_length) / total_length
		_extension_clear_points.append({ "path_ratio": adjusted_ratio })

	var grenade_points: Array = markers.get("grenade_points_data", [])
	for gp in grenade_points:
		var adjusted_ratio: float = (old_length + gp.path_ratio * new_length) / total_length
		var new_gp: Dictionary = gp.duplicate()
		new_gp["path_ratio"] = adjusted_ratio
		_extension_grenade_points.append(new_gp)

	var smoke_grenade_points: Array = markers.get("smoke_grenade_points_data", [])
	for sgp in smoke_grenade_points:
		var adjusted_ratio: float = (old_length + sgp.path_ratio * new_length) / total_length
		var new_sgp: Dictionary = sgp.duplicate()
		new_sgp["path_ratio"] = adjusted_ratio
		_extension_smoke_grenade_points.append(new_sgp)

	var door_points: Array = markers.get("door_points_data", [])
	for dp in door_points:
		var adjusted_ratio: float = (old_length + dp.path_ratio * new_length) / total_length
		var new_dp: Dictionary = dp.duplicate()
		new_dp["path_ratio"] = adjusted_ratio
		_extension_door_points.append(new_dp)

	var wait_points: Array = markers.get("wait_points_data", [])
	for wp in wait_points:
		var adjusted_ratio: float = (old_length + wp.path_ratio * new_length) / total_length
		var new_wp: Dictionary = wp.duplicate()
		new_wp["path_ratio"] = adjusted_ratio
		if new_wp.has("anchor"):
			new_wp["path_distance"] = _calculate_anchor_distance_on_path(_extension_path, new_wp.anchor)
		_extension_wait_points.append(new_wp)

	_extension_wait_points.sort_custom(_compare_by_path_distance)


func _scale_existing_extension_points(old_length: float, total_length: float) -> void:
	var scale := old_length / total_length

	# Visionポイントはアンカー位置から比率を再計算
	_recalculate_extension_vision_ratios_from_anchors()

	for i in range(_extension_run_segments.size()):
		var seg = _extension_run_segments[i]
		if seg.has("start_ratio") and seg.has("end_ratio"):
			_extension_run_segments[i]["start_ratio"] = seg.start_ratio * scale
			_extension_run_segments[i]["end_ratio"] = seg.end_ratio * scale

	for i in range(_extension_clear_points.size()):
		_extension_clear_points[i]["path_ratio"] = _extension_clear_points[i].path_ratio * scale

	for i in range(_extension_grenade_points.size()):
		_extension_grenade_points[i]["path_ratio"] = _extension_grenade_points[i].path_ratio * scale

	for i in range(_extension_smoke_grenade_points.size()):
		_extension_smoke_grenade_points[i]["path_ratio"] = _extension_smoke_grenade_points[i].path_ratio * scale

	for i in range(_extension_door_points.size()):
		_extension_door_points[i]["path_ratio"] = _extension_door_points[i].path_ratio * scale

	for i in range(_extension_wait_points.size()):
		_extension_wait_points[i]["path_ratio"] = _extension_wait_points[i].path_ratio * scale

	_recalculate_extension_wait_distances()

	# ポイントスケールシグナルを発火
	if _controller:
		_controller.extension_points_scaled.emit(scale)


func _recalculate_extension_vision_ratios_from_anchors() -> void:
	if _extension_path.size() < 2:
		return

	for i in range(_extension_vision_points.size()):
		var vp = _extension_vision_points[i]
		if vp.has("anchor") and vp.anchor != Vector3.ZERO:
			var new_ratio = _calculate_ratio_from_position_on_path(_extension_path, vp.anchor)
			_extension_vision_points[i]["path_ratio"] = new_ratio


func _recalculate_extension_wait_distances() -> void:
	if _extension_path.size() < 2:
		return

	for i in range(_extension_wait_points.size()):
		var wp = _extension_wait_points[i]
		if wp.has("anchor"):
			var new_distance = _calculate_anchor_distance_on_path(_extension_path, wp.anchor)
			_extension_wait_points[i]["path_distance"] = new_distance

	_extension_wait_points.sort_custom(_compare_by_path_distance)


func _calculate_anchor_distance_on_path(path: Array, anchor: Vector3) -> float:
	if path.size() < 2:
		return 0.0

	var pos = anchor
	pos.y = 0

	var best_distance = INF
	var best_accumulated_length = 0.0
	var accumulated_length = 0.0

	for i in range(1, path.size()):
		var p1 = path[i - 1]
		var p2 = path[i]
		p1.y = 0
		p2.y = 0

		var segment = p2 - p1
		var segment_length_sq = segment.length_squared()
		if segment_length_sq < 0.000001:
			continue

		var segment_length = sqrt(segment_length_sq)
		var t = clampf((pos - p1).dot(segment) / segment_length_sq, 0.0, 1.0)
		var point_on_segment = p1 + segment * t
		var distance = pos.distance_to(point_on_segment)

		if distance < best_distance:
			best_distance = distance
			best_accumulated_length = accumulated_length + segment_length * t

		accumulated_length += segment_length

	return best_accumulated_length


func _calculate_ratio_from_position_on_path(path: Array[Vector3], position: Vector3) -> float:
	if path.is_empty():
		return 0.0
	if path.size() == 1:
		return 0.0

	var total_length := _calculate_path_length_array(path)
	if total_length < 0.001:
		return 0.0

	var best_ratio: float = 0.0
	var best_distance: float = INF
	var accumulated: float = 0.0

	for i in range(1, path.size()):
		var segment_start = path[i - 1]
		var segment_end = path[i]
		var segment_length = segment_start.distance_to(segment_end)

		if segment_length < 0.001:
			accumulated += segment_length
			continue

		var segment_dir = (segment_end - segment_start).normalized()
		var to_pos = position - segment_start
		var proj_length = to_pos.dot(segment_dir)
		proj_length = clamp(proj_length, 0.0, segment_length)

		var closest_point = segment_start + segment_dir * proj_length
		var dist = position.distance_to(closest_point)

		if dist < best_distance:
			best_distance = dist
			best_ratio = (accumulated + proj_length) / total_length

		accumulated += segment_length

	return clamp(best_ratio, 0.0, 1.0)


func _compare_by_path_distance(a: Dictionary, b: Dictionary) -> bool:
	var cached_total := 0.0
	if _controller:
		cached_total = _controller._cached_total_length
	var dist_a: float = a.get("path_distance", a.get("path_ratio", 0.0) * cached_total)
	var dist_b: float = b.get("path_distance", b.get("path_ratio", 0.0) * cached_total)
	return dist_a < dist_b
