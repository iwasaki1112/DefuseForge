extends Node3D

## パス描画レンダラー
## 3Dメッシュでパスを描画

const PathAnalyzerClass = preload("res://scripts/systems/path/path_analyzer.gd")

@export_group("描画設定")
@export var path_color_walk: Color = Color(0.0, 1.0, 0.0, 0.5)
@export var path_color_run: Color = Color(1.0, 0.5, 0.0, 0.5)
@export var path_width: float = 0.15
@export var path_height_offset: float = 0.05
@export var smoothing_segments: int = 5
@export var cull_margin: float = 50.0  # 適切なカリングマージン

# キャラクターカラー（設定時に使用）
var character_base_color: Color = Color.GREEN

# 描画用メッシュ
var path_mesh_instance_walk: MeshInstance3D = null
var path_mesh_instance_run: MeshInstance3D = null
var immediate_mesh_walk: ImmediateMesh = null
var immediate_mesh_run: ImmediateMesh = null

# パス解析器
var analyzer: RefCounted = null

# パスキャッシュ（変更検出用）
var _cached_path: Array[Vector3] = []
var _cached_run_flags: Array[bool] = []


func _ready() -> void:
	analyzer = PathAnalyzerClass.new()

	# 歩き用メッシュを作成
	immediate_mesh_walk = ImmediateMesh.new()
	path_mesh_instance_walk = MeshInstance3D.new()
	path_mesh_instance_walk.mesh = immediate_mesh_walk
	path_mesh_instance_walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mesh_instance_walk.material_override = _create_path_material(path_color_walk, Color(0.0, 1.0, 0.0, 1.0))
	path_mesh_instance_walk.extra_cull_margin = cull_margin  # 適切なカリングマージン
	add_child(path_mesh_instance_walk)

	# 走り用メッシュを作成
	immediate_mesh_run = ImmediateMesh.new()
	path_mesh_instance_run = MeshInstance3D.new()
	path_mesh_instance_run.mesh = immediate_mesh_run
	path_mesh_instance_run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mesh_instance_run.material_override = _create_path_material(path_color_run, Color(1.0, 0.5, 0.0, 1.0))
	path_mesh_instance_run.extra_cull_margin = cull_margin  # 適切なカリングマージン
	add_child(path_mesh_instance_run)


## キャラクターカラーを設定
## 歩き=通常色（半透明）、走り=濃い色（半透明）
func set_character_color(base_color: Color) -> void:
	character_base_color = base_color

	# 歩き用の色（通常色、半透明）
	path_color_walk = Color(base_color.r, base_color.g, base_color.b, 0.5)

	# 走り用の色（濃い色、半透明）
	var dark_color := base_color.darkened(0.3)
	path_color_run = Color(dark_color.r, dark_color.g, dark_color.b, 0.7)

	# マテリアルを更新
	if path_mesh_instance_walk and path_mesh_instance_walk.material_override:
		var walk_material := path_mesh_instance_walk.material_override as StandardMaterial3D
		walk_material.albedo_color = path_color_walk
		walk_material.emission = Color(base_color.r, base_color.g, base_color.b, 1.0)

	if path_mesh_instance_run and path_mesh_instance_run.material_override:
		var run_material := path_mesh_instance_run.material_override as StandardMaterial3D
		run_material.albedo_color = path_color_run
		run_material.emission = Color(dark_color.r, dark_color.g, dark_color.b, 1.0)


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


## パスが変更されたかチェック
func _is_path_changed(path: Array[Vector3], run_flags: Array[bool]) -> bool:
	if path.size() != _cached_path.size():
		return true
	if run_flags.size() != _cached_run_flags.size():
		return true
	for i in range(path.size()):
		if not path[i].is_equal_approx(_cached_path[i]):
			return true
	for i in range(run_flags.size()):
		if run_flags[i] != _cached_run_flags[i]:
			return true
	return false


## パスを描画
func render(path: Array[Vector3], run_flags: Array[bool]) -> void:
	# パスが変更されていない場合はスキップ
	if not _is_path_changed(path, run_flags):
		return

	# キャッシュを更新
	_cached_path = path.duplicate()
	_cached_run_flags = run_flags.duplicate()

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
	_cached_path.clear()
	_cached_run_flags.clear()


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
