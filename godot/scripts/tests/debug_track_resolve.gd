extends Node3D
## Debug script to check if animation tracks resolve to actual nodes

func _ready() -> void:
	# Load GLB directly
	var anim_source = load("res://assets/animations/character_anims.glb") as PackedScene
	var model = anim_source.instantiate()
	model.name = "CharacterModel"
	add_child(model)

	# Find AnimationPlayer
	var anim_player: AnimationPlayer = null
	for child in model.get_children():
		if child is AnimationPlayer:
			anim_player = child
			break

	if not anim_player:
		print("[Debug] ERROR: AnimationPlayer not found")
		return

	print("[Debug] AnimationPlayer found: %s" % anim_player.name)
	print("[Debug] root_node: %s" % anim_player.root_node)

	# Get the root node that animation tracks are relative to
	var anim_root = anim_player.get_node(anim_player.root_node)
	print("[Debug] Animation root resolves to: %s" % anim_root)
	print("[Debug] Animation root path: %s" % anim_root.get_path())

	# Print model tree structure
	print("\n[Debug] === Model Tree Structure ===")
	_print_tree(model, 0)

	# Check animation tracks
	print("\n[Debug] === Animation Track Analysis ===")
	if anim_player.has_animation("rifle_walk_forward"):
		var anim = anim_player.get_animation("rifle_walk_forward")
		print("[Debug] Animation: rifle_walk_forward")
		print("[Debug] Track count: %d" % anim.get_track_count())

		# Check first few tracks
		var max_tracks = mini(10, anim.get_track_count())
		for i in range(max_tracks):
			var track_path = anim.track_get_path(i)
			var track_type = anim.track_get_type(i)
			var type_str = _track_type_to_string(track_type)

			# Try to resolve the track path
			var target_node = anim_root.get_node_or_null(track_path)
			var resolves = "YES" if target_node else "NO"

			print("[Debug] Track %d: %s (%s) -> Resolves: %s" % [i, track_path, type_str, resolves])

			if not target_node:
				# Try to find what's wrong
				var path_parts = str(track_path).split("/")
				print("[Debug]   Path parts: %s" % str(path_parts))
				_debug_path_resolution(anim_root, path_parts)

	# Find skeleton and check bone names
	print("\n[Debug] === Skeleton Bone Names ===")
	var skeleton = _find_skeleton(model)
	if skeleton:
		print("[Debug] Skeleton path: %s" % skeleton.get_path())
		print("[Debug] Bone count: %d" % skeleton.get_bone_count())
		# Print first 10 bone names
		for i in range(mini(10, skeleton.get_bone_count())):
			print("[Debug] Bone %d: %s" % [i, skeleton.get_bone_name(i)])
	else:
		print("[Debug] ERROR: No Skeleton3D found!")


func _print_tree(node: Node, indent: int) -> void:
	var indent_str = "  ".repeat(indent)
	var type_name = node.get_class()
	print("%s- %s (%s)" % [indent_str, node.name, type_name])

	for child in node.get_children():
		_print_tree(child, indent + 1)


func _track_type_to_string(type: int) -> String:
	match type:
		Animation.TYPE_VALUE: return "VALUE"
		Animation.TYPE_POSITION_3D: return "POSITION_3D"
		Animation.TYPE_ROTATION_3D: return "ROTATION_3D"
		Animation.TYPE_SCALE_3D: return "SCALE_3D"
		Animation.TYPE_BLEND_SHAPE: return "BLEND_SHAPE"
		Animation.TYPE_METHOD: return "METHOD"
		Animation.TYPE_BEZIER: return "BEZIER"
		Animation.TYPE_AUDIO: return "AUDIO"
		Animation.TYPE_ANIMATION: return "ANIMATION"
		_: return "UNKNOWN(%d)" % type


func _debug_path_resolution(root: Node, parts: Array) -> void:
	var current = root
	for i in range(parts.size()):
		var part = parts[i]
		# Handle property paths (contains ":")
		if ":" in part:
			var split = part.split(":")
			part = split[0]

		if part.is_empty():
			continue

		var child = current.get_node_or_null(part)
		if child:
			print("[Debug]     Part '%s' -> Found: %s" % [part, child.get_class()])
			current = child
		else:
			print("[Debug]     Part '%s' -> NOT FOUND (parent has children: %s)" % [part, _get_child_names(current)])
			break


func _get_child_names(node: Node) -> String:
	var names = []
	for child in node.get_children():
		names.append(child.name)
	return str(names)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
