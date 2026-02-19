@tool
class_name BTIsWanderingEnabled extends ConditionLeaf
## Blackboard の wandering_enabled をチェック


func tick(_actor: Node, blackboard: Blackboard) -> int:
	if blackboard.get_value("wandering_enabled", false):
		return SUCCESS
	return FAILURE
