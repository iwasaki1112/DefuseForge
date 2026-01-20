extends Node3D
## Simple AnimationTree test - minimal setup to verify AnimationTree works

var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _skeleton: Skeleton3D
var _hips_bone_idx: int = -1
var _frame_count: int = 0

func _ready() -> void:
	# Load GLB directly
	var anim_source = load("res://assets/animations/character_anims.glb") as PackedScene
	var model = anim_source.instantiate()
	model.name = "CharacterModel"
	add_child(model)

	# Find AnimationPlayer
	for child in model.get_children():
		if child is AnimationPlayer:
			_anim_player = child
			break

	# Find skeleton
	_skeleton = _find_skeleton(model)
	if _skeleton:
		_hips_bone_idx = _skeleton.find_bone("mixamorig_Hips")
		print("[SimpleTest] Skeleton found, Hips index: %d" % _hips_bone_idx)

	print("[SimpleTest] AnimationPlayer: %s" % _anim_player)
	print("[SimpleTest] Has rifle_idle: %s" % _anim_player.has_animation("rifle_idle"))

	# Create minimal AnimationTree
	_anim_tree = AnimationTree.new()
	_anim_tree.name = "AnimationTree"
	model.add_child(_anim_tree)

	# Create simple BlendTree with just one animation
	var blend_tree = AnimationNodeBlendTree.new()

	var anim_node = AnimationNodeAnimation.new()
	anim_node.animation = "rifle_idle"

	blend_tree.add_node("Idle", anim_node, Vector2.ZERO)
	blend_tree.connect_node("output", 0, "Idle")

	_anim_tree.tree_root = blend_tree
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.root_node = NodePath("..")
	_anim_tree.active = true

	print("[SimpleTest] AnimationTree created")
	print("[SimpleTest]   active: %s" % _anim_tree.active)
	print("[SimpleTest]   anim_player: %s" % _anim_tree.anim_player)
	print("[SimpleTest]   root_node: %s" % _anim_tree.root_node)
	print("[SimpleTest]   tree_root: %s" % _anim_tree.tree_root)

	# Verify path resolution
	var resolved = _anim_tree.get_node_or_null(_anim_tree.anim_player)
	print("[SimpleTest]   anim_player resolves to: %s" % resolved)

	# Also try direct AnimationPlayer play for comparison
	# Uncomment to test: _anim_player.play("rifle_idle")


func _physics_process(_delta: float) -> void:
	_frame_count += 1
	if _skeleton and _hips_bone_idx >= 0 and _frame_count % 60 == 0:
		var hips_pos = _skeleton.get_bone_pose_position(_hips_bone_idx)
		var hips_rot = _skeleton.get_bone_pose_rotation(_hips_bone_idx)
		print("[SimpleTest] Frame %d - Hips pos: %s, rot: %s" % [_frame_count, hips_pos, hips_rot])


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
