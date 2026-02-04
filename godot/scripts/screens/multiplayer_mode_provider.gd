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
	_game_manager.door_kick_network_event.connect(_on_door_kick_network_event)
	_game_manager.damage_network_event.connect(_on_damage_network_event)

	# リモートプレイヤーからのパス確定を処理
	if sync_controller:
		sync_controller.path_confirmed_remote.connect(_on_path_confirmed_remote)


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
	if _game_manager and _game_manager.door_kick_network_event.is_connected(_on_door_kick_network_event):
		_game_manager.door_kick_network_event.disconnect(_on_door_kick_network_event)
	if _game_manager and _game_manager.damage_network_event.is_connected(_on_damage_network_event):
		_game_manager.damage_network_event.disconnect(_on_damage_network_event)

	if sync_controller and sync_controller.path_confirmed_remote.is_connected(_on_path_confirmed_remote):
		sync_controller.path_confirmed_remote.disconnect(_on_path_confirmed_remote)


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


## リモートプレイヤーからのパス確定を処理
func _on_path_confirmed_remote(player_id: int, path_msg: NetworkMessages.PathConfirmMessage) -> void:
	if not _game_manager or not _game_manager.path_execution_manager:
		return

	# 自分のパスはすでにローカルで登録済みなのでスキップ
	if player_id == _local_peer_id:
		return

	# キャラクターを検索
	var character := _game_manager.find_character_by_network_id(path_msg.character_id)
	if not character:
		if Debug.enabled: print("[MultiplayerModeProvider] Character not found for path_confirm: ", path_msg.character_id)
		return

	# リモートプレイヤーのパスを登録
	_game_manager.path_execution_manager.confirm_path_for_player(
		player_id, path_msg, character
	)
