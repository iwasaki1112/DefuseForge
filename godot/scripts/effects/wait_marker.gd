class_name WaitMarker
extends ActionMarker

## Waitマーカー（円形背景 + 砂時計アイコン）
## パス上でキャラクターが指定時間待機する位置を示す

## 待機時間（秒）
var _wait_duration: float = 1.0

## テキストラベル用
var _duration_label: Label3D = null


func _init() -> void:
	# デフォルト色を設定（黄色/琥珀系 - 待機を連想）
	circle_color = Color(0.8, 0.6, 0.1, 0.95)
	icon_color = Color(1.0, 1.0, 1.0, 1.0)


func get_action_marker_type() -> MarkerType:
	return MarkerType.WAIT


func _build_mesh() -> void:
	var array_mesh = ArrayMesh.new()
	_array_mesh = array_mesh
	mesh = _array_mesh

	# 1. 塗りつぶし円を生成
	_build_circle_mesh()

	# 2. 砂時計アイコンを生成
	_build_icon()


func _build_circle_mesh() -> void:
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

	st.commit(_array_mesh)

	# マテリアル設定
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.render_priority = 10
	mat.no_depth_test = true
	_array_mesh.surface_set_material(0, mat)
	_circle_material = mat


func _build_icon() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 砂時計アイコン: 2つの三角形が中央で接する形
	var y_offset = 0.001  # 円より少し上
	var icon_half_width = circle_radius * 0.35
	var icon_half_height = circle_radius * 0.45
	var neck_width = icon_half_width * 0.15  # くびれ部分

	# 上の三角形（頂点が下を向く）
	var top_left = Vector3(-icon_half_width, y_offset, -icon_half_height)
	var top_right = Vector3(icon_half_width, y_offset, -icon_half_height)
	var top_bottom_left = Vector3(-neck_width, y_offset, 0)
	var top_bottom_right = Vector3(neck_width, y_offset, 0)

	# 下の三角形（頂点が上を向く）
	var bottom_left = Vector3(-icon_half_width, y_offset, icon_half_height)
	var bottom_right = Vector3(icon_half_width, y_offset, icon_half_height)
	var bottom_top_left = Vector3(-neck_width, y_offset, 0)
	var bottom_top_right = Vector3(neck_width, y_offset, 0)

	st.set_color(icon_color)
	st.set_normal(Vector3.UP)

	# 上の三角形（台形風に4頂点）
	st.add_vertex(top_left)
	st.add_vertex(top_right)
	st.add_vertex(top_bottom_right)

	st.add_vertex(top_left)
	st.add_vertex(top_bottom_right)
	st.add_vertex(top_bottom_left)

	# 下の三角形（台形風に4頂点）
	st.add_vertex(bottom_top_left)
	st.add_vertex(bottom_top_right)
	st.add_vertex(bottom_right)

	st.add_vertex(bottom_top_left)
	st.add_vertex(bottom_right)
	st.add_vertex(bottom_left)

	# 枠線を追加（アウトライン効果）
	var frame_thickness = 0.015
	var frame_y = y_offset + 0.001

	# 上の横線
	_add_quad(st, Vector3(-icon_half_width - frame_thickness, frame_y, -icon_half_height - frame_thickness),
			Vector3(icon_half_width + frame_thickness, frame_y, -icon_half_height - frame_thickness),
			Vector3(icon_half_width + frame_thickness, frame_y, -icon_half_height),
			Vector3(-icon_half_width - frame_thickness, frame_y, -icon_half_height))

	# 下の横線
	_add_quad(st, Vector3(-icon_half_width - frame_thickness, frame_y, icon_half_height),
			Vector3(icon_half_width + frame_thickness, frame_y, icon_half_height),
			Vector3(icon_half_width + frame_thickness, frame_y, icon_half_height + frame_thickness),
			Vector3(-icon_half_width - frame_thickness, frame_y, icon_half_height + frame_thickness))

	st.commit(_array_mesh)

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
	_array_mesh.surface_set_material(1, mat)
	_icon_material = mat


## 四角形を追加するヘルパー
func _add_quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> void:
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p3)
	st.add_vertex(p1)
	st.add_vertex(p3)
	st.add_vertex(p4)


## 待機時間を設定
## @param duration: 待機時間（秒）
func set_wait_duration(duration: float) -> void:
	_wait_duration = duration
	_update_duration_label()


## 待機時間を取得
func get_wait_duration() -> float:
	return _wait_duration


## 持続時間ラベルを更新
func _update_duration_label() -> void:
	if not _duration_label:
		_duration_label = Label3D.new()
		_duration_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_duration_label.no_depth_test = true
		_duration_label.font_size = 48
		_duration_label.outline_size = 8
		_duration_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_duration_label.outline_modulate = Color(0, 0, 0, 0.8)
		_duration_label.position = Vector3(0, 0.5, 0)
		add_child(_duration_label)

	_duration_label.text = "%.1fs" % _wait_duration


## 色を変更（WaitMarkerは再構築が必要）
func set_colors(bg_color: Color, fg_color: Color) -> void:
	circle_color = bg_color
	icon_color = fg_color
	_build_mesh()
