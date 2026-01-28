class_name MultiplayerModeProvider
extends GameModeProvider
## Multiplayerモード用プロバイダー
##
## ネットワーク同期あり。NetworkManagerとSyncControllerを使用。

var network_manager: NetworkManager = null
var sync_controller: MultiplayerSyncController = null

var _local_peer_id: int = 0
var _is_host: bool = false


func setup(net_manager: NetworkManager, sync_ctrl: MultiplayerSyncController) -> void:
	network_manager = net_manager
	sync_controller = sync_ctrl
	_local_peer_id = network_manager.get_local_peer_id()
	_is_host = network_manager.is_host()
	PlayerState.set_local_peer_id(_local_peer_id)


func get_mode_name() -> String:
	return "multiplayer"


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


func on_path_confirmed() -> void:
	if sync_controller:
		sync_controller.send_state_sync()


func on_execute_paths(count: int) -> void:
	if count > 0 and sync_controller:
		sync_controller.send_path_execute(false)


func on_round_ended(_winner: int, _reason: int) -> void:
	if _is_host and sync_controller:
		sync_controller.send_round_state()


func on_grenade_thrown(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int) -> void:
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
	}
	sync_controller.send_game_event(event)


func on_grenade_exploded(grenade_id: int, position: Vector3, is_smoke: bool) -> void:
	if not sync_controller:
		return

	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.SMOKE_DEPLOY if is_smoke else NetworkConstants.GameEventType.GRENADE_EXPLODE
	event.source_id = 0
	event.target_id = 0
	event.data = {
		"grenade_id": grenade_id,
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
	}
	sync_controller.send_game_event(event)


func can_start_round() -> bool:
	return _is_host


func is_host() -> bool:
	return _is_host


func get_player_count() -> int:
	if network_manager:
		return network_manager.get_players().size()
	return 1


func cleanup() -> void:
	if network_manager:
		network_manager.disconnect_from_game()
