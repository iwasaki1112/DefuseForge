@tool
class_name BTProcessDetection extends ActionLeaf
## CombatAwarenessComponent の敵検知フェーズを実行し、
## 追跡状態と向き方向を Blackboard に書き込む


func tick(actor: Node, blackboard: Blackboard) -> int:
	var delta := get_physics_process_delta_time()

	# スプリント状態リセット（BTWander が必要に応じて true にセット）
	blackboard.set_value("is_sprinting", false)

	# グレネードクールダウン管理
	var cd: float = blackboard.get_value("grenade_cooldown", 0.0)
	if cd > 0.0:
		blackboard.set_value("grenade_cooldown", cd - delta)

	if actor.combat_awareness and actor.combat_awareness.has_method("process"):
		actor.combat_awareness.process(delta)

	# 追跡中の向き方向を Blackboard に保存
	var is_tracking := false
	var look_dir := Vector3.ZERO

	var is_manual_rotating: bool = false
	if actor.has_method("is_manual_rotating"):
		is_manual_rotating = actor.is_manual_rotating()

	if not is_manual_rotating and actor.combat_awareness and actor.combat_awareness.has_method("is_tracking_enemy"):
		if actor.combat_awareness.is_tracking_enemy():
			is_tracking = true
			look_dir = actor.combat_awareness.get_override_look_direction()

	if look_dir.length_squared() < 0.1:
		var anim_ctrl = actor.get_anim_controller()
		if anim_ctrl:
			look_dir = anim_ctrl.get_look_direction()

	blackboard.set_value("is_tracking", is_tracking)
	blackboard.set_value("look_direction", look_dir)
	blackboard.set_value("move_direction", Vector3.ZERO)

	return SUCCESS
