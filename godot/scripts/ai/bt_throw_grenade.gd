@tool
class_name BTThrowGrenade extends ActionLeaf
## グレネード投擲アクション（fire-and-forget）


func tick(actor: Node, blackboard: Blackboard) -> int:
	if not actor.combat_awareness:
		return FAILURE

	var target = actor.combat_awareness.get_current_target()
	if not target:
		return FAILURE

	var target_pos: Vector3 = target.global_position
	var char_pos: Vector3 = actor.global_position

	# 距離チェック
	var dist: float = char_pos.distance_to(target_pos)
	if dist > GameConstants.GRENADE_THROW_MAX_DISTANCE:
		return FAILURE

	var anim_ctrl = actor.get_anim_controller()
	if not anim_ctrl:
		return FAILURE

	# ターゲット方向を向く
	var dir: Vector3 = (target_pos - char_pos).normalized()
	dir.y = 0.0
	actor.set_facing_direction_vec(dir)

	# 投擲アニメ開始（距離で遠投/近投を切替）
	if dist > GameConstants.GRENADE_THROW_CLOSE_THRESHOLD:
		anim_ctrl.play_throw_far()
	else:
		anim_ctrl.play_throw_close()

	# throw_release シグナルで実際にグレネード生成
	var game_screen = actor.get_tree().get_first_node_in_group("game_screen")
	if game_screen and game_screen.game_manager and game_screen.game_manager.grenade_service:
		var grenade_service = game_screen.game_manager.grenade_service
		var captured_actor := actor
		var captured_target_pos := target_pos
		anim_ctrl.throw_release.connect(func():
			var s_pos: Vector3 = captured_actor.global_position + Vector3(0, GameConstants.GRENADE_START_HEIGHT, 0)
			grenade_service.spawn_and_throw_hand_grenade(s_pos, captured_target_pos, captured_actor)
		, CONNECT_ONE_SHOT)

	# Blackboard 更新
	blackboard.set_value("hand_grenade_count", blackboard.get_value("hand_grenade_count", 0) - 1)
	blackboard.set_value("grenade_cooldown", BTShouldThrowGrenade.GRENADE_COOLDOWN)

	return SUCCESS
