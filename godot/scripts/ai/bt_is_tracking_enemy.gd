@tool
class_name BTIsTrackingEnemy extends ConditionLeaf
## CombatAwarenessComponent が敵を追跡中かチェック


func tick(actor: Node, _blackboard: Blackboard) -> int:
	if actor.combat_awareness and actor.combat_awareness.has_method("is_tracking_enemy"):
		if actor.combat_awareness.is_tracking_enemy():
			return SUCCESS
	return FAILURE
