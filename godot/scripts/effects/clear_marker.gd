class_name ClearMarker
extends MeshInstance3D

## Clearポイントマーカー
## 円形背景と回転アイコンで「リセット」を示す
## このポイント以降はVision/Runがクリアされ、進行方向を向く

@export var circle_radius: float = 0.3
@export var circle_color: Color = Color(0.2, 0.6, 0.9, 0.95)  # 青系
@export var icon_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var height_offset: float = 0.03
@export var segments: int = 32


func _ready() -> void:
	_build_mesh()


## 位置を設定
func set_marker_position(pos: Vector3) -> void:
	global_position = Vector3(pos.x, pos.y + height_offset, pos.z)


## 色を変更
func set_colors(bg_color: Color, fg_color: Color) -> void:
	circle_color = bg_color
	icon_color = fg_color
	_build_mesh()


func _build_mesh() -> void:
	var array_mesh = ArrayMesh.new()

	# 1. 塗りつぶし円を生成
	_build_circle_mesh(array_mesh)

	# 2. リセットアイコン（円形矢印風）を生成
	_build_icon_mesh(array_mesh)

	mesh = array_mesh


func _build_circle_mesh(array_mesh: ArrayMesh) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 塗りつぶし円
	var center = Vector3.ZERO
	for i in range(segments):
		var angle1 = TAU * i / segments
		var angle2 = TAU * (i + 1) / segments
		var p1 = Vector3(cos(angle1) * circle_radius, 0, sin(angle1) * circle_radius)
		var p2 = Vector3(cos(angle2) * circle_radius, 0, sin(angle2) * circle_radius)

		st.set_color(circle_color)
		st.set_normal(Vector3.UP)
		st.add_vertex(center)
		st.add_vertex(p1)
		st.add_vertex(p2)

	st.commit(array_mesh)

	# マテリアル設定
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.render_priority = 10
	mat.no_depth_test = true
	array_mesh.surface_set_material(0, mat)


func _build_icon_mesh(array_mesh: ArrayMesh) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# リセットアイコン: 円弧と矢印（リフレッシュ/リセット記号）
	var icon_radius = circle_radius * 0.5
	var thickness = 0.03
	var y_offset = 0.001  # 円より少し上

	# 円弧（270度分）
	var arc_segments = 20
	var arc_start = PI * 0.25  # 45度から開始
	var arc_end = PI * 2.0  # 360度まで（315度分の円弧）

	for i in range(arc_segments):
		var t1 = float(i) / arc_segments
		var t2 = float(i + 1) / arc_segments
		var angle1 = arc_start + (arc_end - arc_start) * t1
		var angle2 = arc_start + (arc_end - arc_start) * t2

		var inner_r = icon_radius - thickness
		var outer_r = icon_radius + thickness

		var p1_inner = Vector3(cos(angle1) * inner_r, y_offset, sin(angle1) * inner_r)
		var p1_outer = Vector3(cos(angle1) * outer_r, y_offset, sin(angle1) * outer_r)
		var p2_inner = Vector3(cos(angle2) * inner_r, y_offset, sin(angle2) * inner_r)
		var p2_outer = Vector3(cos(angle2) * outer_r, y_offset, sin(angle2) * outer_r)

		st.set_color(icon_color)
		st.set_normal(Vector3.UP)

		# 2つの三角形でクアッドを形成
		st.add_vertex(p1_inner)
		st.add_vertex(p1_outer)
		st.add_vertex(p2_outer)

		st.add_vertex(p1_inner)
		st.add_vertex(p2_outer)
		st.add_vertex(p2_inner)

	# 矢印の先端（円弧の終点に付ける）
	var arrow_angle = arc_end
	var arrow_tip = Vector3(cos(arrow_angle) * icon_radius, y_offset, sin(arrow_angle) * icon_radius)
	var arrow_size = thickness * 3.0

	# 矢印の方向（円の接線方向、時計回り）
	var tangent = Vector3(-sin(arrow_angle), 0, cos(arrow_angle))
	var outward = Vector3(cos(arrow_angle), 0, sin(arrow_angle))

	# 矢印の3点
	var arrow_p1 = arrow_tip + tangent * arrow_size
	var arrow_p2 = arrow_tip - outward * arrow_size * 0.7
	var arrow_p3 = arrow_tip + outward * arrow_size * 0.7

	st.set_color(icon_color)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(arrow_p1.x, y_offset, arrow_p1.z))
	st.add_vertex(Vector3(arrow_p2.x, y_offset, arrow_p2.z))
	st.add_vertex(Vector3(arrow_p3.x, y_offset, arrow_p3.z))

	st.commit(array_mesh)

	# マテリアル設定（発光あり）
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = icon_color
	mat.emission_energy_multiplier = 1.2
	mat.render_priority = 11
	mat.no_depth_test = true
	array_mesh.surface_set_material(1, mat)
