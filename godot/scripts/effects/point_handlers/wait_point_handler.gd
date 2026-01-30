class_name WaitPointHandler
extends PointHandlerBase

## Waitポイントハンドラ
## パス上の待機ポイント（長押しで待機時間を設定）を管理するポイントの入力・管理を担当


const WaitPointScript = preload("res://scripts/effects/wait_point.gd")

## 最小待機時間（秒）
const WAIT_MIN_DURATION: float = 0.0
## 最大待機時間（秒）
const WAIT_MAX_DURATION: float = 10.0


## Waitポイントデータ配列
var _wait_points: Array[Dictionary] = []

## Waitポイントメッシュ配列
var _wait_meshes: Array[MeshInstance3D] = []

## 長押し開始時刻
var _press_start_time: float = 0.0

## 長押し中フラグ
var _is_pressing: bool = false

## プレビューポイント
var _preview_point: MeshInstance3D = null

## 保留中アンカー位置
var _pending_anchor: Vector3 = Vector3.ZERO

## 保留中比率
var _pending_ratio: float = 0.0


## 入力処理
func handle_input(event: InputEvent) -> bool:
	# マウス入力
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				return _start_press(mouse_event.position)
			else:
				if _is_pressing:
					_finish_press()
					return true

	if event is InputEventMouseMotion:
		if _is_pressing:
			update_preview()
			return true

	# タッチ入力
	if event is InputEventScreenTouch:
		if event.pressed:
			return _start_press(event.position)
		else:
			if _is_pressing:
				_finish_press()
				return true

	if event is InputEventScreenDrag:
		if _is_pressing:
			update_preview()
			return true

	return false


## 長押し開始
func _start_press(screen_pos: Vector2) -> bool:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos == null:
		return false

	var result = _find_closest_point_on_path(ground_pos)
	if result.distance > _get_path_click_threshold():
		return false

	_pending_anchor = result.point
	_pending_ratio = result.ratio
	_press_start_time = Time.get_ticks_msec() / 1000.0
	_is_pressing = true

	_create_preview_point()
	return true


## 長押し終了
func _finish_press() -> void:
	if not _is_pressing:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var duration = current_time - _press_start_time
	_is_pressing = false

	# 最小時間未満はキャンセル
	if duration < WAIT_MIN_DURATION:
		_remove_preview_point()
		return

	# 最大時間で制限
	duration = clampf(duration, WAIT_MIN_DURATION, WAIT_MAX_DURATION)

	_remove_preview_point()

	# Waitポイントを追加
	var new_point = {
		"path_ratio": _pending_ratio,
		"anchor": _pending_anchor,
		"wait_duration": duration
	}

	_wait_points.append(new_point)

	# ポイントメッシュを作成
	var point = _create_wait_point_node(_pending_anchor, duration)
	_wait_meshes.append(point)

	point_added.emit(new_point)


## プレビューポイント作成
func _create_preview_point() -> void:
	_remove_preview_point()

	_preview_point = MeshInstance3D.new()
	_preview_point.set_script(WaitPointScript)
	_add_child_to_drawer(_preview_point)
	_preview_point.set_point_position(_pending_anchor)
	_preview_point.set_colors(Color(_character_color.r, _character_color.g, _character_color.b, 0.6), Color(1.0, 1.0, 1.0, 0.8))
	_preview_point.set_wait_duration(WAIT_MIN_DURATION)


## プレビューポイント削除
func _remove_preview_point() -> void:
	if _preview_point:
		_preview_point.queue_free()
		_preview_point = null


## プレビュー更新
func update_preview() -> void:
	if not _is_pressing or not _preview_point:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var duration = clampf(current_time - _press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)
	_preview_point.set_wait_duration(duration)


## Waitポイントノード作成
func _create_wait_point_node(anchor: Vector3, duration: float) -> MeshInstance3D:
	var point = MeshInstance3D.new()
	point.set_script(WaitPointScript)
	_add_child_to_drawer(point)
	point.set_point_position(anchor)
	point.set_colors(_character_color, Color(1.0, 1.0, 1.0, 1.0))
	point.set_wait_duration(duration)
	return point


## プレビュー中の待機時間を取得
func get_preview_duration() -> float:
	if not _is_pressing:
		return 0.0
	var current_time = Time.get_ticks_msec() / 1000.0
	return clampf(current_time - _press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)


## 長押し中かどうか
func is_pressing() -> bool:
	return _is_pressing


func has_points() -> bool:
	return _wait_points.size() > 0


func get_point_count() -> int:
	return _wait_points.size()


func get_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = _wait_points.duplicate()
	# プレビュー中のポイントがあれば追加
	if _is_pressing and _preview_point:
		result.append({
			"path_ratio": _pending_ratio,
			"anchor": _pending_anchor,
			"wait_duration": get_preview_duration()
		})
	return result


func take_points() -> Array[MeshInstance3D]:
	var points = _wait_meshes.duplicate()
	_wait_meshes.clear()
	return points


func undo_last() -> Dictionary:
	if _wait_points.size() == 0:
		return {}

	var removed_data = _wait_points.pop_back()
	if _wait_meshes.size() > 0:
		var mesh = _wait_meshes.pop_back()
		if is_instance_valid(mesh):
			mesh.queue_free()

	return removed_data


func clear_all() -> void:
	_wait_points.clear()
	for mesh in _wait_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_wait_meshes.clear()
	_remove_preview_point()
	_is_pressing = false
	_press_start_time = 0.0


func reset_state() -> void:
	_remove_preview_point()
	_is_pressing = false
	_press_start_time = 0.0


## 同期Waitポイントを追加（コンテキストメニューから呼ばれる）
## wait_duration = -1 は同期ポイント（Wボタンで解放されるまで待機）を示す
## @param path_ratio: パス上の位置（0.0〜1.0）
## @param anchor: ポイントの3D位置
func add_sync_point(path_ratio: float, anchor: Vector3) -> void:
	var new_point = {
		"path_ratio": path_ratio,
		"anchor": anchor,
		"wait_duration": -1.0  # 同期ポイント（無期限待機）
	}
	_wait_points.append(new_point)

	# ポイントメッシュを作成（"W"表示）
	var point = _create_wait_point_node(anchor, -1.0)
	_wait_meshes.append(point)

	point_added.emit(new_point)


## ポイントを復元
func restore_points(data: Array, meshes: Array) -> void:
	for d in data:
		_wait_points.append(d)
	for m in meshes:
		if is_instance_valid(m):
			_add_child_to_drawer(m)
			_wait_meshes.append(m)
