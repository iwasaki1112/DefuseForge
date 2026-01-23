extends Node3D
## Bank map initialization script
## Sets wall/door collision layers for vision system and path blocking

const WALL_COLLISION_LAYER: int = 2

func _ready() -> void:
	_setup_collisions(self)
	VisionComponent.invalidate_wall_cache()


func _setup_collisions(node: Node) -> void:
	if node is StaticBody3D:
		var parent = node.get_parent()
		if parent:
			var parent_name_lower = parent.name.to_lower()
			# wall_ または door_ プレフィックスはレイヤー2に設定（視界遮蔽・パス遮断）
			if parent_name_lower.begins_with("wall_") or parent_name_lower.begins_with("door_"):
				node.collision_layer = WALL_COLLISION_LAYER

	for child in node.get_children():
		_setup_collisions(child)
