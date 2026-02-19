extends SceneTree
## MeshLibraryをCLIから生成するスクリプト
## scenes/tiles/*.glb を自動スキャンして floor/wall 別のMeshLibraryを生成
##
## 使い方:
##   godot --headless --script res://scripts/editor/generate_tile_library_cli.gd


const TILES_DIR := "res://scenes/tiles/"
const SAVE_DIR := "res://data/tiles/"
const PREVIEW_DIR := "res://data/tiles/previews/"
const FLOOR_SAVE_PATH := "res://data/tiles/tile_library_floor.tres"
const WALL_SAVE_PATH := "res://data/tiles/tile_library_wall.tres"


func _init() -> void:
	print("=== MeshLibrary生成開始 ===")

	# scenes/tiles/*.glb を自動スキャン
	var glb_files: Array[String] = []
	var dir := DirAccess.open(TILES_DIR)
	if not dir:
		print("ERROR: Could not open ", TILES_DIR)
		quit()
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".glb"):
			glb_files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	glb_files.sort()
	print("Found %d GLB files" % glb_files.size())

	# floor/wall に分類
	var floor_files: Array[String] = []
	var wall_files: Array[String] = []
	for f in glb_files:
		var name_lower := f.get_basename().to_lower()
		# _panel サフィックスはランタイムで個別ロード（MeshLibraryに入れない）
		if "_panel" in name_lower:
			continue
		if name_lower.begins_with("wall") or name_lower.begins_with("glass") or name_lower.begins_with("door"):
			wall_files.append(f)
		else:
			floor_files.append(f)

	print("  Floor tiles: %d, Wall tiles: %d" % [floor_files.size(), wall_files.size()])

	# 各ライブラリを生成
	_build_library(floor_files, FLOOR_SAVE_PATH, "Floor")
	_build_library(wall_files, WALL_SAVE_PATH, "Wall")

	quit()


func _build_library(files: Array[String], save_path: String, label: String) -> void:
	var lib := MeshLibrary.new()

	# 既存MeshLibraryから名前→IDマッピングを読み込み（安定ID保持）
	var name_to_id: Dictionary = {}
	var max_id := -1
	if ResourceLoader.exists(save_path):
		var existing := load(save_path) as MeshLibrary
		if existing:
			for item_id in existing.get_item_list():
				var item_name := existing.get_item_name(item_id)
				name_to_id[item_name] = item_id
				if item_id > max_id:
					max_id = item_id
			print("  Loaded existing IDs: %s" % str(name_to_id))

	for i in files.size():
		var file_name2 := files[i]
		var tile_name := file_name2.get_basename()
		var path := TILES_DIR + file_name2
		print("Loading [%s]: %s" % [label, path])

		var scene := load(path) as PackedScene
		if not scene:
			print("  ERROR: Could not load ", path)
			continue

		var instance := scene.instantiate()

		# 既存タイルはIDを保持、新規タイルは次の空きIDを割り当て
		var item_id: int
		if tile_name in name_to_id:
			item_id = name_to_id[tile_name]
		else:
			max_id += 1
			item_id = max_id

		lib.create_item(item_id)
		lib.set_item_name(item_id, tile_name)

		# 全MeshInstance3Dを収集
		var mesh_instances: Array[MeshInstance3D] = []
		_find_all_mesh_instances(instance, mesh_instances)

		if mesh_instances.is_empty():
			print("  WARNING: No MeshInstance3D found in ", tile_name)
			instance.free()
			print("  Done: ", tile_name)
			continue

		var name_lower := tile_name.to_lower()
		var has_opening := name_lower.begins_with("door") or "window" in name_lower

		# メッシュを結合（複数サーフェスのArrayMesh）
		var combined := ArrayMesh.new()
		var shapes: Array = []

		for mi in mesh_instances:
			var mesh := mi.mesh
			for surf_idx in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surf_idx)
				# 頂点をMeshInstance3Dのローカル変換で変換
				var xform := mi.transform
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals = arrays[Mesh.ARRAY_NORMAL]
				var tangents = arrays[Mesh.ARRAY_TANGENT]
				for vi in verts.size():
					verts[vi] = xform * verts[vi]
				if normals:
					for ni in normals.size():
						normals[ni] = (xform.basis * normals[ni]).normalized()
				# タンジェント変換（xyzをbasisで変換、w符号は保持）
				if tangents and tangents.size() > 0:
					for ti in range(0, tangents.size(), 4):
						var t := Vector3(tangents[ti], tangents[ti + 1], tangents[ti + 2])
						t = (xform.basis * t).normalized()
						tangents[ti] = t.x
						tangents[ti + 1] = t.y
						tangents[ti + 2] = t.z
						# tangents[ti + 3] (w/bitangent sign) は保持
					arrays[Mesh.ARRAY_TANGENT] = tangents
				arrays[Mesh.ARRAY_VERTEX] = verts
				if normals:
					arrays[Mesh.ARRAY_NORMAL] = normals

				var mat := mi.get_active_material(surf_idx)
				combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				if mat:
					if mat is StandardMaterial3D and arrays[Mesh.ARRAY_COLOR] != null:
						mat.vertex_color_use_as_albedo = true
					combined.surface_set_material(combined.get_surface_count() - 1, mat)
					print("  Surface: ", mat.resource_name)
			print("  Mesh: ", mi.name, " AABB: ", mi.mesh.get_aabb().size)

		# SurfaceToolでタンジェントを再生成（TBN整合性を保証）
		var regenerated := ArrayMesh.new()
		for surf_idx in combined.get_surface_count():
			var st := SurfaceTool.new()
			st.create_from(combined, surf_idx)
			st.generate_tangents()
			st.commit(regenerated)
			var mat := combined.surface_get_material(surf_idx)
			if mat:
				regenerated.surface_set_material(regenerated.get_surface_count() - 1, mat)
		combined = regenerated

		# コリジョン生成（3分岐）
		if has_opening:
			# ドア/窓タイル: 開口部を除いた柱ごとにBoxShape3Dを生成
			var door_shapes := _create_door_collision_shapes(combined)
			shapes.append_array(door_shapes)
		else:
			var combined_aabb := combined.get_aabb()
			if combined_aabb.size.x > 0.5 and combined_aabb.size.y > 0.5 and combined_aabb.size.z > 0.5:
				# 複合形状壁（L字/T字等）: 三角形BBox分類で壁アームを分解
				var complex_shapes := _create_complex_wall_shapes(combined)
				shapes.append_array(complex_shapes)
			else:
				# 単純壁（wall_straight等）: 全体AABBから単一BoxShape3D
				var box := BoxShape3D.new()
				box.size = combined_aabb.size
				shapes.append(box)
				shapes.append(Transform3D(Basis.IDENTITY, combined_aabb.get_center()))
				print("  Simple wall collision: size=", box.size)

		lib.set_item_mesh(item_id, combined)
		lib.set_item_shapes(item_id, shapes)

		# プレビュー画像の読み込み（Blenderでレンダリング済みPNG）
		var preview_abs := ProjectSettings.globalize_path(PREVIEW_DIR + tile_name + ".png")
		if FileAccess.file_exists(preview_abs):
			var img := Image.new()
			if img.load(preview_abs) == OK:
				var tex := ImageTexture.create_from_image(img)
				lib.set_item_preview(item_id, tex)
				print("  Preview: loaded")
			else:
				print("  Preview: load error")
		else:
			print("  Preview: not found (%s)" % preview_abs)

		instance.free()
		print("  Done: ", tile_name)

	# 保存
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))

	var err := ResourceSaver.save(lib, save_path)
	if err == OK:
		print("=== [%s] MeshLibrary saved: %s (%d items) ===" % [label, save_path, files.size()])
	else:
		print("=== [%s] ERROR saving: %s ===" % [label, err])


func _find_all_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_all_mesh_instances(child, result)


## 開口付きタイルのメッシュ頂点を解析し、柱ごとにBoxShape3Dを生成
## ユニークなX座標から内側の境界（AABB端ではない値）を検出して開口部を特定する
func _create_door_collision_shapes(mesh: ArrayMesh) -> Array:
	var shapes: Array = []

	# 全サーフェスの頂点を収集
	var all_verts: PackedVector3Array = PackedVector3Array()
	for surf_idx in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf_idx)
		all_verts.append_array(arrays[Mesh.ARRAY_VERTEX])

	if all_verts.is_empty():
		return shapes

	# ユニークなX座標を取得（AABB端と内側の境界を識別）
	var unique_x: Array[float] = []
	for v in all_verts:
		var found := false
		for ux in unique_x:
			if absf(ux - v.x) < 0.001:
				found = true
				break
		if not found:
			unique_x.append(v.x)
	unique_x.sort()

	# 4点 [left_outer, left_inner, right_inner, right_outer] を期待
	# 開口部は inner の2点間
	if unique_x.size() < 4:
		# ユニーク値が少ない場合はAABBフォールバック
		var aabb := mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size
		shapes.append(box)
		shapes.append(Transform3D(Basis.IDENTITY, aabb.get_center()))
		print("  Opening collision: fallback AABB (unique_x=%d)" % unique_x.size())
		return shapes

	# 内側の境界 = AABB端(min/max)を除いた値の中で最も離れた2点が開口
	var inner_left := unique_x[1]   # 左柱の内側エッジ
	var inner_right := unique_x[unique_x.size() - 2]  # 右柱の内側エッジ
	var gap_center := (inner_left + inner_right) / 2.0

	print("  Opening detected: x=[%.3f, %.3f] width=%.3f" % [inner_left, inner_right, inner_right - inner_left])

	# ギャップの左右に頂点を分割し、それぞれBoxShape3Dを生成
	var left_min := Vector3(INF, INF, INF)
	var left_max := Vector3(-INF, -INF, -INF)
	var right_min := Vector3(INF, INF, INF)
	var right_max := Vector3(-INF, -INF, -INF)

	for v in all_verts:
		if v.x < gap_center:
			left_min = Vector3(min(left_min.x, v.x), min(left_min.y, v.y), min(left_min.z, v.z))
			left_max = Vector3(max(left_max.x, v.x), max(left_max.y, v.y), max(left_max.z, v.z))
		else:
			right_min = Vector3(min(right_min.x, v.x), min(right_min.y, v.y), min(right_min.z, v.z))
			right_max = Vector3(max(right_max.x, v.x), max(right_max.y, v.y), max(right_max.z, v.z))

	# 左柱
	if left_min.x < INF:
		var box := BoxShape3D.new()
		box.size = left_max - left_min
		var center := (left_min + left_max) / 2.0
		shapes.append(box)
		shapes.append(Transform3D(Basis.IDENTITY, center))
		print("  Opening collision: left pillar size=", box.size, " center=", center)

	# 右柱
	if right_min.x < INF:
		var box := BoxShape3D.new()
		box.size = right_max - right_min
		var center := (right_min + right_max) / 2.0
		shapes.append(box)
		shapes.append(Transform3D(Basis.IDENTITY, center))
		print("  Opening collision: right pillar size=", box.size, " center=", center)

	# 窓台（中央開口部の底面）: 開口内の頂点がAABB底面より高い場合、窓台ボックスを追加
	var aabb := mesh.get_aabb()
	var center_min_y := INF
	var center_max_z := -INF
	var center_min_z := INF
	for v in all_verts:
		if v.x > inner_left - 0.001 and v.x < inner_right + 0.001:
			center_min_y = min(center_min_y, v.y)
			center_min_z = min(center_min_z, v.z)
			center_max_z = max(center_max_z, v.z)

	# 窓台の高さ = 開口内頂点の最小Y - AABB最小Y
	if center_min_y < INF:
		var sill_height := center_min_y - aabb.position.y
		if sill_height > 0.05:
			var box := BoxShape3D.new()
			box.size = Vector3(inner_right - inner_left, sill_height, center_max_z - center_min_z)
			var center := Vector3(
				(inner_left + inner_right) / 2.0,
				aabb.position.y + sill_height / 2.0,
				(center_min_z + center_max_z) / 2.0
			)
			shapes.append(box)
			shapes.append(Transform3D(Basis.IDENTITY, center))
			print("  Opening collision: sill size=", box.size, " center=", center)

	return shapes


## 複合形状壁タイル（L字/T字等）のコリジョンを三角形バウンディングボックス分類で壁アームに分解
## 各三角形のXZ平面でのバウンディングボックスから薄い次元を検出し、同じアームの三角形をクラスタリング
func _create_complex_wall_shapes(mesh: ArrayMesh) -> Array:
	var shapes: Array = []

	# 全サーフェスから三角形の頂点・インデックスを収集
	var all_verts: PackedVector3Array = PackedVector3Array()
	var all_indices: PackedInt32Array = PackedInt32Array()
	var vert_offset := 0

	for surf_idx in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		all_verts.append_array(verts)
		if indices and indices.size() > 0:
			for idx in indices:
				all_indices.append(idx + vert_offset)
		else:
			for vi in verts.size():
				all_indices.append(vi + vert_offset)
		vert_offset += verts.size()

	if all_verts.is_empty() or all_indices.size() < 3:
		var aabb := mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size
		shapes.append(box)
		shapes.append(Transform3D(Basis.IDENTITY, aabb.get_center()))
		print("  Complex wall: fallback AABB (no triangles)")
		return shapes

	var THIN_THRESHOLD := 0.5  # 三角形のバウンディングボックスがこの厚み以下なら「薄い」
	var CLUSTER_GAP := 0.5  # この距離以上離れたら別クラスタ
	var MIN_BOX_DIM := 0.05  # これ以下の次元のボックスはスキップ

	# 各三角形をバウンディングボックスの薄さで分類
	# x_arm_data: [[z_center, v0, v1, v2], ...] — Z方向に薄い → X方向に走る壁
	# z_arm_data: [[x_center, v0, v1, v2], ...] — X方向に薄い → Z方向に走る壁
	var x_arm_data: Array = []
	var z_arm_data: Array = []

	var tri_count := all_indices.size() / 3
	for ti in tri_count:
		var v0 := all_verts[all_indices[ti * 3]]
		var v1 := all_verts[all_indices[ti * 3 + 1]]
		var v2 := all_verts[all_indices[ti * 3 + 2]]

		var tri_z_ext: float = maxf(v0.z, maxf(v1.z, v2.z)) - minf(v0.z, minf(v1.z, v2.z))
		var tri_x_ext: float = maxf(v0.x, maxf(v1.x, v2.x)) - minf(v0.x, minf(v1.x, v2.x))

		if tri_z_ext <= THIN_THRESHOLD:
			var z_center := (v0.z + v1.z + v2.z) / 3.0
			x_arm_data.append([z_center, v0, v1, v2])
		if tri_x_ext <= THIN_THRESHOLD:
			var x_center := (v0.x + v1.x + v2.x) / 3.0
			z_arm_data.append([x_center, v0, v1, v2])

	# X-arm三角形をZ重心でクラスタリング → 各クラスタがX方向の壁セグメント
	_cluster_and_generate_boxes(x_arm_data, CLUSTER_GAP, MIN_BOX_DIM, shapes, "X-arm")

	# Z-arm三角形をX重心でクラスタリング → 各クラスタがZ方向の壁セグメント
	_cluster_and_generate_boxes(z_arm_data, CLUSTER_GAP, MIN_BOX_DIM, shapes, "Z-arm")

	if shapes.is_empty():
		var aabb := mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size
		shapes.append(box)
		shapes.append(Transform3D(Basis.IDENTITY, aabb.get_center()))
		print("  Complex wall: fallback AABB (no arms detected)")
	else:
		print("  Complex wall: %d segments generated" % (shapes.size() / 2))

	return shapes


## 三角形データを重心値でソート・クラスタリングし、各クラスタからBoxShape3Dを生成
func _cluster_and_generate_boxes(tri_data: Array, cluster_gap: float, min_dim: float, shapes: Array, label: String) -> void:
	if tri_data.is_empty():
		return

	# 重心値（index 0）でソート
	tri_data.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	# 隣接する三角形を重心間距離でクラスタリング
	var clusters: Array = []
	var current_cluster: Array = [tri_data[0]]

	for i in range(1, tri_data.size()):
		if tri_data[i][0] - tri_data[i - 1][0] > cluster_gap:
			clusters.append(current_cluster)
			current_cluster = []
		current_cluster.append(tri_data[i])
	clusters.append(current_cluster)

	# 各クラスタの頂点AABBからBoxShape3Dを生成
	for cluster in clusters:
		var vmin := Vector3(INF, INF, INF)
		var vmax := Vector3(-INF, -INF, -INF)
		for entry in cluster:
			for vi in range(1, 4):
				var v: Vector3 = entry[vi]
				vmin.x = min(vmin.x, v.x); vmin.y = min(vmin.y, v.y); vmin.z = min(vmin.z, v.z)
				vmax.x = max(vmax.x, v.x); vmax.y = max(vmax.y, v.y); vmax.z = max(vmax.z, v.z)

		var box_size := vmax - vmin
		# 退化したボックス（非常に薄い面）をスキップ
		if box_size.x < min_dim or box_size.y < min_dim or box_size.z < min_dim:
			continue

		var box := BoxShape3D.new()
		box.size = box_size
		var center := (vmin + vmax) / 2.0
		shapes.append(box)
		shapes.append(Transform3D(Basis.IDENTITY, center))
		print("  Complex wall: %s size=%s center=%s" % [label, str(box_size), str(center)])
