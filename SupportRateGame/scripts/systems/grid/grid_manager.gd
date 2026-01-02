class_name GridManager
extends Node3D

## グリッドマネージャー
## マップをグリッドに分割し、座標変換やパスファインディングを管理
##
## 使用方法:
## - world_to_cell(): ワールド座標 → セル座標
## - cell_to_world(): セル座標 → ワールド座標（セル中心）
## - snap_to_grid(): ワールド座標を最寄りセル中心にスナップ

signal grid_initialized

@export_group("グリッド設定")
@export var cell_size: float = 1.0  # 1セルのサイズ（メートル）
@export var grid_width: int = 32  # グリッドの幅（セル数）
@export var grid_height: int = 32  # グリッドの高さ（セル数）
@export var grid_origin: Vector3 = Vector3.ZERO  # グリッドの原点（左下）

@export_group("障害物")
@export var obstacle_collision_layer: int = 2  # 障害物のコリジョンレイヤー

# グリッドデータ（true = 通行可能, false = 障害物）
var _walkable: PackedByteArray = PackedByteArray()

# 初期化済みフラグ
var _initialized: bool = false


func _ready() -> void:
	_initialize_grid()


## グリッドを初期化
func _initialize_grid() -> void:
	# グリッドデータを確保
	_walkable.resize(grid_width * grid_height)
	_walkable.fill(1)  # デフォルトは全て通行可能

	# 障害物をスキャン
	_scan_obstacles()

	_initialized = true
	grid_initialized.emit()
	print("[GridManager] Initialized: %dx%d cells, cell_size=%.1f" % [grid_width, grid_height, cell_size])


## 障害物をスキャンしてグリッドに反映
func _scan_obstacles() -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return

	var obstacle_count := 0

	for y in range(grid_height):
		for x in range(grid_width):
			var world_pos := cell_to_world(Vector2i(x, y))

			# セル中心から上に向かってレイキャスト
			var query := PhysicsRayQueryParameters3D.create(
				world_pos + Vector3(0, 5, 0),
				world_pos + Vector3(0, -1, 0)
			)
			query.collision_mask = obstacle_collision_layer

			var result := space_state.intersect_ray(query)
			if result:
				set_walkable(Vector2i(x, y), false)
				obstacle_count += 1

	print("[GridManager] Scanned obstacles: %d cells blocked" % obstacle_count)


## 障害物を再スキャン（コリジョン動的追加後に呼び出し）
func rescan_obstacles() -> void:
	# グリッドをリセット
	_walkable.fill(1)
	# 再スキャン
	_scan_obstacles()


## ワールド座標をセル座標に変換
func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local_x := (world_pos.x - grid_origin.x) / cell_size
	var local_z := (world_pos.z - grid_origin.z) / cell_size
	return Vector2i(
		clampi(int(floor(local_x)), 0, grid_width - 1),
		clampi(int(floor(local_z)), 0, grid_height - 1)
	)


## セル座標をワールド座標（セル中心）に変換
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		grid_origin.x + (float(cell.x) + 0.5) * cell_size,
		grid_origin.y,
		grid_origin.z + (float(cell.y) + 0.5) * cell_size
	)


## ワールド座標を最寄りのセル中心にスナップ
func snap_to_grid(world_pos: Vector3) -> Vector3:
	var cell := world_to_cell(world_pos)
	var snapped_pos := cell_to_world(cell)
	snapped_pos.y = world_pos.y  # Y座標は維持
	return snapped_pos


## セルが通行可能かどうか
func is_walkable(cell: Vector2i) -> bool:
	if not is_valid_cell(cell):
		return false
	return _walkable[cell.y * grid_width + cell.x] == 1


## セルの通行可能状態を設定
func set_walkable(cell: Vector2i, walkable: bool) -> void:
	if is_valid_cell(cell):
		_walkable[cell.y * grid_width + cell.x] = 1 if walkable else 0


## セルが有効範囲内かどうか
func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height


## 2x2エリアが通行可能かどうか（キャラクターサイズ用）
## cellは2x2エリアの左下セルを指定
func is_walkable_2x2(cell: Vector2i) -> bool:
	for dx in range(2):
		for dy in range(2):
			var check_cell := Vector2i(cell.x + dx, cell.y + dy)
			if not is_walkable(check_cell):
				return false
	return true


## 2x2エリアが有効範囲内かどうか
func is_valid_cell_2x2(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width - 1 and cell.y >= 0 and cell.y < grid_height - 1


## グリッドの境界を取得（ワールド座標）
func get_bounds() -> AABB:
	var size := Vector3(
		grid_width * cell_size,
		0,
		grid_height * cell_size
	)
	return AABB(grid_origin, size)


## 隣接セルを取得（4方向）
func get_neighbors_4(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions: Array[Vector2i] = [
		Vector2i(0, -1),  # 上
		Vector2i(1, 0),   # 右
		Vector2i(0, 1),   # 下
		Vector2i(-1, 0),  # 左
	]
	for dir in directions:
		var neighbor: Vector2i = cell + dir
		if is_valid_cell(neighbor):
			neighbors.append(neighbor)
	return neighbors


## 隣接セルを取得（8方向）
func get_neighbors_8(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor: Vector2i = cell + Vector2i(dx, dy)
			if is_valid_cell(neighbor):
				neighbors.append(neighbor)
	return neighbors


## A*パスファインディング
## start_cell から end_cell への最短経路をセル配列で返す
func find_path(start_cell: Vector2i, end_cell: Vector2i, allow_diagonal: bool = true) -> Array[Vector2i]:
	if not is_valid_cell(start_cell) or not is_valid_cell(end_cell):
		return []

	if not is_walkable(end_cell):
		return []

	# A*アルゴリズム
	var open_set: Array[Vector2i] = [start_cell]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_cell: 0.0}
	var f_score: Dictionary = {start_cell: _heuristic(start_cell, end_cell)}

	while open_set.size() > 0:
		# f_scoreが最小のノードを取得
		var current: Vector2i = _get_lowest_f_score(open_set, f_score)

		if current == end_cell:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		var neighbors: Array[Vector2i] = get_neighbors_8(current) if allow_diagonal else get_neighbors_4(current)
		for neighbor in neighbors:
			if not is_walkable(neighbor):
				continue

			# 斜め移動時の角抜け防止
			if allow_diagonal:
				var dx: int = neighbor.x - current.x
				var dy: int = neighbor.y - current.y
				if abs(dx) == 1 and abs(dy) == 1:
					if not is_walkable(Vector2i(current.x + dx, current.y)) or \
					   not is_walkable(Vector2i(current.x, current.y + dy)):
						continue

			var move_cost: float = 1.414 if (neighbor - current).length() > 1.1 else 1.0
			var current_g: float = g_score[current]
			var tentative_g: float = current_g + move_cost

			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, end_cell)
				if neighbor not in open_set:
					open_set.append(neighbor)

	return []  # パスが見つからない


## A*パスファインディング（2x2キャラクター用）
## cellは2x2エリアの左下セルを指定
func find_path_2x2(start_cell: Vector2i, end_cell: Vector2i, allow_diagonal: bool = true) -> Array[Vector2i]:
	if not is_valid_cell_2x2(start_cell) or not is_valid_cell_2x2(end_cell):
		return []

	if not is_walkable_2x2(end_cell):
		return []

	# A*アルゴリズム（2x2版）
	var open_set: Array[Vector2i] = [start_cell]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_cell: 0.0}
	var f_score: Dictionary = {start_cell: _heuristic(start_cell, end_cell)}

	while open_set.size() > 0:
		var current: Vector2i = _get_lowest_f_score(open_set, f_score)

		if current == end_cell:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		var neighbors: Array[Vector2i] = _get_neighbors_8_2x2(current) if allow_diagonal else _get_neighbors_4_2x2(current)
		for neighbor in neighbors:
			if not is_walkable_2x2(neighbor):
				continue

			# 斜め移動時の角抜け防止（2x2用）
			if allow_diagonal:
				var dx: int = neighbor.x - current.x
				var dy: int = neighbor.y - current.y
				if abs(dx) == 1 and abs(dy) == 1:
					if not is_walkable_2x2(Vector2i(current.x + dx, current.y)) or \
					   not is_walkable_2x2(Vector2i(current.x, current.y + dy)):
						continue

			var move_cost: float = 1.414 if (neighbor - current).length() > 1.1 else 1.0
			var current_g: float = g_score[current]
			var tentative_g: float = current_g + move_cost

			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, end_cell)
				if neighbor not in open_set:
					open_set.append(neighbor)

	return []


## 隣接セルを取得（4方向、2x2用）
func _get_neighbors_4_2x2(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	]
	for dir in directions:
		var neighbor: Vector2i = cell + dir
		if is_valid_cell_2x2(neighbor):
			neighbors.append(neighbor)
	return neighbors


## 隣接セルを取得（8方向、2x2用）
func _get_neighbors_8_2x2(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor: Vector2i = cell + Vector2i(dx, dy)
			if is_valid_cell_2x2(neighbor):
				neighbors.append(neighbor)
	return neighbors


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# 八方向移動用のチェビシェフ距離
	var dx: int = abs(a.x - b.x)
	var dy: int = abs(a.y - b.y)
	return float(max(dx, dy)) + (1.414 - 1.0) * float(min(dx, dy))


func _get_lowest_f_score(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var lowest: Vector2i = open_set[0]
	var lowest_score: float = f_score.get(lowest, INF)
	for cell in open_set:
		var score: float = f_score.get(cell, INF)
		if score < lowest_score:
			lowest = cell
			lowest_score = score
	return lowest


func _reconstruct_path(came_from: Dictionary, start_current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start_current]
	var current: Vector2i = start_current
	while came_from.has(current):
		var prev: Vector2i = came_from[current]
		current = prev
		path.insert(0, current)
	return path


## デバッグ用：グリッド情報を取得
func get_debug_info() -> Dictionary:
	var walkable_count := 0
	for i in range(_walkable.size()):
		if _walkable[i] == 1:
			walkable_count += 1

	return {
		"grid_size": Vector2i(grid_width, grid_height),
		"cell_size": cell_size,
		"origin": grid_origin,
		"total_cells": grid_width * grid_height,
		"walkable_cells": walkable_count,
		"blocked_cells": grid_width * grid_height - walkable_count,
		"initialized": _initialized
	}
