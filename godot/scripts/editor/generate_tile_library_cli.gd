extends SceneTree
## MeshLibraryをCLIから生成するスクリプト
## scenes/tiles/*.glb を自動スキャンして floor/wall 別のMeshLibraryを生成
##
## 使い方:
##   godot --headless --script res://scripts/editor/generate_tile_library_cli.gd


const TILES_DIR := "res://scenes/tiles/"
const SAVE_DIR := "res://data/tiles/"
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

		lib.create_item(i)
		lib.set_item_name(i, tile_name)

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
				for vi in verts.size():
					verts[vi] = xform * verts[vi]
				if normals:
					for ni in normals.size():
						normals[ni] = xform.basis * normals[ni]
				arrays[Mesh.ARRAY_VERTEX] = verts
				if normals:
					arrays[Mesh.ARRAY_NORMAL] = normals

				var mat := mi.get_active_material(surf_idx)
				combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				if mat:
					combined.surface_set_material(combined.get_surface_count() - 1, mat)
					print("  Surface: ", mat.resource_name)

			if not has_opening:
				# 非ドア: メッシュごとにAABB BoxShape3D
				var aabb := mesh.get_aabb()
				var box := BoxShape3D.new()
				box.size = aabb.size
				var center := mi.transform * aabb.get_center()
				shapes.append(box)
				shapes.append(Transform3D(Basis.IDENTITY, center))
			print("  Mesh: ", mi.name, " AABB: ", mi.mesh.get_aabb().size)

		# ドアタイル: 開口部を除いた柱ごとにBoxShape3Dを生成
		if has_opening:
			var door_shapes := _create_door_collision_shapes(combined)
			shapes.append_array(door_shapes)

		lib.set_item_mesh(i, combined)
		lib.set_item_shapes(i, shapes)

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
