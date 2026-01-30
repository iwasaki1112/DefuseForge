class_name VisionPointHandler
extends PointHandlerBase

## 視線ポイントハンドラ
## パス上の任意の点から視線方向を設定するポイントの入力・管理を担当


const VisionPointScript = preload("res://scripts/effects/vision_point.gd")


## 視線ポイントデータ配列
var _vision_points: Array[Dictionary] = []

## 視線ポイントメッシュ配列
var _vision_meshes: Array[MeshInstance3D] = []

## 現在の視線アンカー位置
var _current_anchor: Vector3 = Vector3.ZERO

## 現在の視線比率
var _current_ratio: float = 0.0

## 視線描画中フラグ
var _is_drawing: bool = false

## ドラッグ開始位置（スクリーン座標）
var _drag_start_pos: Vector2 = Vector2.ZERO

## 最小ドラッグ距離（これ以上動かさないとドラッグとみなさない）
## モバイルでの誤検出を防ぐため大きめの値を設定
const MIN_DRAG_DISTANCE: float = 40.0

## 最後のタッチ時刻（エミュレートマウスイベント対策）
var _last_touch_time: int = 0

## タッチイベントとマウスイベントの間隔閾値（ミリ秒）
const TOUCH_MOUSE_INTERVAL_MS: int = 100


## 入力処理
func handle_input(event: InputEvent) -> bool:
	# タッチ入力
	if event is InputEventScreenTouch:
		_last_touch_time = Time.get_ticks_msec()
		if event.pressed:
			return _handle_press(event.position)
		else:
			return _handle_release(event.position)

	if event is InputEventScreenDrag:
		if _is_drawing:
			_handle_motion(event.position)
			return true
		return false

	# マウス入力（タッチ直後のエミュレートイベントはスキップ）
	if Time.get_ticks_msec() - _last_touch_time < TOUCH_MOUSE_INTERVAL_MS:
		return false

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				return _handle_press(mouse_event.position)
			else:
				return _handle_release(mouse_event.position)

	if event is InputEventMouseMotion:
		if _is_drawing:
			_handle_motion(event.position)
			return true

	return false


## マウス押下処理
func _handle_press(screen_pos: Vector2) -> bool:
	# 既に描画中の場合は無視（重複イベント対策）
	if _is_drawing:
		return true

	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos == null:
		return false

	var result = _find_closest_point_on_path(ground_pos)
	if result.distance > _get_path_click_threshold():
		return false

	_current_anchor = result.point
	_current_ratio = result.ratio
	_drag_start_pos = screen_pos
	_is_drawing = true
	return true


## マウス解放処理
func _handle_release(screen_pos: Vector2) -> bool:
	if not _is_drawing:
		return false

	# ドラッグ距離が閾値未満の場合（タップ）はポイントを作成しない
	var drag_distance = screen_pos.distance_to(_drag_start_pos)
	if drag_distance >= MIN_DRAG_DISTANCE:
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos != null:
			_finish_vision_point(ground_pos)
	else:
		_remove_temp_point()

	_is_drawing = false
	return true


## マウス移動処理
func _handle_motion(screen_pos: Vector2) -> void:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos != null:
		_update_temp_point(_current_anchor, ground_pos)


## 視線ポイント設定完了
func _finish_vision_point(end_pos: Vector3) -> void:
	var target_point = end_pos
	target_point.y = 0

	var direction = (target_point - _current_anchor)
	direction.y = 0

	if direction.length_squared() < 0.001:
		_remove_temp_point()
		return

	_remove_temp_point()

	# 挿入位置を見つける（path_ratio順にソート）
	var insert_idx = 0
	for i in range(_vision_points.size()):
		if _vision_points[i].path_ratio > _current_ratio:
			break
		insert_idx = i + 1

	# 視線ポイントを追加
	var new_point = {
		"path_ratio": _current_ratio,
		"anchor": _current_anchor,
		"target_point": target_point
	}
	_vision_points.insert(insert_idx, new_point)

	# ポイントを作成
	var point = _create_vision_point_node(_current_anchor, target_point)
	_vision_meshes.insert(insert_idx, point)

	point_added.emit(new_point)


## 視線ポイントノード作成
func _create_vision_point_node(anchor: Vector3, target_point: Vector3) -> MeshInstance3D:
	var point = MeshInstance3D.new()
	point.set_script(VisionPointScript)
	_add_child_to_drawer(point)
	point.set_position_and_target(anchor, target_point)
	point.set_colors(_character_color, Color.WHITE)
	point.set_target_line_color(Color(_character_color.r, _character_color.g * 0.7, _character_color.b * 0.5, 0.8))
	return point


## 一時ポイント更新
func _update_temp_point(anchor: Vector3, target_point: Vector3) -> void:
	if _vision_meshes.size() > _vision_points.size():
		var temp_point = _vision_meshes[-1]
		temp_point.set_position_and_target(anchor, target_point)
	else:
		var point = MeshInstance3D.new()
		point.set_script(VisionPointScript)
		_add_child_to_drawer(point)
		_vision_meshes.append(point)
		point.set_position_and_target(anchor, target_point)
		point.set_colors(_character_color, Color.WHITE)
		point.set_target_line_color(Color(_character_color.r, _character_color.g * 0.7, _character_color.b * 0.5, 0.8))


## 一時ポイント削除
func _remove_temp_point() -> void:
	if _vision_meshes.size() > _vision_points.size():
		var temp_point = _vision_meshes.pop_back()
		temp_point.queue_free()


func has_points() -> bool:
	return _vision_points.size() > 0


func get_point_count() -> int:
	return _vision_points.size()


func get_points() -> Array[Dictionary]:
	return _vision_points


func take_points() -> Array[MeshInstance3D]:
	var points = _vision_meshes.duplicate()
	_vision_meshes.clear()
	return points


func undo_last() -> Dictionary:
	if _vision_points.size() == 0:
		return {}

	var removed_data = _vision_points.pop_back()
	if _vision_meshes.size() > 0:
		var mesh = _vision_meshes.pop_back()
		mesh.queue_free()

	return removed_data


func clear_all() -> void:
	_vision_points.clear()
	for mesh in _vision_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_vision_meshes.clear()


func reset_state() -> void:
	_is_drawing = false
	_drag_start_pos = Vector2.ZERO
	_current_anchor = Vector3.ZERO
	_current_ratio = 0.0
	_remove_temp_point()


## ポイントを復元
func restore_points(data: Array, meshes: Array) -> void:
	for d in data:
		_vision_points.append(d)
	for m in meshes:
		if is_instance_valid(m):
			_add_child_to_drawer(m)
			_vision_meshes.append(m)
