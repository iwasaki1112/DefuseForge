class_name GridVisualizer
extends Node3D

## グリッド可視化
## デバッグ用にグリッドを3D空間に表示
## 通行可能/不可能セル、パスなどを色分け表示

const PathGridConverterClass = preload("res://scripts/systems/grid/path_grid_converter.gd")

@export_node_path("Node3D") var grid_manager_path: NodePath
var grid_manager: Node = null  # GridManager参照

@export_group("表示設定")
@export var show_grid_lines: bool = true
@export var show_cells: bool = true
@export var show_walkable: bool = true
@export var show_blocked: bool = true
@export var cell_height: float = 0.02  # セル表示の高さ

@export_group("色設定")
@export var grid_line_color: Color = Color(0.5, 0.5, 0.5, 0.5)
@export var walkable_color: Color = Color(0.2, 0.8, 0.2, 0.3)
@export var blocked_color: Color = Color(0.8, 0.2, 0.2, 0.5)
@export var path_color: Color = Color(0.2, 0.5, 1.0, 0.7)
@export var path_start_color: Color = Color(0.2, 1.0, 0.2, 0.9)
@export var path_end_color: Color = Color(1.0, 0.2, 0.2, 0.9)

# 内部ノード
var _grid_lines_mesh: MeshInstance3D = null
var _cells_mesh: MeshInstance3D = null
var _path_mesh: MeshInstance3D = null

# マテリアル
var _line_material: StandardMaterial3D = null
var _cell_material: StandardMaterial3D = null
var _path_material: StandardMaterial3D = null

# 現在表示中のパス
var _current_path: Array[Vector2i] = []


func _ready() -> void:
	_create_materials()
	_create_mesh_instances()

	# NodePathからgrid_managerを解決
	if grid_manager_path:
		grid_manager = get_node_or_null(grid_manager_path)

	# GridManagerの初期化を待つ
	if grid_manager and grid_manager.has_signal("grid_initialized"):
		if grid_manager._initialized:
			_build_visualization()
		else:
			grid_manager.grid_initialized.connect(_build_visualization)


func _create_materials() -> void:
	# グリッド線マテリアル
	_line_material = StandardMaterial3D.new()
	_line_material.albedo_color = grid_line_color
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# セルマテリアル
	_cell_material = StandardMaterial3D.new()
	_cell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cell_material.vertex_color_use_as_albedo = true

	# パスマテリアル
	_path_material = StandardMaterial3D.new()
	_path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_path_material.vertex_color_use_as_albedo = true


func _create_mesh_instances() -> void:
	_grid_lines_mesh = MeshInstance3D.new()
	_grid_lines_mesh.name = "GridLines"
	_grid_lines_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_lines_mesh)

	_cells_mesh = MeshInstance3D.new()
	_cells_mesh.name = "Cells"
	_cells_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cells_mesh)

	_path_mesh = MeshInstance3D.new()
	_path_mesh.name = "Path"
	_path_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path_mesh)


func _build_visualization() -> void:
	if not grid_manager:
		return

	if show_grid_lines:
		_build_grid_lines()

	if show_cells:
		_build_cells()


## グリッド線を構築
func _build_grid_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_material(_line_material)

	var origin: Vector3 = grid_manager.grid_origin
	var cell_size_val: float = grid_manager.cell_size
	var width: int = grid_manager.grid_width
	var height: int = grid_manager.grid_height
	var y: float = origin.y + cell_height

	# 縦線
	for x in range(width + 1):
		var x_pos: float = origin.x + x * cell_size_val
		st.add_vertex(Vector3(x_pos, y, origin.z))
		st.add_vertex(Vector3(x_pos, y, origin.z + height * cell_size_val))

	# 横線
	for z in range(height + 1):
		var z_pos: float = origin.z + z * cell_size_val
		st.add_vertex(Vector3(origin.x, y, z_pos))
		st.add_vertex(Vector3(origin.x + width * cell_size_val, y, z_pos))

	_grid_lines_mesh.mesh = st.commit()


## セルを構築（通行可能/不可能で色分け）
func _build_cells() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_cell_material)

	var cell_size_val: float = grid_manager.cell_size
	var width: int = grid_manager.grid_width
	var height: int = grid_manager.grid_height
	var origin: Vector3 = grid_manager.grid_origin
	var y: float = origin.y + cell_height

	var margin: float = cell_size_val * 0.05  # セル間のマージン

	for gz in range(height):
		for gx in range(width):
			var cell: Vector2i = Vector2i(gx, gz)
			var walkable: bool = grid_manager.is_walkable(cell)

			if walkable and not show_walkable:
				continue
			if not walkable and not show_blocked:
				continue

			var color: Color = walkable_color if walkable else blocked_color
			var center: Vector3 = grid_manager.cell_to_world(cell)

			var half: float = (cell_size_val - margin * 2) / 2.0
			var v0: Vector3 = Vector3(center.x - half, y, center.z - half)
			var v1: Vector3 = Vector3(center.x + half, y, center.z - half)
			var v2: Vector3 = Vector3(center.x + half, y, center.z + half)
			var v3: Vector3 = Vector3(center.x - half, y, center.z + half)

			# 三角形1
			st.set_color(color)
			st.add_vertex(v0)
			st.set_color(color)
			st.add_vertex(v1)
			st.set_color(color)
			st.add_vertex(v2)

			# 三角形2
			st.set_color(color)
			st.add_vertex(v0)
			st.set_color(color)
			st.add_vertex(v2)
			st.set_color(color)
			st.add_vertex(v3)

	_cells_mesh.mesh = st.commit()


## パスを表示
func show_path(cells: Array[Vector2i]) -> void:
	_current_path = cells
	_build_path_mesh()


## パスをクリア
func clear_path() -> void:
	_current_path.clear()
	_path_mesh.mesh = null


## パスメッシュを構築
func _build_path_mesh() -> void:
	if _current_path.is_empty():
		_path_mesh.mesh = null
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_path_material)

	var cell_size_val: float = grid_manager.cell_size
	var origin: Vector3 = grid_manager.grid_origin
	var y: float = origin.y + cell_height * 2  # パスはセルより上に表示

	var margin: float = cell_size_val * 0.15

	for i in range(_current_path.size()):
		var cell: Vector2i = _current_path[i]
		var center: Vector3 = grid_manager.cell_to_world(cell)

		# 開始・終了・途中で色を変える
		var color: Color
		if i == 0:
			color = path_start_color
		elif i == _current_path.size() - 1:
			color = path_end_color
		else:
			color = path_color

		var half: float = (cell_size_val - margin * 2) / 2.0
		var v0: Vector3 = Vector3(center.x - half, y, center.z - half)
		var v1: Vector3 = Vector3(center.x + half, y, center.z - half)
		var v2: Vector3 = Vector3(center.x + half, y, center.z + half)
		var v3: Vector3 = Vector3(center.x - half, y, center.z + half)

		# 三角形1
		st.set_color(color)
		st.add_vertex(v0)
		st.set_color(color)
		st.add_vertex(v1)
		st.set_color(color)
		st.add_vertex(v2)

		# 三角形2
		st.set_color(color)
		st.add_vertex(v0)
		st.set_color(color)
		st.add_vertex(v2)
		st.set_color(color)
		st.add_vertex(v3)

	_path_mesh.mesh = st.commit()


## フリーハンドパスを変換して表示
func show_freehand_path(freehand_points: Array) -> void:
	if not grid_manager:
		return

	var converter = PathGridConverterClass.new(grid_manager)
	var cells = converter.convert_path(freehand_points)
	var optimized = converter.optimize_path(cells)
	show_path(optimized)


## 表示設定を更新
func update_visibility() -> void:
	_grid_lines_mesh.visible = show_grid_lines
	_cells_mesh.visible = show_cells


## グリッドを再構築
func rebuild() -> void:
	_build_visualization()
