@tool
class_name BTShouldThrowGrenade extends ConditionLeaf
## グレネード投擲条件チェック

const GRENADE_COOLDOWN := 15.0


func tick(actor: Node, blackboard: Blackboard) -> int:
	# 投擲アニメ中はスキップ
	var anim_ctrl = actor.get_anim_controller()
	if anim_ctrl and anim_ctrl._is_throwing:
		return FAILURE

	# 敵追跡中のみ
	if not blackboard.get_value("is_tracking", false):
		return FAILURE

	# グレネード残数チェック
	var count: int = blackboard.get_value("hand_grenade_count", 0)
	if count <= 0:
		return FAILURE

	# クールダウンチェック
	var cooldown: float = blackboard.get_value("grenade_cooldown", 0.0)
	if cooldown > 0.0:
		return FAILURE

	return SUCCESS
