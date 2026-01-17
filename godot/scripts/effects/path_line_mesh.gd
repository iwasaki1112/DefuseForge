class_name PathLineMesh
extends MeshInstance3D

## パスの線描画
## 破線 + 先端にドーナツ型の円

@export var line_height: float = 0.02  # 地面からの高さ
@export var line_width: float = 0.04   # 線の幅
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)  # 白
@export var dash_length: float = 0.15  # 破線の長さ
@export var gap_length: float = 0.1    # 破線の間隔
@export var end_circle_radius: float = 0.15  # 先端円の半径
@export var end_circle_thickness: float = 0.04  # 先端円の太さ
@export var circle_segments: int = 24  # 円のセグメント数

var _array_mesh: ArrayMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_setup_mesh()


func _setup_mesh() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	# 発光マテリアル
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = line_color
	_material.emission_enabled = true
	_material.emission = line_color
	_material.emission_energy_multiplier = 1.5
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _material


## ポイント配列から線メッシュを生成
func update_from_points(points: PackedVector3Array) -> void:
	if _array_mesh == null:
		_setup_mesh()

	if points.size() < 2:
		_array_mesh.clear_surfaces()
		return

	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	# パスに沿って破線を描画
	_add_dashed_line(vertices, indices, points)

	# 終点にドーナツ円を追加
	var end_pos = points[points.size() - 1]
	_add_ring_circle(vertices, indices, Vector3(end_pos.x, line_height, end_pos.z))

	# メッシュを構築
	_array_mesh.clear_surfaces()

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(0, _material)


## 破線を描画
func _add_dashed_line(vertices: PackedVector3Array, indices: PackedInt32Array, points: PackedVector3Array) -> void:
	var half_width = line_width * 0.5
	var total_length = 0.0

	# 各セグメントの累積距離を計算
	var segment_lengths: Array[float] = [0.0]
	for i in range(1, points.size()):
		total_length += points[i].distance_to(points[i - 1])
		segment_lengths.append(total_length)

	# 破線パターンで描画
	var dash_cycle = dash_length + gap_length
	var current_dist = 0.0

	while current_dist < total_length:
		var dash_start = current_dist
		var dash_end = minf(current_dist + dash_length, total_length)

		if dash_end > dash_start:
			var start_pos = _get_position_at_distance(points, segment_lengths, dash_start)
			var end_pos = _get_position_at_distance(points, segment_lengths, dash_end)
			var dir = (end_pos - start_pos).normalized()

			if dir.length_squared() > 0.001:
				_add_line_segment(vertices, indices, start_pos, end_pos, dir, half_width)

		current_dist += dash_cycle


## 指定距離でのパス上の位置を取得
func _get_position_at_distance(points: PackedVector3Array, segment_lengths: Array[float], distance: float) -> Vector3:
	for i in range(1, points.size()):
		if segment_lengths[i] >= distance:
			var seg_start = segment_lengths[i - 1]
			var seg_length = segment_lengths[i] - seg_start
			if seg_length > 0:
				var t = (distance - seg_start) / seg_length
				return points[i - 1].lerp(points[i], t)
			return points[i - 1]
	return points[points.size() - 1]


## 線分セグメントを追加
func _add_line_segment(vertices: PackedVector3Array, indices: PackedInt32Array, start: Vector3, end: Vector3, dir: Vector3, half_width: float) -> void:
	var base_index = vertices.size()

	# 幅方向
	var right = Vector3(-dir.z, 0, dir.x).normalized() * half_width

	# 4頂点
	vertices.append(Vector3(start.x - right.x, line_height, start.z - right.z))
	vertices.append(Vector3(start.x + right.x, line_height, start.z + right.z))
	vertices.append(Vector3(end.x - right.x, line_height, end.z - right.z))
	vertices.append(Vector3(end.x + right.x, line_height, end.z + right.z))

	# 2三角形
	indices.append(base_index)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index + 3)
	indices.append(base_index + 2)


## ドーナツ型の円（リング）を追加
func _add_ring_circle(vertices: PackedVector3Array, indices: PackedInt32Array, center: Vector3) -> void:
	var base_index = vertices.size()
	var inner_radius = end_circle_radius - end_circle_thickness
	var outer_radius = end_circle_radius

	# 内外周の頂点を生成
	for i in range(circle_segments):
		var angle = TAU * i / circle_segments
		var cos_a = cos(angle)
		var sin_a = sin(angle)

		# 内周
		vertices.append(Vector3(
			center.x + cos_a * inner_radius,
			line_height,
			center.z + sin_a * inner_radius
		))
		# 外周
		vertices.append(Vector3(
			center.x + cos_a * outer_radius,
			line_height,
			center.z + sin_a * outer_radius
		))

	# 三角形でリングを描画
	for i in range(circle_segments):
		var curr_inner = base_index + i * 2
		var curr_outer = base_index + i * 2 + 1
		var next_inner = base_index + ((i + 1) % circle_segments) * 2
		var next_outer = base_index + ((i + 1) % circle_segments) * 2 + 1

		# 2三角形で四角形
		indices.append(curr_inner)
		indices.append(curr_outer)
		indices.append(next_inner)
		indices.append(curr_outer)
		indices.append(next_outer)
		indices.append(next_inner)


## 色を変更
func set_line_color(color: Color) -> void:
	line_color = color
	if _material:
		_material.albedo_color = color
		_material.emission = color


## メッシュをクリア
func clear() -> void:
	if _array_mesh:
		_array_mesh.clear_surfaces()
