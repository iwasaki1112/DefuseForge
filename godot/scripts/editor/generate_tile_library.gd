@tool
extends EditorScript
## MeshLibraryを生成するEditorScript
## Godotの Script Editor → File → Run で実行

func _run() -> void:
	print("=== MeshLibrary生成開始 ===")

	var lib = MeshLibrary.new()

	var tile_names = ["floor_concrete", "wall_exterior", "wall_interior", "door_frame"]
	var tile_paths = [
		"res://scenes/tiles/floor_concrete.glb",
		"res://scenes/tiles/wall_exterior.glb",
		"res://scenes/tiles/wall_interior.glb",
		"res://scenes/tiles/door_frame.glb",
	]

	for i in tile_names.size():
		var tile_name = tile_names[i]
		var path = tile_paths[i]
		print("Loading: ", path)

		var scene = load(path)
		if not scene:
			print("  ERROR: Could not load ", path)
			continue

		var instance = scene.instantiate()
		print("  Instance created: ", instance.name)

		lib.create_item(i)
		lib.set_item_name(i, tile_name)

		# MeshInstance3Dを探す
		var mesh_inst = _find_first_mesh_instance(instance)
		if mesh_inst:
			lib.set_item_mesh(i, mesh_inst.mesh)
			print("  Mesh set: ", mesh_inst.name)

			# メッシュAABBからボックスコリジョンを自動生成
			var aabb = mesh_inst.mesh.get_aabb()
			var box = BoxShape3D.new()
			box.size = aabb.size
			var shape_transform = Transform3D(Basis.IDENTITY, aabb.get_center())
			lib.set_item_shapes(i, [box, shape_transform])
			print("  Collision: box ", aabb.size)
		else:
			print("  WARNING: No MeshInstance3D found")

		instance.free()
		print("  Added: ", tile_name, " (id=", i, ")")

	# 保存
	var save_dir = ProjectSettings.globalize_path("res://data/tiles")
	DirAccess.make_dir_recursive_absolute(save_dir)

	var save_path = "res://data/tiles/tile_library.tres"
	var err = ResourceSaver.save(lib, save_path)
	if err == OK:
		print("=== MeshLibrary saved: ", save_path, " ===")
		EditorInterface.get_resource_filesystem().scan()
	else:
		print("=== ERROR saving: ", err, " ===")


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _find_first_mesh_instance(child)
		if result:
			return result
	return null
