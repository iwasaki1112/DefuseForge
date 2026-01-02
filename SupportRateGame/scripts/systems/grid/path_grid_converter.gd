class_name PathGridConverter
extends RefCounted

## パスグリッドコンバーター
## フリーハンドで描いたパスをグリッドセル配列に変換
##
## 使用方法:
## var converter = PathGridConverter.new(grid_manager)
## var cells = converter.convert_path(freehand_points)
## var world_path = converter.cells_to_world_path(cells)

var _grid_manager: Node  # GridManager


func _init(grid_manager: Node) -> void:
	_grid_manager = grid_manager


## フリーハンドパス（Vector3配列）をグリッドセル配列に変換
## 連続する同じセルは除去され、セル間は補間される
func convert_path(freehand_points: Array) -> Array[Vector2i]:
	if freehand_points.is_empty():
		return []

	var cells: Array[Vector2i] = []
	var last_cell: Vector2i = Vector2i(-999, -999)

	for point in freehand_points:
		var world_pos: Vector3
		if point is Vector3:
			world_pos = point
		elif point is Vector2:
			world_pos = Vector3(point.x, 0, point.y)
		else:
			continue

		var cell = _grid_manager.world_to_cell(world_pos)

		# 連続する同じセルは追加しない
		if cell != last_cell:
			# 前のセルとの間を補間
			if last_cell != Vector2i(-999, -999):
				var interpolated := _interpolate_cells(last_cell, cell)
				# 最初のセル（last_cell）は既に追加済みなのでスキップ
				for i in range(1, interpolated.size()):
					if interpolated[i] != cells[cells.size() - 1]:
						cells.append(interpolated[i])
			else:
				cells.append(cell)
			last_cell = cell

	return cells


## 2つのセル間を補間（斜め移動を優先）
func _interpolate_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1

	var x: int = from.x
	var y: int = from.y

	result.append(Vector2i(x, y))

	# 斜め移動を優先：できるだけ斜めに進み、残りを直線で埋める
	while x != to.x or y != to.y:
		if x != to.x and y != to.y:
			# 両方向に移動が必要 → 斜め移動
			x += sx
			y += sy
		elif x != to.x:
			# X方向のみ
			x += sx
		else:
			# Y方向のみ
			y += sy
		result.append(Vector2i(x, y))

	return result


## グリッドセル配列をワールド座標パスに変換
func cells_to_world_path(cells: Array[Vector2i]) -> Array[Vector3]:
	var path: Array[Vector3] = []
	for cell in cells:
		var world_pos: Vector3 = _grid_manager.cell_to_world(cell)
		path.append(world_pos)
	return path


## パスを最適化（不要な中間点を除去）
## 直線上にある中間セルを除去してパスをシンプルにする
func optimize_path(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 2:
		return cells

	var optimized: Array[Vector2i] = [cells[0]]

	for i in range(1, cells.size() - 1):
		var prev := cells[i - 1]
		var curr := cells[i]
		var next := cells[i + 1]

		# 方向ベクトルを計算
		var dir1 := curr - prev
		var dir2 := next - curr

		# 方向が変わった場合のみ追加
		if dir1 != dir2:
			optimized.append(curr)

	optimized.append(cells[cells.size() - 1])
	return optimized


## 階段パターンを滑らかにする
## 斜め移動の途中にある不要な水平/垂直移動を除去
func smooth_staircase(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 2:
		return cells

	var result: Array[Vector2i] = [cells[0]]
	var i := 1

	while i < cells.size() - 1:
		var prev := result[result.size() - 1]
		var curr := cells[i]
		var next := cells[i + 1]

		# prev → curr → next のパターンをチェック
		var dir1 := curr - prev
		var dir2 := next - curr

		# 階段パターンの検出：
		# 斜め→水平/垂直 または 水平/垂直→斜め の組み合わせで、
		# 全体としては斜め方向に進んでいる場合
		var total_dir := next - prev
		var is_staircase := false

		# 全体の移動が斜め（±2, ±1）または（±1, ±2）のパターン
		if abs(total_dir.x) <= 2 and abs(total_dir.y) <= 2:
			if abs(total_dir.x) >= 1 and abs(total_dir.y) >= 1:
				# 中間点をスキップして直接斜め移動が可能かチェック
				var can_skip := _can_move_diagonally(prev, next)
				if can_skip:
					is_staircase = true

		if is_staircase:
			# 中間点をスキップ
			i += 1
		else:
			result.append(curr)
			i += 1

	# 残りの点を追加
	while i < cells.size():
		result.append(cells[i])
		i += 1

	return result


## 2点間を斜め移動のみで接続可能かチェック
func _can_move_diagonally(from: Vector2i, to: Vector2i) -> bool:
	var dx: int = absi(to.x - from.x)
	var dy: int = absi(to.y - from.y)
	# 完全な斜め、または斜め＋1マスの水平/垂直
	return (dx == dy) or (absi(dx - dy) <= 1)


## フリーハンドパスを完全変換（変換→階段除去→最適化→ワールド座標）
func convert_and_optimize(freehand_points: Array) -> Dictionary:
	var cells := convert_path(freehand_points)
	# 階段パターンを滑らかにしてから最適化
	var smoothed := smooth_staircase(cells)
	var optimized := optimize_path(smoothed)
	var world_path := cells_to_world_path(optimized)

	return {
		"original_points": freehand_points.size(),
		"grid_cells": smoothed,  # 階段除去後のセル
		"optimized_cells": optimized,
		"world_path": world_path,
		"reduction_ratio": float(optimized.size()) / float(cells.size()) if cells.size() > 0 else 1.0
	}


## A*を使用してパスを補間（障害物回避）
## 開始・終了セルだけ指定して、GridManagerのA*で経路探索
func find_grid_path(start_pos: Vector3, end_pos: Vector3) -> Array[Vector2i]:
	var start_cell = _grid_manager.world_to_cell(start_pos)
	var end_cell = _grid_manager.world_to_cell(end_pos)
	var path = _grid_manager.find_path(start_cell, end_cell)
	var result: Array[Vector2i] = []
	for cell in path:
		result.append(cell)
	return result


## フリーハンドパスをA*で再計算（障害物回避版）
## 各ウェイポイント間をA*で接続
func convert_with_pathfinding(freehand_points: Array) -> Array[Vector2i]:
	if freehand_points.size() < 2:
		return convert_path(freehand_points)

	# まずフリーハンドをセルに変換
	var waypoint_cells := convert_path(freehand_points)

	if waypoint_cells.size() < 2:
		return waypoint_cells

	# 通行可能なセルのみをフィルタリング
	var walkable_waypoints: Array[Vector2i] = []
	for cell in waypoint_cells:
		if _grid_manager.is_walkable(cell):
			walkable_waypoints.append(cell)

	if walkable_waypoints.size() < 2:
		return walkable_waypoints

	# 最適化して主要ウェイポイントだけにする
	var key_waypoints := optimize_path(walkable_waypoints)

	# 各ウェイポイント間をA*で接続
	var full_path: Array[Vector2i] = []

	for i in range(key_waypoints.size() - 1):
		var from_cell := key_waypoints[i]
		var to_cell := key_waypoints[i + 1]

		# 両方のセルが通行可能か確認
		if not _grid_manager.is_walkable(from_cell) or not _grid_manager.is_walkable(to_cell):
			continue

		var segment = _grid_manager.find_path(from_cell, to_cell)

		if segment.is_empty():
			# パスが見つからない場合はスキップ（壁を通らない）
			# 開始点だけは追加
			if full_path.is_empty():
				full_path.append(from_cell)
		else:
			# 最初のセグメント以外は開始点を除去（重複防止）
			var start_idx := 0 if full_path.is_empty() else 1
			for j in range(start_idx, segment.size()):
				full_path.append(segment[j])

	return full_path


## 移動コストを計算（セル数ベース）
func calculate_path_cost(cells: Array[Vector2i]) -> float:
	if cells.size() <= 1:
		return 0.0

	var cost := 0.0
	for i in range(1, cells.size()):
		var diff := cells[i] - cells[i - 1]
		# 斜め移動は√2倍のコスト
		cost += 1.414 if abs(diff.x) + abs(diff.y) == 2 else 1.0

	return cost


## パスの推定移動時間を計算
func estimate_travel_time(cells: Array[Vector2i], speed: float) -> float:
	var cost := calculate_path_cost(cells)
	var cell_size: float = _grid_manager.cell_size
	var distance := cost * cell_size
	return distance / speed if speed > 0 else 0.0
