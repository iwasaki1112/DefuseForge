class_name MultiplayerModeProvider
extends GameModeProvider
## Multiplayerモード用プロバイダー
##
## ネットワーク同期あり。NetworkManagerとSyncControllerを使用。
## ネットワーク関連の処理をすべてこのクラスに集約。

var network_manager: NetworkManager = null
var sync_controller: MultiplayerSyncController = null

var _game_screen: Node = null
var _game_manager: GameManager = null
var _local_peer_id: int = 0
var _is_host: bool = false


## NetworkManagerを設定（LobbyScreenから呼ばれる）
func setup_network(net_manager: NetworkManager) -> void:
	network_manager = net_manager
	_local_peer_id = network_manager.get_local_peer_id()
	_is_host = network_manager.is_host()
	PlayerState.set_local_peer_id(_local_peer_id)


func get_mode_name() -> String:
	return "multiplayer"


func initialize(game_screen: Node, game_manager: GameManager) -> void:
	_game_screen = game_screen
	_game_manager = game_manager

	# SyncControllerをセットアップ
	_setup_sync_controller()

	# ネットワークイベントを接続
	_connect_network_events()


func _setup_sync_controller() -> void:
	if not network_manager or not _game_screen:
		return

	# ネットワークバスをラップするアダプタを作成
	var network_adapter := NetworkBusAdapter.new()
	network_adapter.setup(network_manager)
	_game_screen.add_child(network_adapter)

	sync_controller = MultiplayerSyncController.new()
	sync_controller.name = "SyncController"
	_game_screen.add_child(sync_controller)
	sync_controller.setup(network_adapter, _game_manager, _local_peer_id, _is_host)


func _connect_network_events() -> void:
	if not network_manager or not _game_manager:
		return

	network_manager.peer_disconnected.connect(_on_peer_disconnected)
	network_manager.message_received.connect(_on_network_message)
	_game_manager.grenade_network_event.connect(_on_grenade_network_event)
	_game_manager.grenade_explode_network_event.connect(_on_grenade_explode_network_event)
	_game_manager.door_open_network_event.connect(_on_door_open_network_event)
	_game_manager.door_kick_network_event.connect(_on_door_kick_network_event)
	_game_manager.door_close_network_event.connect(_on_door_close_network_event)
	_game_manager.damage_network_event.connect(_on_damage_network_event)




func determine_player_team() -> void:
	var players := network_manager.get_players()
	var my_info: Dictionary = players.get(_local_peer_id, {})
	var my_team: int = my_info.get("team", GameCharacter.Team.NONE)
	PlayerState.set_player_team(my_team)


func get_character_owner_id(team: int) -> int:
	var players := network_manager.get_players()
	for peer_id in players:
		var info: Dictionary = players[peer_id]
		if info.get("team", GameCharacter.Team.NONE) == team:
			return peer_id
	return _local_peer_id


func register_character(game_manager: GameManager, character: GameCharacter, network_id: int) -> void:
	var owner_id := get_character_owner_id(character.team)
	game_manager.register_character_with_network(character, owner_id, network_id)


## マルチプレイヤー用キャラクタースポーン
## peer_idでソートして確定的な順序でスポーン（ホストとクライアントで同じnetwork_idになるように）
func spawn_characters(game_screen: Node, game_manager: GameManager) -> bool:
	if not game_manager.has_map():
		push_warning("[MultiplayerModeProvider] Cannot spawn characters - no map loaded yet")
		return true  # 処理済み扱い（エラー）

	var preset = game_manager.get_current_map_preset()
	if not preset:
		push_error("[MultiplayerModeProvider] Cannot spawn characters - no map preset")
		return true

	var players := network_manager.get_players()

	# peer_idでソートして確定的な順序でスポーン
	var sorted_peer_ids: Array[int] = []
	for pid in players.keys():
		sorted_peer_ids.append(pid)
	sorted_peer_ids.sort()

	var network_id_counter: int = 1

	for peer_id in sorted_peer_ids:
		var info: Dictionary = players[peer_id]
		var team: int = info.get("team", GameCharacter.Team.NONE)

		# チームに基づいてキャラクターをスポーン（TPS: 1プレイヤー1体）
		if team == GameCharacter.Team.COUNTER_TERRORIST:
			network_id_counter = _spawn_team_characters_for_player(
				game_screen, game_manager, preset,
				peer_id, team,
				preset.spawn_points_ct, preset.spawn_rotations_ct,
				["alpha"], "alpha",
				network_id_counter
			)
		elif team == GameCharacter.Team.TERRORIST:
			network_id_counter = _spawn_team_characters_for_player(
				game_screen, game_manager, preset,
				peer_id, team,
				preset.spawn_points_t, preset.spawn_rotations_t,
				["ares"], "ares",
				network_id_counter
			)

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)

	return true  # スポーン処理完了


## プレイヤー用のチームキャラクターをスポーン
func _spawn_team_characters_for_player(
	_screen: Node,
	game_manager: GameManager,
	_preset,
	owner_peer_id: int,
	team: int,
	spawn_points: Array,
	spawn_rotations: Array,
	marker_names: Array,
	preset_id: String,
	network_id_counter: int
) -> int:
	var char_preset = CharacterRegistry.get_preset(preset_id)
	if not char_preset:
		push_error("[MultiplayerModeProvider] Character preset not found: %s" % preset_id)
		return network_id_counter

	var count := mini(marker_names.size(), spawn_points.size())

	for i in range(count):
		var spawn_pos: Vector3 = spawn_points[i]
		var character = CharacterRegistry.create_character(char_preset.id, spawn_pos)
		if character:
			character.team = team
			# マーカー名を設定
			if i < marker_names.size():
				character.marker_name = marker_names[i]
			# add_child()前に向きを設定
			if i < spawn_rotations.size():
				var spawn_rot: float = spawn_rotations[i]
				var direction := Vector3(sin(spawn_rot), 0, cos(spawn_rot))
				character.set_initial_facing(direction)

			var character_parent = game_manager.get_character_parent()
			character_parent.add_child(character)

			# 確定的なnetwork_idで登録
			game_manager.register_character_with_network(character, owner_peer_id, network_id_counter)
			network_id_counter += 1

	return network_id_counter


func send_animation_event(character_id: int, anim_event: int, extra_data: Dictionary = {}) -> void:
	if sync_controller:
		sync_controller.send_animation_event(character_id, anim_event, extra_data)


func on_round_ended(_winner: int, _reason: int) -> void:
	if _is_host and sync_controller:
		sync_controller.send_round_state()


func can_start_round() -> bool:
	return _is_host


func is_host() -> bool:
	return _is_host


func get_player_count() -> int:
	if network_manager:
		return network_manager.get_players().size()
	return 1


func cleanup() -> void:
	# シグナル切断
	if network_manager:
		if network_manager.peer_disconnected.is_connected(_on_peer_disconnected):
			network_manager.peer_disconnected.disconnect(_on_peer_disconnected)
		if network_manager.message_received.is_connected(_on_network_message):
			network_manager.message_received.disconnect(_on_network_message)
		# WebSocket切断
		network_manager.disconnect_from_game()
		if Debug.enabled: print("[MultiplayerModeProvider] WebSocket disconnected")

	if _game_manager and _game_manager.grenade_network_event.is_connected(_on_grenade_network_event):
		_game_manager.grenade_network_event.disconnect(_on_grenade_network_event)
	if _game_manager and _game_manager.grenade_explode_network_event.is_connected(_on_grenade_explode_network_event):
		_game_manager.grenade_explode_network_event.disconnect(_on_grenade_explode_network_event)
	if _game_manager and _game_manager.door_open_network_event.is_connected(_on_door_open_network_event):
		_game_manager.door_open_network_event.disconnect(_on_door_open_network_event)
	if _game_manager and _game_manager.door_kick_network_event.is_connected(_on_door_kick_network_event):
		_game_manager.door_kick_network_event.disconnect(_on_door_kick_network_event)
	if _game_manager and _game_manager.door_close_network_event.is_connected(_on_door_close_network_event):
		_game_manager.door_close_network_event.disconnect(_on_door_close_network_event)
	if _game_manager and _game_manager.damage_network_event.is_connected(_on_damage_network_event):
		_game_manager.damage_network_event.disconnect(_on_damage_network_event)


## ========================================
## ネットワークイベントハンドラ
## ========================================

func _on_peer_disconnected(peer_id: int) -> void:
	if Debug.enabled: print("[MultiplayerModeProvider] Peer %d disconnected" % peer_id)


func _on_network_message(_from_peer: int, _msg_type: int, _data: Dictionary) -> void:
	# sync_controllerが処理
	pass


func _on_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int) -> void:
	if not sync_controller:
		return

	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.SMOKE_GRENADE_THROW if is_smoke else NetworkConstants.GameEventType.GRENADE_THROW
	event.source_id = 0
	event.target_id = 0
	event.data = {
		"start_x": start_pos.x,
		"start_y": start_pos.y,
		"start_z": start_pos.z,
		"vel_x": velocity.x,
		"vel_y": velocity.y,
		"vel_z": velocity.z,
		"grenade_id": grenade_id,
		"thrower_team": PlayerState.get_player_team(),
	}
	sync_controller.send_game_event(event)


func _on_grenade_explode_network_event(grenade_id: int, pos: Vector3, is_smoke: bool) -> void:
	if not sync_controller:
		return

	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.SMOKE_DEPLOY if is_smoke else NetworkConstants.GameEventType.GRENADE_EXPLODE
	event.source_id = 0
	event.target_id = 0
	event.data = {
		"grenade_id": grenade_id,
		"pos_x": pos.x,
		"pos_y": pos.y,
		"pos_z": pos.z,
	}
	sync_controller.send_game_event(event)


func _on_door_open_network_event(door_id: int, character_network_id: int) -> void:
	if not sync_controller:
		return

	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.DOOR_OPEN
	event.source_id = character_network_id
	event.target_id = 0
	event.data = {
		"door_id": door_id,
		"character_id": character_network_id,
	}
	sync_controller.send_game_event(event)


func _on_door_kick_network_event(door_id: int, character_network_id: int) -> void:
	if not sync_controller:
		return

	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.DOOR_KICK
	event.source_id = character_network_id
	event.target_id = 0
	event.data = {
		"door_id": door_id,
		"character_id": character_network_id,
	}
	sync_controller.send_game_event(event)


func _on_door_close_network_event(door_id: int, character_network_id: int) -> void:
	if not sync_controller:
		return

	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.DOOR_CLOSE
	event.source_id = character_network_id
	event.target_id = 0
	event.data = {
		"door_id": door_id,
		"character_id": character_network_id,
	}
	sync_controller.send_game_event(event)


func _on_damage_network_event(attacker_id: int, target_id: int, damage: float, is_headshot: bool) -> void:
	if not sync_controller:
		return

	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.DAMAGE
	event.source_id = attacker_id
	event.target_id = target_id
	event.data = {
		"damage": damage,
		"is_headshot": is_headshot,
	}
	sync_controller.send_game_event(event)
