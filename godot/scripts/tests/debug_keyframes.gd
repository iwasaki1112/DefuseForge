extends SceneTree

func _init():
	var anim_source = load("res://assets/animations/character_anims.glb") as PackedScene
	var anim_instance = anim_source.instantiate()

	var source_player: AnimationPlayer = null
	for child in anim_instance.get_children():
		if child is AnimationPlayer:
			source_player = child
			break

	print("\n=== Animation Keyframe Analysis ===")

	if source_player:
		var anim = source_player.get_animation("rifle_idle")
		if anim:
			print("Animation: rifle_idle")
			print("Length: ", anim.length, "s")
			print("Loop mode: ", anim.loop_mode)
			print("Track count: ", anim.get_track_count())

			# Check first few tracks for keyframe data
			print("\nFirst 5 tracks:")
			for i in range(min(5, anim.get_track_count())):
				var path = anim.track_get_path(i)
				var type = anim.track_get_type(i)
				var key_count = anim.track_get_key_count(i)

				var type_str = "UNKNOWN"
				match type:
					Animation.TYPE_VALUE: type_str = "VALUE"
					Animation.TYPE_POSITION_3D: type_str = "POSITION_3D"
					Animation.TYPE_ROTATION_3D: type_str = "ROTATION_3D"
					Animation.TYPE_SCALE_3D: type_str = "SCALE_3D"

				print("  Track %d: %s (%s) - %d keys" % [i, path, type_str, key_count])

				if key_count > 0:
					var first_key = anim.track_get_key_value(i, 0)
					print("    First key value: ", first_key)

	anim_instance.queue_free()
	quit()
