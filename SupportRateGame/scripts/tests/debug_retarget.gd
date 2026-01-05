extends SceneTree

func _init() -> void:
	# Load the retargeted FBX
	var retarget_path := "res://assets/characters/animations/retargeted/rifle_idle_retargeted.fbx"
	var scene := load(retarget_path)
	if not scene:
		print("ERROR: Failed to load FBX")
		quit()
		return

	var instance: Node = scene.instantiate()
	var anim_player := instance.get_node_or_null("AnimationPlayer") as AnimationPlayer

	if not anim_player:
		print("ERROR: No AnimationPlayer found")
		quit()
		return

	print("=== Retargeted FBX Animation Debug ===")
	print("Animations: ", anim_player.get_animation_list())

	for anim_name in anim_player.get_animation_list():
		var anim := anim_player.get_animation(anim_name)
		print("\n--- Animation: %s ---" % anim_name)
		print("Duration: %.2f sec" % anim.length)
		print("Track count: %d" % anim.get_track_count())

		# Print first 10 tracks
		for i in range(mini(anim.get_track_count(), 20)):
			var path := str(anim.track_get_path(i))
			var track_type := anim.track_get_type(i)
			var type_name := ""
			match track_type:
				Animation.TYPE_POSITION_3D:
					type_name = "POSITION"
				Animation.TYPE_ROTATION_3D:
					type_name = "ROTATION"
				Animation.TYPE_SCALE_3D:
					type_name = "SCALE"
				_:
					type_name = "OTHER"
			print("  Track %d: %s [%s]" % [i, path, type_name])

		if anim.get_track_count() > 20:
			print("  ... and %d more tracks" % (anim.get_track_count() - 20))

	# Also check character skeleton bone names
	print("\n=== Character Skeleton Bone Names ===")
	var char_path := "res://assets/characters/gsg9/gsg9.fbx"
	var char_scene := load(char_path)
	if char_scene:
		var char_instance: Node = char_scene.instantiate()
		var skeleton := _find_skeleton(char_instance)
		if skeleton:
			print("Skeleton bone count: %d" % skeleton.get_bone_count())
			for i in range(mini(skeleton.get_bone_count(), 20)):
				print("  Bone %d: %s" % [i, skeleton.get_bone_name(i)])
		char_instance.queue_free()

	instance.queue_free()
	quit()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null
