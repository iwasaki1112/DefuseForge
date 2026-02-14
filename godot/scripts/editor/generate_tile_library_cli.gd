extends SceneTree
## MeshLibraryをCLIから生成するスクリプト
## scenes/tiles/*.glb を自動スキャンしてtile_library.tresを生成
##
## 使い方:
##   godot --headless --script res://scripts/editor/generate_tile_library_cli.gd


const TILES_DIR := "res://scenes/tiles/"
const SAVE_PATH := "res://data/tiles/tile_library.tres"


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

	var lib := MeshLibrary.new()

	for i in glb_files.size():
		var file_name2 := glb_files[i]
		var tile_name := file_name2.get_basename()  # "floor_concrete.glb" → "floor_concrete"
		var path := TILES_DIR + file_name2
		print("Loading: ", path)

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

			# コリジョン（メッシュごとにBoxShape3D）
			var aabb := mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = aabb.size
			var center := mi.transform * aabb.get_center()
			shapes.append(box)
			shapes.append(Transform3D(Basis.IDENTITY, center))
			print("  Mesh: ", mi.name, " AABB: ", aabb.size)

		lib.set_item_mesh(i, combined)
		lib.set_item_shapes(i, shapes)

		instance.free()
		print("  Done: ", tile_name)

	# 保存
	var save_dir := ProjectSettings.globalize_path("res://data/tiles")
	DirAccess.make_dir_recursive_absolute(save_dir)

	var err := ResourceSaver.save(lib, SAVE_PATH)
	if err == OK:
		print("=== MeshLibrary saved: %s (%d items) ===" % [SAVE_PATH, glb_files.size()])
	else:
		print("=== ERROR saving: ", err, " ===")

	quit()


func _find_all_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_all_mesh_instances(child, result)
