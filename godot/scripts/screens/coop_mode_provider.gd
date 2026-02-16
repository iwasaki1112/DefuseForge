class_name CoopModeProvider
extends MultiplayerModeProvider
## COOPモード用プロバイダー
##
## 2v2 COOP: 全プレイヤーがCTチーム + AI敵がTチーム。
## MultiplayerModeProviderを継承し、チーム割り当てとスポーンをオーバーライド。


func get_mode_name() -> String:
	return "coop"


func determine_player_team() -> void:
	# COOPでは全プレイヤーがCT
	PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)


## COOPモード用キャラクタースポーン
## 全プレイヤー = CT（alphaプリセット）、AI敵 = T（aresプリセット）
func spawn_characters(_screen: Node, game_manager: GameManager) -> bool:
	if not game_manager.has_map():
		push_warning("[CoopModeProvider] Cannot spawn characters - no map loaded yet")
		return true

	var preset = game_manager.get_current_map_preset()
	if not preset:
		push_error("[CoopModeProvider] Cannot spawn characters - no map preset")
		return true

	var players := network_manager.get_players()

	# peer_idでソートして確定的な順序でスポーン
	var sorted_peer_ids: Array[int] = []
	for pid in players.keys():
		sorted_peer_ids.append(pid)
	sorted_peer_ids.sort()

	var network_id_counter: int = 1
	var ct_spawns: Array = preset.spawn_points_ct
	var ct_rotations: Array = preset.spawn_rotations_ct
	var spawn_index: int = 0

	# 全プレイヤーをCTとしてスポーン
	for peer_id in sorted_peer_ids:
		var spawn_pos: Vector3
		if spawn_index < ct_spawns.size():
			spawn_pos = ct_spawns[spawn_index]
		else:
			# スポーンポイント不足 → 1人目の位置から2mオフセット
			spawn_pos = ct_spawns[0] + Vector3(2.0 * spawn_index, 0, 0)

		var spawn_rot: float = 0.0
		if spawn_index < ct_rotations.size():
			spawn_rot = ct_rotations[spawn_index]
		elif ct_rotations.size() > 0:
			spawn_rot = ct_rotations[0]

		var char_preset = CharacterRegistry.get_preset("alpha")
		if not char_preset:
			push_error("[CoopModeProvider] Character preset 'alpha' not found")
			continue

		var character = CharacterRegistry.create_character(char_preset.id, spawn_pos)
		if character:
			character.team = GameCharacter.Team.COUNTER_TERRORIST
			character.marker_name = "alpha_%d" % spawn_index
			var direction := Vector3(sin(spawn_rot), 0, cos(spawn_rot))
			character.set_initial_facing(direction)
			game_manager.get_character_parent().add_child(character)
			game_manager.register_character_with_network(character, peer_id, network_id_counter)
			network_id_counter += 1

		spawn_index += 1

	# AI敵をTスポーンポイントにスポーン
	var t_spawns: Array = preset.spawn_points_t
	var t_rotations: Array = preset.spawn_rotations_t
	var ares_preset = CharacterRegistry.get_preset("ares")
	if ares_preset:
		for i in range(t_spawns.size()):
			var enemy = CharacterRegistry.create_character(ares_preset.id, t_spawns[i])
			if enemy:
				enemy.team = GameCharacter.Team.TERRORIST
				if i < t_rotations.size():
					var dir := Vector3(sin(t_rotations[i]), 0, cos(t_rotations[i]))
					enemy.set_initial_facing(dir)
				game_manager.get_character_parent().add_child(enemy)

				# AI敵: owner_peer_id=0（どのプレイヤーにも属さない）
				# ホストが制御し、SyncControllerで状態同期
				game_manager.register_character_with_network(enemy, 0, network_id_counter)
				network_id_counter += 1

				# クライアント側: AI敵のcombat_awarenessを無効化（ホストが制御）
				if not _is_host and enemy.combat_awareness:
					enemy.combat_awareness.disable_firing()

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)

	return true
