extends Node3D

## パス描画レンダラー
## 3Dメッシュでパスを描画

const PathAnalyzerClass = preload("res://scripts/systems/path/path_analyzer.gd")

@export_group("描画設定")
@export var path_color_walk: Color = Color(0.0, 1.0, 0.0, 0.5)
@export var path_color_run: Color = Color(1.0, 0.5, 0.0, 0.5)
@export var path_width: float = 0.15
@export var path_height_offset: float = 0.001
@export var smoothing_segments: int = 5

# 描画用メッシュ
var path_mesh_instance_walk: MeshInstance3D = null
var path_mesh_instance_run: MeshInstance3D = null
var immediate_mesh_walk: ImmediateMesh = null
var immediate_mesh_run: ImmediateMesh = null

# パス解析器
var analyzer: RefCounted = null


func _ready() -> void:
	analyzer = PathAnalyzerClass.new()

	# 歩き用メッシュを作成
	immediate_mesh_walk = ImmediateMesh.new()
	path_mesh_instance_walk = MeshInstance3D.new()
	path_mesh_instance_walk.mesh = immediate_mesh_walk
	path_mesh_instance_walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mesh_instance_walk.material_override = _create_path_material(path_color_walk, Color(0.0, 1.0, 0.0, 1.0))
	add_child(path_mesh_instance_walk)

	# 走り用メッシュを作成
	immediate_mesh_run = ImmediateMesh.new()
	path_mesh_instance_run = MeshInstance3D.new()
	path_mesh_instance_run.mesh = immediate_mesh_run
	path_mesh_instance_run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mesh_instance_run.material_override = _create_path_material(path_color_run, Color(1.0, 0.5, 0.0, 1.0))
	add_child(path_mesh_instance_run)


## パス用マテリアルを作成
func _create_path_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.disable_receive_shadows = false
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 0.5
	return material


## パスを描画
func render(path: Array[Vector3], run_flags: Array[bool]) -> void:
	immediate_mesh_walk.clear_surfaces()
	immediate_mesh_run.clear_surfaces()

	if path.size() < 2:
		return

	# セグメントごとに歩き/走りを分けて描画
	for seg_idx in range(path.size() - 1):
		var p1 := path[seg_idx]
		var p2 := path[seg_idx + 1]

		var is_run := false
		if seg_idx < run_flags.size():
			is_run = run_flags[seg_idx]

		var mesh: ImmediateMesh = immediate_mesh_run if is_run else immediate_mesh_walk
		_draw_segment(mesh, p1, p2)

	# 終点キャップ
	if path.size() >= 2:
		var last_run := false
		if run_flags.size() > 0:
			last_run = run_flags[run_flags.size() - 1]
		var mesh: ImmediateMesh = immediate_mesh_run if last_run else immediate_mesh_walk
		var end_point: Vector3 = path[path.size() - 1]
		end_point.y += path_height_offset
		var end_dir := (path[path.size() - 1] - path[path.size() - 2]).normalized()
		_draw_round_cap(mesh, end_point, end_dir)


## パスをクリア
func clear() -> void:
	immediate_mesh_walk.clear_surfaces()
	immediate_mesh_run.clear_surfaces()


## 1セグメントを描画
func _draw_segment(mesh: ImmediateMesh, p1: Vector3, p2: Vector3) -> void:
	var segment_points: Array[Vector3] = [p1, p2]
	var smooth: Array[Vector3] = analyzer.generate_smooth_path(segment_points, smoothing_segments)

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in range(smooth.size()):
		var point: Vector3 = smooth[i]
		point.y += path_height_offset

		var direction := Vector3.ZERO
		if i < smooth.size() - 1:
			direction = (smooth[i + 1] - smooth[i]).normalized()
		elif i > 0:
			direction = (smooth[i] - smooth[i - 1]).normalized()

		var up := Vector3.UP
		var right := direction.cross(up).normalized() * path_width * 0.5

		if right.length() < 0.01:
			right = Vector3.RIGHT * path_width * 0.5

		mesh.surface_add_vertex(point - right)
		mesh.surface_add_vertex(point + right)

	mesh.surface_end()


## 角丸キャップを描画
func _draw_round_cap(mesh: ImmediateMesh, center: Vector3, direction: Vector3) -> void:
	var up := Vector3.UP
	var right := direction.cross(up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT

	var segments := 8
	var radius := path_width * 0.5

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var start_angle := -PI * 0.5
	var end_angle := PI * 0.5

	for i in range(segments):
		var angle1 := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		var angle2 := start_angle + (end_angle - start_angle) * float(i + 1) / float(segments)

		mesh.surface_add_vertex(center)
		var offset1 := right * cos(angle1) * radius + direction * sin(angle1) * radius
		var offset2 := right * cos(angle2) * radius + direction * sin(angle2) * radius
		mesh.surface_add_vertex(center + offset1)
		mesh.surface_add_vertex(center + offset2)

	mesh.surface_end()
