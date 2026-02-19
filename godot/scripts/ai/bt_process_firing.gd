@tool
class_name BTProcessFiring extends ActionLeaf
## 射撃判定実行


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var delta := get_physics_process_delta_time()
	if actor.combat_awareness and actor.combat_awareness.has_method("process_firing"):
		actor.combat_awareness.process_firing(delta)
	return SUCCESS
