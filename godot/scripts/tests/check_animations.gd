extends SceneTree

func _init():
	var glb_path := "res://assets/animations/character_anims.glb"
	var scene := load(glb_path) as PackedScene
	if not scene:
		print("ERROR: Could not load GLB: ", glb_path)
		quit()
		return

	var instance := scene.instantiate()
	var anim_player: AnimationPlayer = null

	# Find AnimationPlayer
	for child in instance.get_children():
		if child is AnimationPlayer:
			anim_player = child
			break
		for grandchild in child.get_children():
			if grandchild is AnimationPlayer:
				anim_player = grandchild
				break

	if not anim_player:
		print("ERROR: No AnimationPlayer found in GLB")
		instance.queue_free()
		quit()
		return

	print("\n=== Animations in character_anims.glb ===")
	var lib := anim_player.get_animation_library("")
	if lib:
		var anims := lib.get_animation_list()
		print("Total animations: ", anims.size())
		for anim_name in anims:
			var anim := lib.get_animation(anim_name)
			print("  - ", anim_name, " (", anim.length, "s, ", anim.get_track_count(), " tracks)")
	else:
		print("ERROR: No animation library found")

	instance.queue_free()
	quit()
