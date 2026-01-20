extends SceneTree

func _init():
	# Check the model structure
	var preset_path := "res://data/characters/dummy_t.tres"
	var preset = load(preset_path)
	if not preset:
		print("ERROR: Could not load preset")
		quit()
		return

	print("\n=== Model Structure ===")
	var model = preset.model_scene.instantiate()
	_print_tree(model, 0)

	# Find AnimationPlayer and check its root_node
	var anim_player = _find_node_by_type(model, "AnimationPlayer")
	if anim_player:
		print("\n=== AnimationPlayer Info ===")
		print("root_node: ", anim_player.root_node)
		var root = anim_player.get_node(anim_player.root_node)
		print("root_node resolves to: ", root.name if root else "NULL")

	# Find Skeleton3D and check its path
	var skeleton = _find_node_by_type(model, "Skeleton3D")
	if skeleton:
		print("\n=== Skeleton3D Info ===")
		print("Skeleton path from model root: ", model.get_path_to(skeleton))
		print("Bone count: ", skeleton.get_bone_count())
		print("First 5 bones:")
		for i in range(min(5, skeleton.get_bone_count())):
			print("  - ", skeleton.get_bone_name(i))

	model.queue_free()
	quit()

func _print_tree(node: Node, depth: int):
	var indent = "  ".repeat(depth)
	var type_name = node.get_class()
	print(indent, node.name, " (", type_name, ")")
	for child in node.get_children():
		_print_tree(child, depth + 1)

func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_type(child, type_name)
		if result:
			return result
	return null
