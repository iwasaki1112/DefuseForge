class_name SmokeAreaManager
extends Node
## スモークエリア管理システム
## アクティブなスモークエリアをグローバル管理し、視線ブロック判定APIを提供

signal smoke_area_added(area: Node3D)
signal smoke_area_removed(area: Node3D)

## アクティブなスモークエリアのリスト
var _active_areas: Array[Node3D] = []


## スモークエリアを登録
func register_area(area: Node3D) -> void:
	if area in _active_areas:
		return
	_active_areas.append(area)
	smoke_area_added.emit(area)


## スモークエリアを解除
func unregister_area(area: Node3D) -> void:
	var idx := _active_areas.find(area)
	if idx >= 0:
		_active_areas.remove_at(idx)
		smoke_area_removed.emit(area)


## 視線がスモークでブロックされているか判定
## XZ平面上での線分と円（スモークエリア）の交差判定
## @param origin: 視線の始点
## @param target: 視線の終点
## @return: スモークで視線がブロックされている場合true
func is_line_of_sight_blocked(origin: Vector3, target: Vector3) -> bool:
	for area in _active_areas:
		if not is_instance_valid(area):
			continue
		if area.has_method("intersects_line_segment"):
			if area.intersects_line_segment(origin, target):
				return true
	return false


## 一方通行の視線ブロック判定
## 視線の始点（viewer）がスモーク内にいる場合、そのスモークは視線をブロックしない
## @param origin: 視線の始点（見る側）
## @param target: 視線の終点（見られる側）
## @return: スモークで視線がブロックされている場合true
func is_line_of_sight_blocked_one_way(origin: Vector3, target: Vector3) -> bool:
	for area in _active_areas:
		if not is_instance_valid(area):
			continue
		# 見る側がこのスモーク内にいる場合、このスモークはブロックしない
		if area.has_method("is_position_inside") and area.is_position_inside(origin):
			continue
		if area.has_method("intersects_line_segment"):
			if area.intersects_line_segment(origin, target):
				return true
	return false


## 2つの位置が同じスモーク内にあるか判定
## @param pos_a: 位置A
## @param pos_b: 位置B
## @return: 同じスモーク内にある場合true
func are_positions_in_same_smoke(pos_a: Vector3, pos_b: Vector3) -> bool:
	for area in _active_areas:
		if not is_instance_valid(area):
			continue
		if area.has_method("is_position_inside"):
			if area.is_position_inside(pos_a) and area.is_position_inside(pos_b):
				return true
	return false


## 指定位置がスモーク内にあるか判定
## @param pos: 判定位置
## @return: スモーク内にある場合true
func is_position_in_smoke(pos: Vector3) -> bool:
	for area in _active_areas:
		if not is_instance_valid(area):
			continue
		if area.has_method("is_position_inside"):
			if area.is_position_inside(pos):
				return true
	return false


## アクティブなスモークエリア数を取得
func get_active_count() -> int:
	return _active_areas.size()


## 無効なエリアをクリーンアップ
func cleanup_invalid_areas() -> void:
	var valid_areas: Array[Node3D] = []
	for area in _active_areas:
		if is_instance_valid(area):
			valid_areas.append(area)
	_active_areas = valid_areas


## 全スモークエリアをクリア
func clear_all() -> void:
	for area in _active_areas:
		if is_instance_valid(area):
			area.queue_free()
	_active_areas.clear()
