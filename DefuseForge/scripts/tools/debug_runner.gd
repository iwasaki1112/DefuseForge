extends SceneTree

func _init():
	print("\n=== Scene Structure Comparison ===\n")

	var scenes = {
		"FBX": "res://assets/characters/mixamo_test/mixamo_test.fbx",
		"GLB": "res://assets/characters/vanguard/vanguard.glb"
	}

	for label in scenes:
		var path = scenes[label]
		print("\n--- %s: %s ---" % [label, path])
		var scene = load(path)
		if scene:
			var instance = scene.instantiate()
			_print_tree(instance, 0)
			instance.free()
		else:
			print("FAILED TO LOAD")

	quit()

func _print_tree(node: Node, depth: int) -> void:
	var indent = "  ".repeat(depth)
	var info = node.get_class()

	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.mesh:
			info += " [mesh=%s, %d surfaces, visible=%s]" % [mi.mesh.get_class(), mi.mesh.get_surface_count(), mi.visible]
		else:
			info += " [NO MESH, visible=%s]" % mi.visible
	elif node is Skeleton3D:
		info += " [%d bones, scale=%s]" % [(node as Skeleton3D).get_bone_count(), node.scale]

	print("%s%s (%s)" % [indent, node.name, info])

	for child in node.get_children():
		_print_tree(child, depth + 1)
