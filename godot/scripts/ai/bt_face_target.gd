@tool
class_name BTFaceTarget extends ActionLeaf
## 追跡中の敵方向を向く


func tick(actor: Node, blackboard: Blackboard) -> int:
	var look_dir: Vector3 = blackboard.get_value("look_direction", Vector3.ZERO)
	if look_dir.length_squared() > 0.01:
		actor.set_facing_direction_vec(look_dir)
	return SUCCESS
