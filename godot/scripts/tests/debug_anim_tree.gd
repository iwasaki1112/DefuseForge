extends SceneTree

func _init():
	# Load character preset directly
	var preset = load("res://data/characters/dummy_t.tres")
	if not preset:
		print("ERROR: Could not load preset")
		quit()
		return

	print("\n=== Debug Animation Setup ===")

	# Check model
	var model = preset.model_scene.instantiate()
	print("Model: ", model)

	var anim_player = _find_node(model, "AnimationPlayer")
	print("\nAnimationPlayer: ", anim_player)

	if anim_player:
		print("  root_node: ", anim_player.root_node)
		print("  Libraries: ", anim_player.get_animation_library_list())
		var lib = anim_player.get_animation_library("")
		if lib:
			print("  Animations in default library: ", lib.get_animation_list())
		print("  Has rifle_idle: ", anim_player.has_animation("rifle_idle"))

	# Now load the animation library from character_anims.glb
	print("\n=== Loading Animation Library ===")
	var anim_glb = load("res://assets/animations/character_anims.glb") as PackedScene
	if anim_glb:
		var anim_instance = anim_glb.instantiate()
		var source_anim_player = _find_node(anim_instance, "AnimationPlayer")
		if source_anim_player:
			var source_lib = source_anim_player.get_animation_library("")
			print("Source library animations: ", source_lib.get_animation_list() if source_lib else "None")

			# Add to model's AnimationPlayer
			if anim_player and source_lib:
				if anim_player.has_animation_library(""):
					anim_player.remove_animation_library("")
				anim_player.add_animation_library("", source_lib)
				print("\nAfter adding library:")
				print("  Has rifle_idle: ", anim_player.has_animation("rifle_idle"))
				print("  Has rifle_walk_forward: ", anim_player.has_animation("rifle_walk_forward"))

		anim_instance.queue_free()

	model.queue_free()
	quit()

func _find_node(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result = _find_node(child, type_name)
		if result:
			return result
	return null
