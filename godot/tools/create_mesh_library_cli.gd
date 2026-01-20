extends SceneTree
## MeshLibraryを作成するCLIスクリプト
## 実行: godot --headless --script tools/create_mesh_library_cli.gd

func _init() -> void:
	print("=== Creating MeshLibrary (CLI) ===")

	# GLBシーンをロード
	var glb_path := "res://assets/maps/mesh_library_parts.glb"
	var glb_scene := load(glb_path) as PackedScene
	if not glb_scene:
		push_error("Failed to load GLB: " + glb_path)
		quit(1)
		return

	# シーンをインスタンス化
	var instance := glb_scene.instantiate()

	# MeshLibraryを作成
	var mesh_lib := MeshLibrary.new()
	var item_id := 0

	# 子ノードを走査してMeshInstance3Dを取得
	item_id = _process_node(instance, mesh_lib, item_id)

	# 保存
	var output_path := "res://assets/maps/mesh_library.tres"
	var err := ResourceSaver.save(mesh_lib, output_path)
	if err == OK:
		print("MeshLibrary saved to: " + output_path)
		print("Total items: %d" % mesh_lib.get_item_list().size())
	else:
		push_error("Failed to save MeshLibrary: " + str(err))
		quit(1)
		return

	# クリーンアップ
	instance.queue_free()
	quit(0)


func _process_node(node: Node, mesh_lib: MeshLibrary, item_id: int) -> int:
	# MeshInstance3Dを探す
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			mesh_lib.create_item(item_id)
			mesh_lib.set_item_name(item_id, node.name)
			mesh_lib.set_item_mesh(item_id, mesh)

			# Mesh Transform: オフセットなし（原点は底面中央に設定済み）
			# 床と壁を同じFloor=0に配置する想定

			# コリジョン形状を作成（メッシュのAABBからボックス）
			var aabb := mesh.get_aabb()
			var box_shape := BoxShape3D.new()
			box_shape.size = aabb.size

			# shapes配列を設定
			var shapes_array: Array = []
			shapes_array.append(box_shape)
			shapes_array.append(Transform3D(Basis.IDENTITY, aabb.get_center()))
			mesh_lib.set_item_shapes(item_id, shapes_array)

			print("  Added item %d: %s (size: %s)" % [item_id, node.name, aabb.size])
			item_id += 1

	# 子ノードを再帰的に処理
	for child in node.get_children():
		item_id = _process_node(child, mesh_lib, item_id)

	return item_id
