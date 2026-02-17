extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/effects/bullet_casing.glb")
	if not scene:
		print("DEBUG: Failed to load GLB")
		quit()
		return

	var instance := scene.instantiate()
	_print_tree(instance, 0)
	instance.free()
	quit()

func _print_tree(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var info := "%s%s [%s]" % [indent, node.name, node.get_class()]

	if node is Node3D:
		var n3d := node as Node3D
		info += " pos=%s scale=%s" % [n3d.position, n3d.scale]

	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var aabb := mi.mesh.get_aabb()
			info += " AABB_size=%s" % [aabb.size]

	print(info)

	for child in node.get_children():
		_print_tree(child, depth + 1)
