@tool
extends EditorScript

func _run() -> void:
	print("\n=== Scene Tree Debug ===\n")

	# Compare FBX and GLB structures
	var scenes = [
		"res://assets/characters/mixamo_test/mixamo_test.fbx",
		"res://assets/characters/vanguard/vanguard.glb"
	]

	for scene_path in scenes:
		print("\n--- %s ---" % scene_path)
		var scene = load(scene_path)
		if scene:
			var instance = scene.instantiate()
			_print_tree(instance, 0)
			instance.queue_free()
		else:
			print("Failed to load: %s" % scene_path)

func _print_tree(node: Node, depth: int) -> void:
	var indent = "  ".repeat(depth)
	var type_info = node.get_class()

	# Add extra info for specific types
	if node is MeshInstance3D:
		var mesh = node.mesh
		if mesh:
			type_info += " (mesh: %s, surfaces: %d)" % [mesh.get_class(), mesh.get_surface_count()]
		else:
			type_info += " (NO MESH)"
	elif node is Skeleton3D:
		type_info += " (bones: %d)" % node.get_bone_count()

	print("%s%s [%s]" % [indent, node.name, type_info])

	for child in node.get_children():
		_print_tree(child, depth + 1)
