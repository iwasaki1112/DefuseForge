extends Node
class_name MultiplayerSyncController
## マルチプレイヤー同期コントローラー
## GameManagerとLocalNetworkBus間の同期処理を管理

## 同期イベントシグナル
signal sync_state_received(snapshot: SyncState.GameStateSnapshot)
signal character_updated_remote(char_state: NetworkMessages.CharacterStateMessage)
signal round_state_updated(round_state: NetworkMessages.RoundStateMessage)
signal game_event_received(event: NetworkMessages.GameEventMessage)

## 参照（LocalNetworkBusまたはNetworkBusAdapterを受け入れ）
var network_bus: Node
var game_manager: GameManager
var peer_id: int = 0
var is_host: bool = false

## 同期設定
var _sync_interval: float = 1.0 / NetworkConstants.SYNC_RATE_HZ
var _auto_sync_enabled: bool = true

## Tick管理（Phase 3: Tick分離）
var _tick_counter: int = 0
var _last_sent_states: Dictionary = {}  # character_id -> last_state for delta detection
var _idle_skip_counter: int = 0  # 静止時の送信スキップカウンター


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

	# RoundManagerの権限を設定（Host=true, Client=false）
	if game_manager.round_manager:
		game_manager.round_manager.set_authority(is_host)


func _process(_delta: float) -> void:
	if not _auto_sync_enabled:
		return

	# Tick-based送信（Phase 3）
	_tick_counter += 1

	# 送信タイミングの判定
	if _tick_counter % NetworkConstants.SEND_EVERY_N_TICKS == 0:
		if is_host:
			# ホストは全状態を送信
			send_state_sync()
		else:
			# クライアントも同じ頻度で送信（デルタ検出は後で最適化）
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
## バイナリ形式で一括送信することで帯域を削減
func send_local_character_states() -> void:
	if is_host or not game_manager:
		return

	var my_characters := game_manager.find_characters_by_owner(peer_id)
	if my_characters.is_empty():
		return

	# 複数キャラクターを一括でバイナリ送信
	var states: Array[NetworkMessages.CharacterStateMessage] = []
	for character in my_characters:
		states.append(character.to_character_state())

	send_character_batch_update_binary(states)


## デルタ検出付きでローカルキャラクター状態を送信
## 変化がない場合は送信頻度を下げる
func _send_local_character_states_with_delta() -> void:
	if is_host or not game_manager:
		return

	var my_characters := game_manager.find_characters_by_owner(peer_id)
	if my_characters.is_empty():
		return

	var states_to_send: Array[NetworkMessages.CharacterStateMessage] = []
	var all_idle := true

	for character in my_characters:
		var current_state := character.to_character_state()
		var char_id := current_state.character_id

		# 前回の状態と比較
		var should_send := true
		if _last_sent_states.has(char_id):
			var last_state: NetworkMessages.CharacterStateMessage = _last_sent_states[char_id]
			should_send = _has_significant_change(last_state, current_state)

		# 速度チェック（静止判定）
		if current_state.velocity.length() > NetworkConstants.IDLE_VELOCITY_THRESHOLD:
			all_idle = false

		if should_send:
			states_to_send.append(current_state)
			_last_sent_states[char_id] = current_state

	# 静止時は送信頻度を下げる
	if all_idle:
		_idle_skip_counter += 1
		if _idle_skip_counter < NetworkConstants.IDLE_SEND_MULTIPLIER:
			return
		_idle_skip_counter = 0
	else:
		_idle_skip_counter = 0

	# 送信すべき状態がある場合のみ送信
	# 一時的に従来方式を使用（デバッグ用）
	for state in states_to_send:
		send_character_update(state)  # バイナリではなく従来のJSON方式


## 状態に有意な変化があるか判定
func _has_significant_change(old_state: NetworkMessages.CharacterStateMessage, new_state: NetworkMessages.CharacterStateMessage) -> bool:
	# 位置の変化（1cm以上）
	if old_state.position.distance_to(new_state.position) > 0.01:
		return true

	# 回転の変化（1度以上）
	if absf(old_state.rotation - new_state.rotation) > deg_to_rad(1.0):
		return true

	# HPの変化
	if old_state.current_health != new_state.current_health:
		return true

	# 生存状態の変化
	if old_state.is_alive != new_state.is_alive:
		return true

	return false


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


## キャラクター更新をバイナリ形式で送信（高効率版）
func send_character_update_binary(char_state: NetworkMessages.CharacterStateMessage) -> void:
	var binary_data := NetworkSerializer.serialize_character_state_binary(char_state)
	# JSON経由で送信するためBase64エンコード
	var encoded := Marshalls.raw_to_base64(binary_data)

	if is_host:
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.CHARACTER_UPDATE_BINARY,
			{"binary": encoded}
		)
	else:
		network_bus.send_message(
			peer_id,
			LocalNetworkBus.HOST_PEER_ID,
			NetworkConstants.MessageType.CHARACTER_UPDATE_BINARY,
			{"binary": encoded}
		)


## 複数キャラクター状態を一括送信（バイナリ形式）
func send_character_batch_update_binary(states: Array[NetworkMessages.CharacterStateMessage]) -> void:
	if states.is_empty():
		return

	var binary_data := NetworkSerializer.serialize_character_states_binary(states)
	# JSON経由で送信するためBase64エンコード
	var encoded := Marshalls.raw_to_base64(binary_data)

	if is_host:
		network_bus.broadcast_from_host(
			NetworkConstants.MessageType.CHARACTER_BATCH_UPDATE_BINARY,
			{"binary": encoded}
		)
	else:
		network_bus.send_message(
			peer_id,
			LocalNetworkBus.HOST_PEER_ID,
			NetworkConstants.MessageType.CHARACTER_BATCH_UPDATE_BINARY,
			{"binary": encoded}
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


## アニメーションイベントを即時送信
## 発砲、リロード、ヒットリアクションなどの瞬間的なアニメーションに使用
func send_animation_event(character_id: int, anim_event: NetworkConstants.AnimationEventType, extra_data: Dictionary = {}) -> void:
	var event := NetworkMessages.GameEventMessage.new()
	event.event_type = NetworkConstants.GameEventType.ANIMATION_EVENT
	event.source_id = character_id
	event.data = {
		"anim_type": anim_event,
		"timestamp": Time.get_ticks_msec()
	}
	event.data.merge(extra_data)

	send_game_event(event)


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
		NetworkConstants.MessageType.CHARACTER_UPDATE:
			_handle_character_update(data)
		NetworkConstants.MessageType.CHARACTER_UPDATE_BINARY:
			_handle_character_update_binary(data)
		NetworkConstants.MessageType.CHARACTER_BATCH_UPDATE_BINARY:
			_handle_character_batch_update_binary(data)
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


func _handle_character_update(data: Dictionary) -> void:
	var char_state := _dict_to_char_state(data)
	_apply_character_state(char_state)


func _handle_character_update_binary(data: Dictionary) -> void:
	var binary := _get_binary_from_data(data)
	if binary.is_empty():
		return
	var char_state := NetworkSerializer.deserialize_character_state_binary(binary)
	_apply_character_state(char_state)


func _handle_character_batch_update_binary(data: Dictionary) -> void:
	var binary := _get_binary_from_data(data)
	if binary.is_empty():
		return
	var states := NetworkSerializer.deserialize_character_states_binary(binary)
	for char_state in states:
		_apply_character_state(char_state)


## Dictionaryからバイナリデータを取得（JSON経由で文字列化される場合に対応）
func _get_binary_from_data(data: Dictionary) -> PackedByteArray:
	var raw = data.get("binary", null)
	if raw == null:
		return PackedByteArray()

	# 既にPackedByteArrayの場合
	if raw is PackedByteArray:
		return raw

	# 文字列（Base64）の場合
	if raw is String:
		return Marshalls.base64_to_raw(raw)

	# 配列の場合（JSONでint配列になることがある）
	if raw is Array:
		var result := PackedByteArray()
		result.resize(raw.size())
		for i in raw.size():
			result[i] = raw[i]
		return result

	return PackedByteArray()


## キャラクター状態を適用（共通処理）
func _apply_character_state(char_state: NetworkMessages.CharacterStateMessage) -> void:
	var character := game_manager.find_character_by_network_id(char_state.character_id)
	if character:
		if not character.is_local():
			character.apply_remote_state(char_state)
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
		NetworkConstants.GameEventType.ANIMATION_EVENT:
			_apply_animation_event(event)
		NetworkConstants.GameEventType.DOOR_KICK:
			_apply_door_kick_event(event)


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
	# ローカルキャラクターにのみダメージを適用（所有者側で処理）
	# リモートキャラクターは攻撃側でローカルに処理済み
	if target and target.is_local():
		var damage: float = event.data.get("damage", 0.0)
		var is_headshot: bool = event.data.get("is_headshot", false)
		target.take_damage(damage, null, is_headshot)


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
	if Debug.enabled: print("[GRENADE RECV] start=", start_pos, " vel=", velocity, " id=", grenade_id)
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
	if Debug.enabled: print("[SMOKE RECV] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	game_manager.spawn_smoke_grenade_from_network(start_pos, velocity, grenade_id)


func _apply_grenade_explode_event(event: NetworkMessages.GameEventMessage) -> void:
	# リモートからのグレネード爆発を再現（正確な位置で爆発）
	var position := Vector3(
		event.data.get("pos_x", 0.0),
		event.data.get("pos_y", 0.0),
		event.data.get("pos_z", 0.0)
	)
	var grenade_id: int = event.data.get("grenade_id", 0)
	if Debug.enabled: print("[GRENADE EXPLODE RECV] id=", grenade_id, " pos=", position)
	game_manager.handle_grenade_explode_from_network(grenade_id, position, false)


func _apply_smoke_deploy_event(event: NetworkMessages.GameEventMessage) -> void:
	# リモートからのスモーク展開を再現（正確な位置で展開）
	var position := Vector3(
		event.data.get("pos_x", 0.0),
		event.data.get("pos_y", 0.0),
		event.data.get("pos_z", 0.0)
	)
	var grenade_id: int = event.data.get("grenade_id", 0)
	if Debug.enabled: print("[SMOKE DEPLOY RECV] id=", grenade_id, " pos=", position)
	game_manager.handle_grenade_explode_from_network(grenade_id, position, true)


func _apply_animation_event(event: NetworkMessages.GameEventMessage) -> void:
	var character := game_manager.find_character_by_network_id(event.source_id)
	if not character or character.is_local():
		return  # ローカルキャラクターは自分でアニメーション管理

	var anim_type: int = event.data.get("anim_type", 0)
	var timestamp: int = event.data.get("timestamp", 0)

	# レイテンシ補正（アニメーション開始位置を調整）
	var latency_sec := (Time.get_ticks_msec() - timestamp) / 1000.0
	latency_sec = clampf(latency_sec, 0.0, 0.5)  # 最大500msまで

	var anim_ctrl = character.anim_ctrl
	if not anim_ctrl:
		return

	match anim_type:
		NetworkConstants.AnimationEventType.FIRE:
			# 発砲アニメーション（レイテンシ補正付き）
			if anim_ctrl.has_method("play_fire_animation"):
				anim_ctrl.play_fire_animation()
				# アニメーションを進める（レイテンシ補正）
				_seek_animation_forward(anim_ctrl, latency_sec)

		NetworkConstants.AnimationEventType.RELOAD:
			if anim_ctrl.has_method("play_reload"):
				anim_ctrl.play_reload()
				_seek_animation_forward(anim_ctrl, latency_sec)

		NetworkConstants.AnimationEventType.HIT_REACTION:
			var direction: int = event.data.get("direction", 0)
			if anim_ctrl.has_method("play_hit_reaction"):
				anim_ctrl.play_hit_reaction(direction)

		NetworkConstants.AnimationEventType.DEATH:
			var direction: int = event.data.get("direction", 0)
			if anim_ctrl.has_method("play_death"):
				anim_ctrl.play_death(direction, false)

		NetworkConstants.AnimationEventType.GRENADE_THROW:
			if anim_ctrl.has_method("play_grenade_throw"):
				anim_ctrl.play_grenade_throw()
				_seek_animation_forward(anim_ctrl, latency_sec)


func _apply_door_kick_event(event: NetworkMessages.GameEventMessage) -> void:
	var door_id: int = event.data.get("door_id", 0)
	var character_id: int = event.data.get("character_id", 0)

	if door_id == 0:
		push_warning("[SyncController] DOOR_KICK event missing door_id")
		return

	game_manager.apply_door_kick_from_network(door_id, character_id)


## アニメーションを指定秒数分進める（レイテンシ補正用）
func _seek_animation_forward(anim_ctrl: Node, seconds: float) -> void:
	if seconds <= 0.0:
		return

	# AnimationPlayerを取得してseek
	var anim_player: AnimationPlayer = null
	if anim_ctrl.has_method("get_animation_player"):
		anim_player = anim_ctrl.get_animation_player()
	elif anim_ctrl.get("animation_player") != null:
		anim_player = anim_ctrl.animation_player

	if anim_player and anim_player.is_playing():
		var current_pos := anim_player.current_animation_position
		var new_pos := current_pos + seconds
		anim_player.seek(new_pos, true)


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
	snap.team = data.get("team", 0)
	snap.weapon_id = data.get("weapon_id", "")
	snap.animation_state = data.get("animation_state", "")

	return snap


func _char_state_to_dict(state: NetworkMessages.CharacterStateMessage) -> Dictionary:
	return {
		"character_id": state.character_id,
		"position": {"x": state.position.x, "y": state.position.y, "z": state.position.z},
		"rotation": state.rotation,
		"velocity": {"x": state.velocity.x, "y": state.velocity.y, "z": state.velocity.z},
		"current_health": state.current_health,
		"is_alive": state.is_alive,
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
