extends SceneTree

func _init():
	var preset = load("res://data/characters/dummy_t.tres")
	var model = preset.model_scene.instantiate()

	print("\n=== Model Skinning Analysis ===")
	_analyze_node(model, 0)

	model.queue_free()
	quit()

func _analyze_node(node: Node, depth: int):
	var indent = "  ".repeat(depth)

	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		print(indent, node.name, " (MeshInstance3D)")
		print(indent, "  skeleton: ", mesh_inst.skeleton)
		print(indent, "  skin: ", mesh_inst.skin)

		if mesh_inst.mesh:
			print(indent, "  mesh surface count: ", mesh_inst.mesh.get_surface_count())
	elif node is Skeleton3D:
		var skel = node as Skeleton3D
		print(indent, node.name, " (Skeleton3D)")
		print(indent, "  bone count: ", skel.get_bone_count())
	else:
		print(indent, node.name, " (", node.get_class(), ")")

	for child in node.get_children():
		_analyze_node(child, depth + 1)
