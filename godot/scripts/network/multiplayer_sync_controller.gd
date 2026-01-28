extends Node
class_name MultiplayerSyncController
## マルチプレイヤー同期コントローラー
## GameManagerとLocalNetworkBus間の同期処理を管理

## 同期イベントシグナル
signal sync_state_received(snapshot: SyncState.GameStateSnapshot)
signal path_confirmed_remote(player_id: int, path_msg: NetworkMessages.PathConfirmMessage)
signal character_updated_remote(char_state: NetworkMessages.CharacterStateMessage)
signal round_state_updated(round_state: NetworkMessages.RoundStateMessage)
signal game_event_received(event: NetworkMessages.GameEventMessage)

## 参照（LocalNetworkBusまたはNetworkBusAdapterを受け入れ）
var network_bus: Node
var game_manager: GameManager
var peer_id: int = 0
var is_host: bool = false

## 同期設定
var _sync_timer: float = 0.0
var _sync_interval: float = 1.0 / NetworkConstants.SYNC_RATE_HZ
var _auto_sync_enabled: bool = true


func setup(bus: Node, gm: GameManager, my_peer_id: int, host: bool) -> void:
	network_bus = bus
	game_manager = gm
	peer_id = my_peer_id
	is_host = host

	# ネットワークバスのシグナル接続
	if not network_bus.message_received.is_connected(_on_message_received):
		network_bus.message_received.connect(_on_message_received)

	# GameManagerをマルチプレイヤーモードに
	game_manager.enable_multiplayer_mode(peer_id)

	# Hostの場合、RoundManagerに権限を設定
	if is_host and game_manager.round_manager:
		game_manager.round_manager.set_authority(true)


func _process(delta: float) -> void:
	if not _auto_sync_enabled:
		return

	_sync_timer += delta
	if _sync_timer >= _sync_interval:
		_sync_timer = 0.0
		if is_host:
			# ホストは全状態を送信
			send_state_sync()
		else:
			# クライアントは自分のキャラクター状態のみ送信
			send_local_character_states()


## 状態同期を送信（Host→Client）
func send_state_sync() -> void:
	if not is_host or not game_manager:
		return

	var snapshot := game_manager.get_game_state_snapshot()
	var data := _snapshot_to_dict(snapshot)

	network_bus.broadcast_from_host(
		NetworkConstants.MessageType.GAME_STATE_SYNC,
		data
	)


## ローカルキャラクターの状態をホストに送信（Client→Host）
func send_local_character_states() -> void:
	if is_host or not game_manager:
		return

	var my_characters := game_manager.find_characters_by_owner(peer_id)
	for character in my_characters:
		var char_state := character.to_character_state()
		send_character_update(char_state)


## パス確定を送信
func send_path_confirm(path_msg: NetworkMessages.PathConfirmMessage) -> void:
	var data := _path_message_to_dict(path_msg)

	if is_host:
		# Hostは全Clientへブロードキャスト
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.PATH_CONFIRM,
			data
		)
	else:
		# ClientはHostへ送信
		network_bus.send_message(
			peer_id,
			LocalNetworkBus.HOST_PEER_ID,
			NetworkConstants.MessageType.PATH_CONFIRM,
			data
		)


## パス実行を送信（Host→Client）
func send_path_execute(run: bool) -> void:
	if not is_host:
		return

	network_bus.broadcast_from_host(
		NetworkConstants.MessageType.PATH_EXECUTE,
		{"run": run}
	)


## キャラクター更新を送信
func send_character_update(char_state: NetworkMessages.CharacterStateMessage) -> void:
	var data := _char_state_to_dict(char_state)

	if is_host:
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.CHARACTER_UPDATE,
			data
		)
	else:
		network_bus.send_message(
			peer_id,
			LocalNetworkBus.HOST_PEER_ID,
			NetworkConstants.MessageType.CHARACTER_UPDATE,
			data
		)


## ラウンド状態を送信（Host→Client）
func send_round_state() -> void:
	if not is_host or not game_manager.round_manager:
		return

	var round_state := game_manager.round_manager.to_round_state()
	var data := _round_state_to_dict(round_state)

	network_bus.broadcast_from_host(
		NetworkConstants.MessageType.ROUND_STATE,
		data
	)


## ゲームイベントを送信
func send_game_event(event: NetworkMessages.GameEventMessage) -> void:
	var data := _game_event_to_dict(event)

	if is_host:
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.GAME_EVENT,
			data
		)
	else:
		network_bus.send_message(
			peer_id,
			LocalNetworkBus.HOST_PEER_ID,
			NetworkConstants.MessageType.GAME_EVENT,
			data
		)


## 選択状態を送信
func send_selection_update() -> void:
	if not game_manager.selection_manager:
		return

	var data := game_manager.selection_manager.to_selection_dict()

	if is_host:
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.SELECTION_UPDATE,
			data
		)
	else:
		network_bus.send_message(
			peer_id,
			LocalNetworkBus.HOST_PEER_ID,
			NetworkConstants.MessageType.SELECTION_UPDATE,
			data
		)


## メッセージ受信ハンドラ
func _on_message_received(from_peer: int, to_peer: int, msg_type: int, data: Dictionary) -> void:
	# 自分宛てまたはブロードキャストのみ処理
	if to_peer != peer_id and to_peer != 0:
		return

	match msg_type:
		NetworkConstants.MessageType.GAME_STATE_SYNC:
			_handle_state_sync(data)
		NetworkConstants.MessageType.PATH_CONFIRM:
			_handle_path_confirm(from_peer, data)
		NetworkConstants.MessageType.PATH_EXECUTE:
			_handle_path_execute(data)
		NetworkConstants.MessageType.CHARACTER_UPDATE:
			_handle_character_update(data)
		NetworkConstants.MessageType.ROUND_STATE:
			_handle_round_state(data)
		NetworkConstants.MessageType.GAME_EVENT:
			_handle_game_event(from_peer, data)
		NetworkConstants.MessageType.SELECTION_UPDATE:
			_handle_selection_update(from_peer, data)


func _handle_state_sync(data: Dictionary) -> void:
	if is_host:
		return  # Hostは自分の状態同期を無視

	var snapshot := _dict_to_snapshot(data)
	game_manager.apply_game_state_snapshot(snapshot)
	sync_state_received.emit(snapshot)


func _handle_path_confirm(from_peer: int, data: Dictionary) -> void:
	var path_msg := _dict_to_path_message(data)

	if is_host:
		# HostはClientからのパス確定を受け取り、全体に転送
		var character := game_manager.find_character_by_network_id(path_msg.character_id)
		if character:
			game_manager.path_execution_manager.confirm_path_for_player(
				from_peer, path_msg, character
			)
		# 全Clientへ転送
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.PATH_CONFIRM,
			data
		)
	else:
		# Clientはパス確定を適用
		path_confirmed_remote.emit(from_peer, path_msg)


func _handle_path_execute(data: Dictionary) -> void:
	if is_host:
		return

	var run: bool = data.get("run", false)
	game_manager.execute_all_paths(run)


func _handle_character_update(data: Dictionary) -> void:
	var char_state := _dict_to_char_state(data)
	var character := game_manager.find_character_by_network_id(char_state.character_id)
	if character:
		if not character.is_local():
			character.apply_remote_state(char_state)
		# デバッグ: 10回に1回だけログ出力
		if randi() % 30 == 0:
			print("[SYNC] CharUpdate id=%d is_local=%s pos=%s" % [char_state.character_id, character.is_local(), char_state.position])
	character_updated_remote.emit(char_state)


func _handle_round_state(data: Dictionary) -> void:
	if is_host:
		return

	var round_state := _dict_to_round_state(data)
	if game_manager.round_manager:
		game_manager.round_manager.apply_round_state(round_state)
	round_state_updated.emit(round_state)


func _handle_game_event(from_peer: int, data: Dictionary) -> void:
	var event := _dict_to_game_event(data)
	game_event_received.emit(event)

	# ホストの場合、クライアントからのイベントを他のクライアントに転送
	if is_host and from_peer != peer_id:
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.GAME_EVENT,
			data
		)

	# イベントに応じた処理
	match event.event_type:
		NetworkConstants.GameEventType.DAMAGE:
			_apply_damage_event(event)
		NetworkConstants.GameEventType.DEATH:
			_apply_death_event(event)
		NetworkConstants.GameEventType.GRENADE_THROW:
			_apply_grenade_throw_event(event)
		NetworkConstants.GameEventType.SMOKE_GRENADE_THROW:
			_apply_smoke_grenade_throw_event(event)
		NetworkConstants.GameEventType.GRENADE_EXPLODE:
			_apply_grenade_explode_event(event)
		NetworkConstants.GameEventType.SMOKE_DEPLOY:
			_apply_smoke_deploy_event(event)


func _handle_selection_update(from_peer: int, data: Dictionary) -> void:
	# 他プレイヤーの選択状態を保存（表示用）
	var selected: Array[Node] = []
	var selected_ids: Array = data.get("selected_ids", [])
	for i in range(selected_ids.size()):
		var char_id: int = selected_ids[i]
		var character: Node = game_manager.find_character_by_network_id(char_id)
		if character:
			selected.append(character)

	var primary: Node = null
	var primary_id: int = data.get("primary_id", 0)
	if primary_id != 0:
		primary = game_manager.find_character_by_network_id(primary_id)

	game_manager.selection_manager.set_selection_for_player(from_peer, selected, primary)


func _apply_damage_event(event: NetworkMessages.GameEventMessage) -> void:
	var target := game_manager.find_character_by_network_id(event.target_id)
	if target and not target.is_local():
		var amount: float = event.data.get("amount", 0.0)
		var is_headshot: bool = event.data.get("is_headshot", false)
		target.take_damage(amount, null, is_headshot)


func _apply_death_event(event: NetworkMessages.GameEventMessage) -> void:
	var target := game_manager.find_character_by_network_id(event.target_id)
	if target and target.is_alive:
		target.take_damage(target.current_health + 1)


func _apply_grenade_throw_event(event: NetworkMessages.GameEventMessage) -> void:
	# リモートからのグレネード投擲を再現（velocityとIDを使用）
	var start_pos := Vector3(
		event.data.get("start_x", 0.0),
		event.data.get("start_y", 0.0),
		event.data.get("start_z", 0.0)
	)
	var velocity := Vector3(
		event.data.get("vel_x", 0.0),
		event.data.get("vel_y", 0.0),
		event.data.get("vel_z", 0.0)
	)
	var grenade_id: int = event.data.get("grenade_id", 0)
	print("[GRENADE RECV] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	game_manager.spawn_grenade_from_network(start_pos, velocity, grenade_id)


func _apply_smoke_grenade_throw_event(event: NetworkMessages.GameEventMessage) -> void:
	# リモートからのスモークグレネード投擲を再現（velocityとIDを使用）
	var start_pos := Vector3(
		event.data.get("start_x", 0.0),
		event.data.get("start_y", 0.0),
		event.data.get("start_z", 0.0)
	)
	var velocity := Vector3(
		event.data.get("vel_x", 0.0),
		event.data.get("vel_y", 0.0),
		event.data.get("vel_z", 0.0)
	)
	var grenade_id: int = event.data.get("grenade_id", 0)
	print("[SMOKE RECV] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	game_manager.spawn_smoke_grenade_from_network(start_pos, velocity, grenade_id)


func _apply_grenade_explode_event(event: NetworkMessages.GameEventMessage) -> void:
	# リモートからのグレネード爆発を再現（正確な位置で爆発）
	var position := Vector3(
		event.data.get("pos_x", 0.0),
		event.data.get("pos_y", 0.0),
		event.data.get("pos_z", 0.0)
	)
	var grenade_id: int = event.data.get("grenade_id", 0)
	print("[GRENADE EXPLODE RECV] id=", grenade_id, " pos=", position)
	game_manager.handle_grenade_explode_from_network(grenade_id, position, false)


func _apply_smoke_deploy_event(event: NetworkMessages.GameEventMessage) -> void:
	# リモートからのスモーク展開を再現（正確な位置で展開）
	var position := Vector3(
		event.data.get("pos_x", 0.0),
		event.data.get("pos_y", 0.0),
		event.data.get("pos_z", 0.0)
	)
	var grenade_id: int = event.data.get("grenade_id", 0)
	print("[SMOKE DEPLOY RECV] id=", grenade_id, " pos=", position)
	game_manager.handle_grenade_explode_from_network(grenade_id, position, true)


# ============================================
# シリアライズ/デシリアライズ
# ============================================

func _snapshot_to_dict(snapshot: SyncState.GameStateSnapshot) -> Dictionary:
	var chars_data: Array[Dictionary] = []
	for char_state in snapshot.characters:
		chars_data.append(_char_state_to_dict(char_state))

	var round_data: Dictionary = {}
	if snapshot.round_state:
		round_data = _round_state_to_dict(snapshot.round_state)

	return {
		"timestamp": snapshot.timestamp,
		"round_state": round_data,
		"characters": chars_data
	}


func _dict_to_snapshot(data: Dictionary) -> SyncState.GameStateSnapshot:
	var snapshot := SyncState.GameStateSnapshot.new()
	snapshot.timestamp = data.get("timestamp", 0)

	if data.has("round_state") and not data["round_state"].is_empty():
		snapshot.round_state = _dict_to_round_state(data["round_state"])

	for char_data in data.get("characters", []):
		snapshot.characters.append(_dict_to_char_state(char_data))

	return snapshot


func _char_snapshot_to_dict(snap: SyncState.CharacterSnapshot) -> Dictionary:
	return {
		"network_id": snap.network_id,
		"owner_peer_id": snap.owner_peer_id,
		"position": {"x": snap.position.x, "y": snap.position.y, "z": snap.position.z},
		"rotation": snap.rotation,
		"facing_direction": {"x": snap.facing_direction.x, "y": snap.facing_direction.y, "z": snap.facing_direction.z},
		"current_health": snap.current_health,
		"max_health": snap.max_health,
		"is_alive": snap.is_alive,
		"is_crouching": snap.is_crouching,
		"team": snap.team,
		"weapon_id": snap.weapon_id,
		"animation_state": snap.animation_state
	}


func _dict_to_char_snapshot(data: Dictionary) -> SyncState.CharacterSnapshot:
	var snap := SyncState.CharacterSnapshot.new()
	snap.network_id = data.get("network_id", 0)
	snap.owner_peer_id = data.get("owner_peer_id", 0)

	var pos: Dictionary = data.get("position", {})
	snap.position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	snap.rotation = data.get("rotation", 0.0)

	var facing: Dictionary = data.get("facing_direction", {})
	snap.facing_direction = Vector3(facing.get("x", 0), facing.get("y", 0), facing.get("z", 1))

	snap.current_health = data.get("current_health", 100.0)
	snap.max_health = data.get("max_health", 100.0)
	snap.is_alive = data.get("is_alive", true)
	snap.is_crouching = data.get("is_crouching", false)
	snap.team = data.get("team", 0)
	snap.weapon_id = data.get("weapon_id", "")
	snap.animation_state = data.get("animation_state", "")

	return snap


func _path_message_to_dict(msg: NetworkMessages.PathConfirmMessage) -> Dictionary:
	var path_array: Array[Dictionary] = []
	for p in msg.path:
		path_array.append({"x": p.x, "y": p.y, "z": p.z})

	return {
		"player_id": msg.player_id,
		"character_id": msg.character_id,
		"path": path_array,
		"vision_points": msg.vision_points.duplicate(true),
		"run_segments": msg.run_segments.duplicate(true),
		"clear_points": msg.clear_points.duplicate(true),
		"grenade_markers": msg.grenade_markers.duplicate(true),
		"door_markers": msg.door_markers.duplicate(true)
	}


func _dict_to_path_message(data: Dictionary) -> NetworkMessages.PathConfirmMessage:
	var msg := NetworkMessages.PathConfirmMessage.new()
	msg.player_id = data.get("player_id", 0)
	msg.character_id = data.get("character_id", 0)

	for p in data.get("path", []):
		msg.path.append(Vector3(p.get("x", 0), p.get("y", 0), p.get("z", 0)))

	msg.vision_points = data.get("vision_points", []).duplicate(true)
	msg.run_segments = data.get("run_segments", []).duplicate(true)
	msg.clear_points = data.get("clear_points", []).duplicate(true)
	msg.grenade_markers = data.get("grenade_markers", []).duplicate(true)
	msg.door_markers = data.get("door_markers", []).duplicate(true)

	return msg


func _char_state_to_dict(state: NetworkMessages.CharacterStateMessage) -> Dictionary:
	return {
		"character_id": state.character_id,
		"position": {"x": state.position.x, "y": state.position.y, "z": state.position.z},
		"rotation": state.rotation,
		"velocity": {"x": state.velocity.x, "y": state.velocity.y, "z": state.velocity.z},
		"current_health": state.current_health,
		"is_alive": state.is_alive,
		"is_crouching": state.is_crouching,
		"animation_state": state.animation_state
	}


func _dict_to_char_state(data: Dictionary) -> NetworkMessages.CharacterStateMessage:
	var state := NetworkMessages.CharacterStateMessage.new()
	state.character_id = data.get("character_id", 0)

	var pos: Dictionary = data.get("position", {})
	state.position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	var vel: Dictionary = data.get("velocity", {})
	state.velocity = Vector3(vel.get("x", 0), vel.get("y", 0), vel.get("z", 0))

	state.rotation = data.get("rotation", 0.0)
	state.current_health = data.get("current_health", 100)
	state.is_alive = data.get("is_alive", true)
	state.is_crouching = data.get("is_crouching", false)
	state.animation_state = data.get("animation_state", "")

	return state


func _round_state_to_dict(state: NetworkMessages.RoundStateMessage) -> Dictionary:
	return {
		"phase": state.phase,
		"remaining_time": state.remaining_time,
		"ct_alive_count": state.ct_alive_count,
		"t_alive_count": state.t_alive_count,
		"winner_team": state.winner_team,
		"end_reason": state.end_reason
	}


func _dict_to_round_state(data: Dictionary) -> NetworkMessages.RoundStateMessage:
	var state := NetworkMessages.RoundStateMessage.new()
	state.phase = data.get("phase", 0)
	state.remaining_time = data.get("remaining_time", 0.0)
	state.ct_alive_count = data.get("ct_alive_count", 0)
	state.t_alive_count = data.get("t_alive_count", 0)
	state.winner_team = data.get("winner_team", 0)
	state.end_reason = data.get("end_reason", 0)
	return state


func _game_event_to_dict(event: NetworkMessages.GameEventMessage) -> Dictionary:
	return {
		"event_type": event.event_type,
		"source_id": event.source_id,
		"target_id": event.target_id,
		"data": event.data.duplicate(true)
	}


func _dict_to_game_event(data: Dictionary) -> NetworkMessages.GameEventMessage:
	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = data.get("event_type", 0)
	event.source_id = data.get("source_id", 0)
	event.target_id = data.get("target_id", 0)
	event.data = data.get("data", {}).duplicate(true)
	return event


## 自動同期の有効/無効
func set_auto_sync_enabled(enabled: bool) -> void:
	_auto_sync_enabled = enabled


## 同期間隔を設定
func set_sync_interval(interval: float) -> void:
	_sync_interval = interval
