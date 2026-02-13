extends SceneTree

func _init():
	# Simulate weapon_adjustment flow exactly

	# Step 1: Load animation library (same as weapon_adjustment._load_animation_library)
	var anim_scene = load("res://assets/animations/character_anims_kubold.glb") as PackedScene
	var anim_instance = anim_scene.instantiate()
	root.add_child(anim_instance)
	var source_player = _find_anim_player(anim_instance)
	var anim_lib: AnimationLibrary = null
	if source_player:
		anim_lib = source_player.get_animation_library("")
		print("=== Source Animation Library ===")
		print("Animations: %s" % str(anim_lib.get_animation_list()))
		var sample_anim = anim_lib.get_animation("game_rifle_idle")
		if sample_anim:
			print("game_rifle_idle tracks: %d" % sample_anim.get_track_count())
			for i in range(min(3, sample_anim.get_track_count())):
				print("  Track[%d]: %s" % [i, sample_anim.track_get_path(i)])
	anim_instance.queue_free()

	# Step 2: Load character model (same as _setup_scene)
	var char_scene = load("res://assets/characters/terrorist/ares/ares.glb") as PackedScene
	var model = char_scene.instantiate()
	model.name = "CharacterModel"
	root.add_child(model)

	print("\n=== Character Model Tree ===")
	_print_tree(model, 0)

	# Step 3: Setup AnimationPlayer with shared library (same as weapon_adjustment)
	var anim_player = _find_anim_player(model)
	if anim_player:
		print("\n=== AnimationPlayer (before library swap) ===")
		print("Path: %s" % model.get_path_to(anim_player))
		print("root_node: %s" % anim_player.root_node)
		print("Has animations: %s" % str(anim_player.get_animation_list()))

		if anim_lib:
			if anim_player.has_animation_library(""):
				anim_player.remove_animation_library("")
			anim_player.add_animation_library("", anim_lib)

		print("\n=== AnimationPlayer (after library swap) ===")
		print("Has Rifle_Idle: %s" % anim_player.has_animation("game_rifle_idle"))
		print("Has Rifle_WalkFwdLoop: %s" % anim_player.has_animation("game_rifle_walk_forward"))
		print("Animation list: %s" % str(anim_player.get_animation_list()))

		# Step 4: Change root_node like the controller does
		anim_player.root_node = NodePath("..")
		print("\n=== After root_node change to '..' ===")
		print("root_node resolves to: %s" % anim_player.get_node(anim_player.root_node).name)

		# Step 5: Check if Skeleton3D is findable from the root
		var root_node = anim_player.get_node(anim_player.root_node)
		var skeleton = _find_skeleton(root_node)
		print("Skeleton3D found: %s" % (skeleton != null))
		if skeleton:
			print("Skeleton3D path from root: %s" % root_node.get_path_to(skeleton))
			print("Skeleton3D bone count: %d" % skeleton.get_bone_count())
			var bone_names = []
			for i in range(min(5, skeleton.get_bone_count())):
				bone_names.append(skeleton.get_bone_name(i))
			print("First 5 bones: %s" % str(bone_names))

		# Step 6: Check track path resolution
		if anim_lib:
			var test_anim = anim_lib.get_animation("game_rifle_idle")
			if test_anim:
				print("\n=== Track Path Resolution Test ===")
				for i in range(min(5, test_anim.get_track_count())):
					var track_path = test_anim.track_get_path(i)
					var node_path = NodePath(str(track_path).split(":")[0])
					var target = root_node.get_node_or_null(node_path)
					var resolved = "FOUND (%s)" % target.name if target else "NOT FOUND"
					print("  Track '%s' -> %s" % [track_path, resolved])

	quit()


func _print_tree(node: Node, depth: int):
	var prefix = "  ".repeat(depth)
	var type_info = node.get_class()
	if node is Skeleton3D:
		type_info += " (bones=%d)" % node.get_bone_count()
	print("%s%s [%s]" % [prefix, node.name, type_info])
	for child in node.get_children():
		_print_tree(child, depth + 1)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_anim_player(child)
		if result:
			return result
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
