extends Node3D
## GridMapテストマップ
## MeshLibraryを使用したタイル配置のデモ

# MeshLibraryアイテムID
const FLOOR := 0
const WALL_STRAIGHT := 1
const WALL_CORNER := 2
const PILLAR := 3
const CRATE := 4

@onready var grid_map: GridMap = $GridMap


func _ready() -> void:
	_build_map()
	print("[GridMapTest] Map built")


func _build_map() -> void:
	if not grid_map:
		return

	# マップサイズ
	var map_width := 10
	var map_depth := 10

	# 床を敷き詰める
	for x in range(map_width):
		for z in range(map_depth):
			grid_map.set_cell_item(Vector3i(x, 0, z), FLOOR)

	# 外周に壁を配置
	# 北壁（Z=0）
	for x in range(map_width):
		grid_map.set_cell_item(Vector3i(x, 1, 0), WALL_STRAIGHT, 0)

	# 南壁（Z=map_depth-1）
	for x in range(map_width):
		grid_map.set_cell_item(Vector3i(x, 1, map_depth - 1), WALL_STRAIGHT, 0)

	# 西壁（X=0）- 回転して配置
	for z in range(1, map_depth - 1):
		grid_map.set_cell_item(Vector3i(0, 1, z), WALL_STRAIGHT, 16)  # 90度回転

	# 東壁（X=map_width-1）- 回転して配置
	for z in range(1, map_depth - 1):
		grid_map.set_cell_item(Vector3i(map_width - 1, 1, z), WALL_STRAIGHT, 16)

	# 中央に障害物（箱）
	grid_map.set_cell_item(Vector3i(5, 1, 5), CRATE)
	grid_map.set_cell_item(Vector3i(4, 1, 5), CRATE)

	# 柱を配置
	grid_map.set_cell_item(Vector3i(3, 1, 3), PILLAR)
	grid_map.set_cell_item(Vector3i(6, 1, 6), PILLAR)
