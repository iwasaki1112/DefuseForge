class_name PathLineMesh
extends MeshInstance3D

## パスの線描画
## ドットライン（シェーダーベース）+ 先端にドーナツ型の円

@export var line_height: float = 0.15  # 地面からの高さ
@export var line_width: float = GameConstants.PATH_LINE_WIDTH  # 線の幅（GameConstantsと統一）
@export var line_color: Color = Color(0.0, 1.0, 0.0, 1.0)  # 緑
@export var end_circle_radius: float = 0.15  # 先端円の半径
@export var end_circle_thickness: float = 0.04  # 先端円の太さ
@export var circle_segments: int = 24  # 円のセグメント数
@export var joint_segments: int = 8  # ジョイント円のセグメント数
## ドットライン設定
@export var dot_radius: float = 0.12  # ドットの半径（ワールド単位）
@export var dot_spacing: float = 0.5  # ドットの間隔（ワールド単位）
@export var flow_speed: float = 1.5  # 流れる速度

## 通過した距離（アニメーション連続性用）
var _path_offset: float = 0.0

var _array_mesh: ArrayMesh
var _shader_material: ShaderMaterial
var _circle_material: StandardMaterial3D  # 先端円用（実線）

## シェーダーのパス
const DOTTED_LINE_SHADER_PATH = "res://shaders/path_dotted_line.gdshader"


func _ready() -> void:
	_setup_mesh()


func _setup_mesh() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	# ドットライン用シェーダーマテリアル
	_shader_material = ShaderMaterial.new()
	var shader = load(DOTTED_LINE_SHADER_PATH)
	if shader:
		_shader_material.shader = shader
		_shader_material.set_shader_parameter("line_color", line_color)
		_shader_material.set_shader_parameter("dot_radius", dot_radius)
		_shader_material.set_shader_parameter("dot_spacing", dot_spacing)
		_shader_material.set_shader_parameter("flow_speed", flow_speed)
		_shader_material.set_shader_parameter("line_width_world", line_width)
		_shader_material.render_priority = 2  # Fogより上に描画

	# 先端円用マテリアル（実線）
	_circle_material = StandardMaterial3D.new()
	_circle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_circle_material.albedo_color = line_color
	_circle_material.emission_enabled = true
	_circle_material.emission = line_color
	_circle_material.emission_energy_multiplier = 1.5
	_circle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_circle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_circle_material.render_priority = 2


## ポイント配列から線メッシュを生成
func update_from_points(points: PackedVector3Array) -> void:
	if _array_mesh == null:
		_setup_mesh()

	if points.size() < 2:
		_array_mesh.clear_surfaces()
		return

	_array_mesh.clear_surfaces()

	# サーフェス0: ドットライン（シェーダー使用）
	var line_vertices = PackedVector3Array()
	var line_uvs = PackedVector2Array()
	var line_indices = PackedInt32Array()
	_add_dotted_line(line_vertices, line_uvs, line_indices, points)

	if line_vertices.size() > 0:
		var line_arrays = []
		line_arrays.resize(Mesh.ARRAY_MAX)
		line_arrays[Mesh.ARRAY_VERTEX] = line_vertices
		line_arrays[Mesh.ARRAY_TEX_UV] = line_uvs
		line_arrays[Mesh.ARRAY_INDEX] = line_indices
		_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, line_arrays)
		_array_mesh.surface_set_material(0, _shader_material)

	# サーフェス1: 先端円（実線マテリアル）
	var circle_vertices = PackedVector3Array()
	var circle_indices = PackedInt32Array()
	var end_pos = points[points.size() - 1]
	_add_ring_circle(circle_vertices, circle_indices, Vector3(end_pos.x, line_height, end_pos.z))

	if circle_vertices.size() > 0:
		var circle_arrays = []
		circle_arrays.resize(Mesh.ARRAY_MAX)
		circle_arrays[Mesh.ARRAY_VERTEX] = circle_vertices
		circle_arrays[Mesh.ARRAY_INDEX] = circle_indices
		_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, circle_arrays)
		_array_mesh.surface_set_material(_array_mesh.get_surface_count() - 1, _circle_material)


## ドットラインを描画（UV座標付き、ジョイント円付き）
func _add_dotted_line(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, points: PackedVector3Array) -> void:
	var half_width = line_width * 0.5

	# パス全体の長さを計算
	var cumulative_distance: float = 0.0

	# 各セグメントを連続して描画
	for i in range(1, points.size()):
		var start_pos = points[i - 1]
		var end_pos = points[i]
		var segment_length = start_pos.distance_to(end_pos)
		var dir = (end_pos - start_pos).normalized()

		if dir.length_squared() > 0.001:
			var start_dist = cumulative_distance
			var end_dist = cumulative_distance + segment_length
			_add_line_segment_with_uv(vertices, uvs, indices, start_pos, end_pos, dir, half_width, start_dist, end_dist)

		cumulative_distance += segment_length

	# 各ポイントにジョイント円を追加（終点を除く - 終点はリング円がある）
	var joint_distance: float = 0.0
	for i in range(0, points.size() - 1):
		var pos = points[i]
		_add_joint_circle_with_uv(vertices, uvs, indices, Vector3(pos.x, line_height, pos.z), half_width, joint_distance)
		if i < points.size() - 1:
			joint_distance += points[i].distance_to(points[i + 1])


## 線分セグメントを追加（UV座標付き）
func _add_line_segment_with_uv(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, start: Vector3, end: Vector3, dir: Vector3, half_width: float, start_dist: float, end_dist: float) -> void:
	var base_index = vertices.size()

	# 幅方向
	var right = Vector3(-dir.z, 0, dir.x).normalized() * half_width

	# 4頂点（UV.x = パスに沿った距離、UV.y = 幅方向 0-1）
	vertices.append(Vector3(start.x - right.x, line_height, start.z - right.z))
	uvs.append(Vector2(start_dist, 0.0))

	vertices.append(Vector3(start.x + right.x, line_height, start.z + right.z))
	uvs.append(Vector2(start_dist, 1.0))

	vertices.append(Vector3(end.x - right.x, line_height, end.z - right.z))
	uvs.append(Vector2(end_dist, 0.0))

	vertices.append(Vector3(end.x + right.x, line_height, end.z + right.z))
	uvs.append(Vector2(end_dist, 1.0))

	# 2三角形
	indices.append(base_index)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index + 3)
	indices.append(base_index + 2)


## ジョイント円を追加（UV座標付き、セグメント間の隙間を埋める）
func _add_joint_circle_with_uv(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, center: Vector3, radius: float, distance: float) -> void:
	var base_index = vertices.size()

	# 中心頂点
	vertices.append(center)
	uvs.append(Vector2(distance, 0.5))

	# 円周上の頂点
	for i in range(joint_segments):
		var angle = TAU * i / joint_segments
		vertices.append(Vector3(
			center.x + cos(angle) * radius,
			center.y,
			center.z + sin(angle) * radius
		))
		# UV.y は角度に応じて0-1
		var uv_y = (sin(angle) + 1.0) * 0.5
		uvs.append(Vector2(distance, uv_y))

	# 三角形で扇形を描画
	for i in range(joint_segments):
		var curr = base_index + 1 + i
		var next = base_index + 1 + ((i + 1) % joint_segments)
		indices.append(base_index)  # 中心
		indices.append(curr)
		indices.append(next)


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
	# シェーダーマテリアル（ドットライン）
	if _shader_material:
		_shader_material.set_shader_parameter("line_color", color)
	# 先端円マテリアル
	if _circle_material:
		_circle_material.albedo_color = color
		_circle_material.emission = color


## 線幅を変更（シェーダーパラメータも更新）
func set_line_width(width: float) -> void:
	line_width = width
	if _shader_material:
		_shader_material.set_shader_parameter("line_width_world", width)


## シェーダーパラメータを再設定（プールからの再利用時に呼ばれる）
func refresh_shader_parameters() -> void:
	if _shader_material:
		_shader_material.set_shader_parameter("line_color", line_color)
		_shader_material.set_shader_parameter("dot_radius", dot_radius)
		_shader_material.set_shader_parameter("dot_spacing", dot_spacing)
		_shader_material.set_shader_parameter("flow_speed", flow_speed)
		_shader_material.set_shader_parameter("line_width_world", line_width)
		_shader_material.set_shader_parameter("path_offset", _path_offset)
	if _circle_material:
		_circle_material.albedo_color = line_color
		_circle_material.emission = line_color


## 通過距離オフセットを設定（アニメーション連続性用）
func set_path_offset(offset: float) -> void:
	_path_offset = offset
	if _shader_material:
		_shader_material.set_shader_parameter("path_offset", offset)


## 通過距離オフセットをリセット
func reset_path_offset() -> void:
	set_path_offset(0.0)


## メッシュをクリア
func clear() -> void:
	if _array_mesh:
		_array_mesh.clear_surfaces()
