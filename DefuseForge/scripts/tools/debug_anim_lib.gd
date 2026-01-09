extends SceneTree

func _init():
	var path = "res://assets/animations/mixamo_animation_library.glb"
	print("Checking: %s" % path)
	var scene = load(path)
	if scene:
		var instance = scene.instantiate()
		_print_tree(instance, 0)
		instance.free()
	else:
		print("Failed to load")
	quit()

func _print_tree(node: Node, depth: int) -> void:
	var indent = "  ".repeat(depth)
	var info = node.get_class()
	if node is AnimationPlayer:
		var ap = node as AnimationPlayer
		info += " [%d animations]" % ap.get_animation_list().size()
		for anim_name in ap.get_animation_list():
			print("%s  - %s" % [indent, anim_name])
	elif node is Skeleton3D:
		info += " [%d bones]" % (node as Skeleton3D).get_bone_count()
	elif node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.mesh:
			info += " [%s]" % mi.mesh.get_class()
	print("%s%s (%s)" % [indent, node.name, info])
	for child in node.get_children():
		_print_tree(child, depth + 1)
