extends Node3D
## Bank map initialization script
## Sets wall collision layers for vision system

const WALL_COLLISION_LAYER: int = 2

func _ready() -> void:
	_setup_wall_collisions(self)
	VisionComponent.invalidate_wall_cache()


func _setup_wall_collisions(node: Node) -> void:
	if node is StaticBody3D:
		# 親ノード名に"wall"を含むStaticBody3Dは壁として扱う
		var parent = node.get_parent()
		if parent and "wall" in parent.name.to_lower():
			node.collision_layer = WALL_COLLISION_LAYER

	for child in node.get_children():
		_setup_wall_collisions(child)
