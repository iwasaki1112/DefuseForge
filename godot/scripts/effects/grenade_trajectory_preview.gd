class_name GrenadeTrajectoryPreview
extends RefCounted
## グレネード軌道プレビュー
## スモークグレネードのターゲット選択モード中に
## 投擲地点から着弾地点までの放物線軌道をリアルタイム表示する

## 描画設定
const LINE_HEIGHT: float = 0.15  ## 地面からの高さ
const LINE_WIDTH: float = 0.08  ## 弧の幅
const ARC_SEGMENTS: int = 20  ## 放物線の分割数
const RING_RADIUS: float = 0.2  ## 着弾リングの半径
const RING_THICKNESS: float = 0.04  ## 着弾リングの太さ
const RING_SEGMENTS: int = 24  ## リングのセグメント数
const ARC_COLOR: Color = Color(0.8, 0.4, 0.1, 0.8)  ## オレンジ系

## 物理パラメータ（Grenadeクラスと統一）
const ARC_HEIGHT: float = 2.0
const GRAVITY: float = 9.8

## シェーダーパス
const DOTTED_LINE_SHADER_PATH = "res://shaders/path_dotted_line.gdshader"

## 内部メッシュ
var _arc_mesh: MeshInstance3D = null
var _impact_ring: MeshInstance3D = null
var _parent: Node3D = null

## マテリアル
var _arc_material: ShaderMaterial = null
var _ring_material: StandardMaterial3D = null


## 親ノードに追加してメッシュを初期化
func setup(parent: Node3D) -> void:
	_parent = parent

	# 弧メッシュ
	_arc_mesh = MeshInstance3D.new()
	_arc_mesh.name = "GrenadeTrajectoryArc"
	_arc_mesh.visible = false
	parent.add_child(_arc_mesh)

	# 着弾リング
	_impact_ring = MeshInstance3D.new()
	_impact_ring.name = "GrenadeTrajectoryRing"
	_impact_ring.visible = false
	parent.add_child(_impact_ring)

	_setup_materials()


## マテリアルを初期化
func _setup_materials() -> void:
	# 弧用シェーダーマテリアル
	_arc_material = ShaderMaterial.new()
	var shader = load(DOTTED_LINE_SHADER_PATH)
	if shader:
		_arc_material.shader = shader
		_arc_material.set_shader_parameter("line_color", ARC_COLOR)
		_arc_material.set_shader_parameter("dot_radius", 0.08)
		_arc_material.set_shader_parameter("dot_spacing", 0.3)
		_arc_material.set_shader_parameter("flow_speed", 2.0)
		_arc_material.set_shader_parameter("line_width_world", LINE_WIDTH)
		_arc_material.render_priority = 2

	# 着弾リング用マテリアル
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = ARC_COLOR
	_ring_material.emission_enabled = true
	_ring_material.emission = ARC_COLOR
	_ring_material.emission_energy_multiplier = 1.5
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.render_priority = 2


## 軌道を更新（投擲位置とターゲット位置から放物線を計算）
func update(start_pos: Vector3, target_pos: Vector3) -> void:
	if not _arc_mesh or not _impact_ring:
		return

	# 放物線サンプル点を計算
	var arc_points := _calculate_arc_points(start_pos, target_pos)
	if arc_points.size() < 2:
		clear()
		return

	# 弧メッシュを更新
	_update_arc_mesh(arc_points)
	_arc_mesh.visible = true

	# 着弾リングを更新
	_update_impact_ring(target_pos)
	_impact_ring.visible = true


## メッシュを非表示
func clear() -> void:
	if _arc_mesh:
		_arc_mesh.visible = false
	if _impact_ring:
		_impact_ring.visible = false


## メッシュを削除
func destroy() -> void:
	if _arc_mesh and is_instance_valid(_arc_mesh):
		_arc_mesh.queue_free()
		_arc_mesh = null
	if _impact_ring and is_instance_valid(_impact_ring):
		_impact_ring.queue_free()
		_impact_ring = null
	_parent = null


## 放物線のサンプル点を計算（Grenade._calculate_throw_velocityと同じ物理式）
func _calculate_arc_points(start: Vector3, target: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var displacement := target - start
	var horizontal := Vector3(displacement.x, 0, displacement.z)
	var horizontal_distance := horizontal.length()
	var delta_y := displacement.y
	var g := GRAVITY

	if horizontal_distance < 0.3:
		return points

	var horizontal_dir := horizontal.normalized()

	# 放物線の頂点高さ
	var peak_height := ARC_HEIGHT
	if delta_y < 0:
		peak_height = maxf(peak_height, absf(delta_y) * 0.3 + 0.3)

	# 垂直初速度
	var vy := sqrt(2.0 * g * peak_height)

	# 飛行時間
	var discriminant := vy * vy - 2.0 * g * delta_y
	var flight_time: float
	if discriminant >= 0:
		flight_time = (vy + sqrt(discriminant)) / g
	else:
		peak_height = absf(delta_y) + 1.0
		vy = sqrt(2.0 * g * peak_height)
		discriminant = vy * vy - 2.0 * g * delta_y
		flight_time = (vy + sqrt(discriminant)) / g

	flight_time = maxf(flight_time, 0.2)

	# 水平速度
	var horizontal_speed := horizontal_distance / flight_time
	if horizontal_speed > 15.0:
		horizontal_speed = 15.0
		flight_time = horizontal_distance / horizontal_speed
		vy = (delta_y + 0.5 * g * flight_time * flight_time) / flight_time

	# サンプリング
	for i in range(ARC_SEGMENTS + 1):
		var t := flight_time * i / ARC_SEGMENTS
		var pos := Vector3.ZERO
		pos.x = start.x + horizontal_dir.x * horizontal_speed * t
		pos.z = start.z + horizontal_dir.z * horizontal_speed * t
		pos.y = start.y + vy * t - 0.5 * g * t * t
		# 地面より下にならないようにクランプ
		pos.y = maxf(pos.y, 0.0)
		points.append(pos)

	return points


## 弧メッシュを更新
func _update_arc_mesh(points: PackedVector3Array) -> void:
	var array_mesh := ArrayMesh.new()

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var half_width := LINE_WIDTH * 0.5
	var cumulative_distance := 0.0

	for i in range(1, points.size()):
		var start_pos := points[i - 1]
		var end_pos := points[i]
		var segment_length := start_pos.distance_to(end_pos)
		var dir := (end_pos - start_pos).normalized()

		if dir.length_squared() < 0.001:
			cumulative_distance += segment_length
			continue

		var start_dist := cumulative_distance
		var end_dist := cumulative_distance + segment_length

		# 幅方向（水平面上のみ）
		var horizontal_dir := Vector3(dir.x, 0, dir.z)
		if horizontal_dir.length_squared() < 0.001:
			horizontal_dir = Vector3(1, 0, 0)
		horizontal_dir = horizontal_dir.normalized()
		var right := Vector3(-horizontal_dir.z, 0, horizontal_dir.x) * half_width

		var base_index := vertices.size()

		# 4頂点（3D空間での放物線を描画）
		vertices.append(Vector3(start_pos.x - right.x, start_pos.y, start_pos.z - right.z))
		uvs.append(Vector2(start_dist, 0.0))

		vertices.append(Vector3(start_pos.x + right.x, start_pos.y, start_pos.z + right.z))
		uvs.append(Vector2(start_dist, 1.0))

		vertices.append(Vector3(end_pos.x - right.x, end_pos.y, end_pos.z - right.z))
		uvs.append(Vector2(end_dist, 0.0))

		vertices.append(Vector3(end_pos.x + right.x, end_pos.y, end_pos.z + right.z))
		uvs.append(Vector2(end_dist, 1.0))

		# 2三角形
		indices.append(base_index)
		indices.append(base_index + 1)
		indices.append(base_index + 2)
		indices.append(base_index + 1)
		indices.append(base_index + 3)
		indices.append(base_index + 2)

		cumulative_distance += segment_length

	if vertices.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		array_mesh.surface_set_material(0, _arc_material)

	_arc_mesh.mesh = array_mesh


## 着弾リングを更新
func _update_impact_ring(target_pos: Vector3) -> void:
	var array_mesh := ArrayMesh.new()

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var inner_radius := RING_RADIUS - RING_THICKNESS
	var outer_radius := RING_RADIUS
	var center := Vector3(target_pos.x, LINE_HEIGHT, target_pos.z)

	# 内外周の頂点を生成
	for i in range(RING_SEGMENTS):
		var angle := TAU * i / RING_SEGMENTS
		var cos_a := cos(angle)
		var sin_a := sin(angle)

		# 内周
		vertices.append(Vector3(
			center.x + cos_a * inner_radius,
			center.y,
			center.z + sin_a * inner_radius
		))
		# 外周
		vertices.append(Vector3(
			center.x + cos_a * outer_radius,
			center.y,
			center.z + sin_a * outer_radius
		))

	# 三角形でリングを描画
	for i in range(RING_SEGMENTS):
		var curr_inner := i * 2
		var curr_outer := i * 2 + 1
		var next_inner := ((i + 1) % RING_SEGMENTS) * 2
		var next_outer := ((i + 1) % RING_SEGMENTS) * 2 + 1

		indices.append(curr_inner)
		indices.append(curr_outer)
		indices.append(next_inner)
		indices.append(curr_outer)
		indices.append(next_outer)
		indices.append(next_inner)

	if vertices.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		array_mesh.surface_set_material(0, _ring_material)

	_impact_ring.mesh = array_mesh
