extends SceneTree

func _init():
	var preset = load("res://data/characters/dummy_t.tres")
	if not preset:
		print("ERROR: Could not load preset")
		quit()
		return

	print("\n=== Model Instance Structure ===")
	var model = preset.model_scene.instantiate()
	print("Root name: ", model.name)
	print("Root class: ", model.get_class())
	_print_tree(model, 0)

	print("\n=== Animation GLB Structure ===")
	var anim_glb = load("res://assets/animations/character_anims.glb") as PackedScene
	if anim_glb:
		var anim_instance = anim_glb.instantiate()
		print("Root name: ", anim_instance.name)
		print("Root class: ", anim_instance.get_class())
		_print_tree(anim_instance, 0)

		# Check AnimationPlayer root_node
		var anim_player = _find_node(anim_instance, "AnimationPlayer")
		if anim_player:
			print("\nAnimationPlayer.root_node: ", anim_player.root_node)

		anim_instance.queue_free()

	model.queue_free()
	quit()

func _print_tree(node: Node, depth: int):
	var indent = "  ".repeat(depth)
	print(indent, node.name, " (", node.get_class(), ")")
	if depth < 3:  # Limit depth
		for child in node.get_children():
			_print_tree(child, depth + 1)

func _find_node(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result = _find_node(child, type_name)
		if result:
			return result
	return null
