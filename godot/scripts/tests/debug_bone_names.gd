extends SceneTree

func _init():
	var preset = load("res://data/characters/dummy_t.tres")
	var anim_source = load("res://assets/animations/character_anims.glb") as PackedScene

	var model = preset.model_scene.instantiate()

	# Find skeleton
	var skeleton: Skeleton3D = null
	for child in model.get_children():
		for gc in child.get_children():
			if gc is Skeleton3D:
				skeleton = gc
				break

	print("\n=== Bone Name Comparison ===")

	if skeleton:
		print("Skeleton bones (first 10):")
		for i in range(min(10, skeleton.get_bone_count())):
			print("  ", skeleton.get_bone_name(i))

	# Get animation track bone names
	var anim_instance = anim_source.instantiate()
	var source_player: AnimationPlayer = null
	for child in anim_instance.get_children():
		if child is AnimationPlayer:
			source_player = child
			break

	if source_player:
		var anim = source_player.get_animation("rifle_idle")
		if anim:
			print("\nAnimation track bone names (first 10):")
			for i in range(min(10, anim.get_track_count())):
				var path = anim.track_get_path(i)
				var subnames = path.get_concatenated_subnames()
				print("  ", subnames)

	model.queue_free()
	anim_instance.queue_free()
	quit()
