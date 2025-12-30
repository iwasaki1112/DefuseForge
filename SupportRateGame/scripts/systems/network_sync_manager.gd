extends Node
class_name NetworkSyncManager

## ネットワーク同期マネージャー
## オンラインマッチ時のプレイヤー位置/アクション同期を管理

# =====================================
# シグナル
# =====================================
signal remote_player_joined(user_id: String, username: String)
signal remote_player_left(user_id: String)
signal remote_player_updated(user_id: String, position: Vector3, rotation: float)
signal remote_player_action(user_id: String, action_type: String, data: Dictionary)
signal game_state_updated(state: Dictionary)

# =====================================
# OpCodes（サーバーと一致させる）
# =====================================
enum OpCode {
	GAME_START = 1,
	GAME_EVENT = 2,
	PLAYER_POSITION = 10,
	PLAYER_ACTION = 11,
	PHASE_CHANGE = 20,
}

# =====================================
# 変数
# =====================================
var _is_active: bool = false
var _local_user_id: String = ""
var _remote_players: Dictionary = {}  # user_id -> {position, rotation, node}
var _sync_interval: float = 0.05  # 20Hz
var _sync_timer: float = 0.0
var _last_sent_position: Vector3 = Vector3.ZERO
var _last_sent_rotation: float = 0.0
var _position_threshold: float = 0.1  # 位置変化の閾値
var _rotation_threshold: float = 0.1  # 回転変化の閾値

# =====================================
# 初期化
# =====================================
func _ready() -> void:
	set_process(false)

func activate() -> void:
	if not GameManager.is_online_match:
		return

	_is_active = true
	_local_user_id = NakamaClient.get_user_id()

	# シグナル接続
	NakamaClient.match_data_received.connect(_on_match_data_received)
	NakamaClient.match_presence_joined.connect(_on_presence_joined)
	NakamaClient.match_presence_left.connect(_on_presence_left)

	set_process(true)
	print("[NetworkSync] Activated for match: ", GameManager.current_match_id)

func deactivate() -> void:
	_is_active = false
	set_process(false)

	# シグナル切断
	if NakamaClient.match_data_received.is_connected(_on_match_data_received):
		NakamaClient.match_data_received.disconnect(_on_match_data_received)
	if NakamaClient.match_presence_joined.is_connected(_on_presence_joined):
		NakamaClient.match_presence_joined.disconnect(_on_presence_joined)
	if NakamaClient.match_presence_left.is_connected(_on_presence_left):
		NakamaClient.match_presence_left.disconnect(_on_presence_left)

	_remote_players.clear()
	print("[NetworkSync] Deactivated")

# =====================================
# プロセス
# =====================================
func _process(delta: float) -> void:
	if not _is_active:
		return

	_sync_timer += delta
	if _sync_timer >= _sync_interval:
		_sync_timer = 0.0
		_send_position_update()

# =====================================
# 位置送信
# =====================================
func _send_position_update() -> void:
	var player_node = GameManager.player
	if not player_node:
		return

	var position = player_node.global_position
	var rotation = player_node.rotation.y

	# 変化がある場合のみ送信
	var pos_changed = position.distance_to(_last_sent_position) > _position_threshold
	var rot_changed = abs(rotation - _last_sent_rotation) > _rotation_threshold

	if pos_changed or rot_changed:
		_last_sent_position = position
		_last_sent_rotation = rotation

		var data = {
			"x": position.x,
			"y": position.y,
			"z": position.z,
			"r": rotation,
			"t": Time.get_ticks_msec()  # タイムスタンプ
		}
		NakamaClient.send_match_data(OpCode.PLAYER_POSITION, data)

# =====================================
# アクション送信
# =====================================
func send_action(action_type: String, data: Dictionary = {}) -> void:
	if not _is_active:
		return

	var action_data = {
		"type": action_type,
		"data": data,
		"t": Time.get_ticks_msec()
	}
	NakamaClient.send_match_data(OpCode.PLAYER_ACTION, action_data)

## 射撃アクション
func send_shoot(target_position: Vector3, weapon_id: int) -> void:
	send_action("shoot", {
		"target_x": target_position.x,
		"target_y": target_position.y,
		"target_z": target_position.z,
		"weapon_id": weapon_id
	})

## リロードアクション
func send_reload() -> void:
	send_action("reload", {})

## 死亡アクション
func send_death(killer_id: String) -> void:
	send_action("death", {"killer_id": killer_id})

## パス設定アクション
func send_path_set(waypoints: Array) -> void:
	var wp_data = []
	for wp in waypoints:
		wp_data.append({"x": wp.x, "y": wp.y, "z": wp.z})
	send_action("path_set", {"waypoints": wp_data})

# =====================================
# ゲーム状態送信（ホストのみ）
# =====================================
func send_game_start() -> void:
	if not GameManager.is_host:
		return
	NakamaClient.send_match_data(OpCode.GAME_START, {})

func send_phase_change(phase: String, round_num: int) -> void:
	if not GameManager.is_host:
		return
	NakamaClient.send_match_data(OpCode.PHASE_CHANGE, {
		"phase": phase,
		"round": round_num
	})

# =====================================
# 受信ハンドラ
# =====================================
func _on_match_data_received(op_code: int, data: Dictionary, sender_id: String) -> void:
	# 自分自身のデータは無視
	if sender_id == _local_user_id:
		return

	match op_code:
		OpCode.PLAYER_POSITION:
			_handle_player_position(sender_id, data)
		OpCode.PLAYER_ACTION:
			_handle_player_action(sender_id, data)
		OpCode.GAME_EVENT:
			_handle_game_event(data)
		_:
			print("[NetworkSync] Unknown op_code: ", op_code)

func _handle_player_position(sender_id: String, data: Dictionary) -> void:
	var position = Vector3(
		data.get("x", 0.0),
		data.get("y", 0.0),
		data.get("z", 0.0)
	)
	var rotation = data.get("r", 0.0)

	# リモートプレイヤー情報を更新
	if _remote_players.has(sender_id):
		_remote_players[sender_id].position = position
		_remote_players[sender_id].rotation = rotation
	else:
		_remote_players[sender_id] = {
			"position": position,
			"rotation": rotation,
			"node": null
		}

	remote_player_updated.emit(sender_id, position, rotation)

func _handle_player_action(sender_id: String, data: Dictionary) -> void:
	var action_type = data.get("type", "")
	var action_data = data.get("data", {})
	remote_player_action.emit(sender_id, action_type, action_data)

func _handle_game_event(data: Dictionary) -> void:
	var event_type = data.get("event", "")

	match event_type:
		"match_ready":
			print("[NetworkSync] Match ready!")
			game_state_updated.emit(data)

		"game_start":
			print("[NetworkSync] Game starting!")
			game_state_updated.emit(data)

		"phase_change":
			print("[NetworkSync] Phase changed to: ", data.get("phase", ""))
			game_state_updated.emit(data)

		_:
			print("[NetworkSync] Unknown game event: ", event_type)

func _on_presence_joined(presences: Array) -> void:
	for presence in presences:
		var user_id = presence.get("user_id", "")
		var username = presence.get("username", "Player")

		if user_id == _local_user_id:
			continue

		if not _remote_players.has(user_id):
			_remote_players[user_id] = {
				"position": Vector3.ZERO,
				"rotation": 0.0,
				"node": null,
				"username": username
			}
			remote_player_joined.emit(user_id, username)
			print("[NetworkSync] Remote player joined: ", username)

func _on_presence_left(presences: Array) -> void:
	for presence in presences:
		var user_id = presence.get("user_id", "")

		if _remote_players.has(user_id):
			_remote_players.erase(user_id)
			remote_player_left.emit(user_id)
			print("[NetworkSync] Remote player left: ", user_id)

# =====================================
# ユーティリティ
# =====================================
func get_remote_players() -> Dictionary:
	return _remote_players

func get_remote_player_position(user_id: String) -> Vector3:
	if _remote_players.has(user_id):
		return _remote_players[user_id].position
	return Vector3.ZERO

func set_remote_player_node(user_id: String, node: Node3D) -> void:
	if _remote_players.has(user_id):
		_remote_players[user_id].node = node

func is_active() -> bool:
	return _is_active
