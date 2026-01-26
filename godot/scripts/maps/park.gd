extends Node3D
## Park map initialization script
## Sets wall/obstacle collision layers for vision system and path blocking

const WALL_COLLISION_LAYER: int = 2

func _ready() -> void:
	_setup_collisions(self)


func _setup_collisions(node: Node) -> void:
	if node is StaticBody3D:
		var node_name_lower = node.name.to_lower()

		# ノード自体が wall_ または door_ プレフィックスを持つ場合（-col サフィックス付き）
		if node_name_lower.begins_with("wall_") or node_name_lower.begins_with("door_"):
			node.collision_layer = WALL_COLLISION_LAYER
			if node_name_lower.begins_with("door_"):
				node.add_to_group(GameConstants.GROUP_DOORS)
				print("[PARK] Added door to group: %s" % node.name)
		else:
			# 親ノードが wall_ または door_ プレフィックスを持つ場合
			var parent = node.get_parent()
			if parent:
				var parent_name_lower = parent.name.to_lower()
				if parent_name_lower.begins_with("wall_") or parent_name_lower.begins_with("door_"):
					node.collision_layer = WALL_COLLISION_LAYER
				if parent_name_lower.begins_with("door_"):
					parent.add_to_group(GameConstants.GROUP_DOORS)
					print("[PARK] Added door to group: %s" % parent.name)

	for child in node.get_children():
		_setup_collisions(child)
