class_name SmokeGrenadePoint
extends ActionPoint

## スモークグレネードポイント（円形背景 + 雲アイコン）
## パス上でキャラクターがグレネードを投擲する位置を示す


func _init() -> void:
	# デフォルト色を設定（灰色/スモーク系）
	circle_color = Color(0.5, 0.5, 0.55, 0.95)
	icon_color = Color(1.0, 1.0, 1.0, 1.0)


func get_action_point_type() -> PointType:
	return PointType.SMOKE_GRENADE


## アイコン（雲: 3つの重なった円）を構築
func _build_icon() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	var y_offset = 0.02  # 円より少し上（Z-fighting防止）
	var cloud_scale = circle_radius * 0.35

	# 雲を3つの円で構成
	var cloud_circles = [
		Vector3(-cloud_scale * 0.5, y_offset, 0.0),   # 左
		Vector3(0.0, y_offset, -cloud_scale * 0.2),    # 中央上
		Vector3(cloud_scale * 0.5, y_offset, 0.0),     # 右
	]
	var cloud_radii = [
		cloud_scale * 0.55,  # 左
		cloud_scale * 0.65,  # 中央（少し大きく）
		cloud_scale * 0.55,  # 右
	]

	var cloud_segments = 12
	var vertex_offset = 0

	for c in range(cloud_circles.size()):
		var center = cloud_circles[c]
		var radius = cloud_radii[c]

		# 中心点
		vertices.append(center)
		var center_idx = vertex_offset

		# 円周上の頂点
		for i in range(cloud_segments):
			var angle = TAU * i / cloud_segments
			vertices.append(Vector3(
				center.x + cos(angle) * radius,
				y_offset,
				center.z + sin(angle) * radius
			))

		# 三角形で塗りつぶし
		for i in range(cloud_segments):
			var curr = vertex_offset + 1 + i
			var next = vertex_offset + 1 + (i + 1) % cloud_segments
			indices.append(center_idx)
			indices.append(curr)
			indices.append(next)

		vertex_offset += cloud_segments + 1

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(1, _icon_material)


## 色を変更（SmokeGrenadePointは再構築が必要）
func set_colors(bg_color: Color, fg_color: Color) -> void:
	circle_color = bg_color
	icon_color = fg_color
	_build_mesh()
