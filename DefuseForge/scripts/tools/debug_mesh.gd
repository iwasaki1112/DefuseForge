extends SceneTree

func _init():
	print("\n=== Mesh & Skin Debug ===\n")

	var scenes = {
		"vanguard": "res://assets/characters/vanguard/vanguard.glb",
		"phantom": "res://assets/characters/phantom/phantom.glb",
		"shade": "res://assets/characters/shade/shade.glb"
	}

	for label in scenes:
		var path = scenes[label]
		print("\n=== %s: %s ===" % [label, path])
		var scene = load(path)
		if scene:
			var instance = scene.instantiate()
			_analyze_meshes(instance, label)
			instance.free()
		else:
			print("FAILED TO LOAD")

	quit()

func _analyze_meshes(node: Node, label: String) -> void:
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		print("\nMeshInstance3D: %s" % mi.name)
		print("  Visible: %s" % mi.visible)

		if mi.mesh:
			var mesh = mi.mesh
			print("  Mesh type: %s" % mesh.get_class())
			print("  Surface count: %d" % mesh.get_surface_count())

			for i in range(mesh.get_surface_count()):
				var mat = mi.get_surface_override_material(i)
				if not mat:
					mat = mesh.surface_get_material(i)
				print("  Surface %d:" % i)
				print("    Material: %s" % (mat.resource_name if mat else "NONE"))

				if mesh is ArrayMesh:
					var arrays = mesh.surface_get_arrays(i)
					if arrays.size() > 0:
						var vertices = arrays[Mesh.ARRAY_VERTEX]
						print("    Vertices: %d" % (vertices.size() if vertices else 0))
		else:
			print("  NO MESH!")

		if mi.skin:
			print("  Skin bind count: %d" % mi.skin.get_bind_count())
		else:
			print("  Skin: NONE")

	elif node is Skeleton3D:
		var skel = node as Skeleton3D
		print("\nSkeleton3D: %s" % node.name)
		print("  Bone count: %d" % skel.get_bone_count())
		print("  Scale: %s" % node.scale)
		print("  Bones:")
		for i in range(skel.get_bone_count()):
			print("    %d: %s" % [i, skel.get_bone_name(i)])

	for child in node.get_children():
		_analyze_meshes(child, label)
