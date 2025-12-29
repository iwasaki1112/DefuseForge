extends Node3D

## デバッグ用キャラクター確認スクリプト

var anim_player: AnimationPlayer = null
var current_anim_index: int = 0
var animations: Array = []

func _ready() -> void:
	print("=== Debug Character Scene ===")
	
	var model = $LeetModel
	if model:
		print("Model found: ", model.name)
		_print_node_tree(model, 0)
		
		# AnimationPlayerを探す
		anim_player = _find_animation_player(model)
		if anim_player:
			print("\n=== AnimationPlayer Found ===")
			print("Path: ", anim_player.get_path())
			animations = anim_player.get_animation_list()
			print("Animations: ", animations)
			
			# 最初のアニメーションを再生
			if animations.size() > 0:
				print("Playing: ", animations[0])
				anim_player.play(animations[0])
		else:
			print("ERROR: AnimationPlayer not found!")
			
		# Skeletonを探してボーン名を表示
		var skeleton = _find_skeleton(model)
		if skeleton:
			print("\n=== Skeleton Bones ===")
			for i in range(min(skeleton.get_bone_count(), 10)):
				print("  ", skeleton.get_bone_name(i))
			print("  ... (total: ", skeleton.get_bone_count(), " bones)")
	else:
		print("ERROR: LeetModel not found!")
	
	print("\n=== Controls ===")
	print("Press SPACE to cycle animations")
	print("Press 1-3 to play idle/walking/running")


func _print_node_tree(node: Node, depth: int) -> void:
	var indent = "  ".repeat(depth)
	var type_info = node.get_class()
	if node is AnimationPlayer:
		type_info += " (ANIM PLAYER!)"
	elif node is Skeleton3D:
		type_info += " (SKELETON!)"
	print(indent, node.name, " [", type_info, "]")
	for child in node.get_children():
		_print_node_tree(child, depth + 1)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
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


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE and anim_player and animations.size() > 0:
			current_anim_index = (current_anim_index + 1) % animations.size()
			var anim_name = animations[current_anim_index]
			print("Playing: ", anim_name)
			anim_player.play(anim_name)
		elif event.keycode == KEY_1:
			_try_play("idle")
		elif event.keycode == KEY_2:
			_try_play("walking")
		elif event.keycode == KEY_3:
			_try_play("running")


func _try_play(anim_name: String) -> void:
	if anim_player:
		if anim_player.has_animation(anim_name):
			print("Playing: ", anim_name)
			anim_player.play(anim_name)
		else:
			print("Animation not found: ", anim_name)
			print("Available: ", anim_player.get_animation_list())
