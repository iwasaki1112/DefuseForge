extends SceneTree

func _init():
	print("\n=== Animation Check ===\n")

	var scenes = {
		"vanguard": "res://assets/characters/vanguard/vanguard.glb",
		"phantom": "res://assets/characters/phantom/phantom.glb",
		"shade": "res://assets/characters/shade/shade.glb",
	}

	for label in scenes:
		var path = scenes[label]
		print("\n--- %s ---" % label)
		var scene = load(path)
		if scene:
			var instance = scene.instantiate()
			_check_animations(instance)
			instance.free()

	quit()

func _check_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var ap = node as AnimationPlayer
		print("AnimationPlayer: %s" % node.name)
		var anims = ap.get_animation_list()
		print("  Animation count: %d" % anims.size())
		for anim in anims:
			print("    - %s" % anim)

	for child in node.get_children():
		_check_animations(child)
