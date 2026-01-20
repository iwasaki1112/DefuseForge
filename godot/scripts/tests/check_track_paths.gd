extends SceneTree

func _init():
	var glb_path := "res://assets/animations/character_anims.glb"
	var scene := load(glb_path) as PackedScene
	if not scene:
		print("ERROR: Could not load GLB")
		quit()
		return

	var instance := scene.instantiate()
	var anim_player: AnimationPlayer = null

	for child in instance.get_children():
		if child is AnimationPlayer:
			anim_player = child
			break
		for grandchild in child.get_children():
			if grandchild is AnimationPlayer:
				anim_player = grandchild
				break

	if not anim_player:
		print("ERROR: No AnimationPlayer found")
		instance.queue_free()
		quit()
		return

	var lib := anim_player.get_animation_library("")
	if not lib:
		print("ERROR: No animation library")
		instance.queue_free()
		quit()
		return

	# Get rifle_idle animation and check track paths
	var anim := lib.get_animation("rifle_idle")
	if anim:
		print("\n=== rifle_idle Track Paths (first 10) ===")
		for i in range(min(10, anim.get_track_count())):
			var path := anim.track_get_path(i)
			print("  ", path)
	else:
		print("rifle_idle not found")

	instance.queue_free()
	quit()
