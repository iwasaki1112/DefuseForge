extends Node3D

var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _hips_bone_idx: int = -1
var _frame_count: int = 0

func _ready():
	# Use the animation source GLB directly (includes model + animations)
	var anim_source = load("res://assets/animations/character_anims.glb") as PackedScene
	var model = anim_source.instantiate()
	model.name = "CharacterModel"
	add_child(model)

	# Find the AnimationPlayer in the model
	for child in model.get_children():
		if child is AnimationPlayer:
			_anim_player = child
			break

	# Find skeleton
	_skeleton = _find_skeleton(model)
	if _skeleton:
		_hips_bone_idx = _skeleton.find_bone("mixamorig_Hips")
		print("[Test] Skeleton found, Hips bone index: ", _hips_bone_idx)
	else:
		print("[Test] ERROR: Skeleton not found!")

	print("[Test] Using character_anims.glb directly")

	# Debug info
	print("[Test] AnimationPlayer root_node: ", _anim_player.root_node)
	print("[Test] Has rifle_idle: ", _anim_player.has_animation("rifle_idle"))
	print("[Test] Has rifle_walk_forward: ", _anim_player.has_animation("rifle_walk_forward"))

	# Try to play animation
	if _anim_player.has_animation("rifle_walk_forward"):
		_anim_player.play("rifle_walk_forward")
		print("[Test] Playing rifle_walk_forward")
	else:
		print("[Test] ERROR: Animation not found")

func _process(_delta):
	_frame_count += 1
	if _anim_player and _anim_player.is_playing() and _skeleton and _hips_bone_idx >= 0:
		# Only print every 30 frames to reduce spam
		if _frame_count % 30 == 0:
			var hips_pos = _skeleton.get_bone_pose_position(_hips_bone_idx)
			var hips_rot = _skeleton.get_bone_pose_rotation(_hips_bone_idx)
			print("[Test] Frame %d - Hips pos: %s, rot: %s" % [_frame_count, hips_pos, hips_rot])

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
