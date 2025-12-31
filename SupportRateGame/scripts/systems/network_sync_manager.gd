extends Node
class_name NetworkSyncManager

## ネットワーク同期マネージャー
## オンラインマッチ時のプレイヤー位置/アクション同期を管理

# =====================================
# シグナル
# =====================================
signal remote_player_joined(user_id: String, username: String)
signal remote_player_left(user_id: String)
signal remote_player_updated(user_id: String, character_name: String, position: Vector3, rotation: float, is_moving: bool, is_running: bool)
signal remote_player_action(user_id: String, action_type: String, data: Dictionary)
signal game_state_updated(state: Dictionary)
signal team_assigned(my_team: int, opponent_team: int)  # チーム割り当て通知

# =====================================
# OpCodes（サーバーと一致させる）
# =====================================
enum OpCode {
	GAME_START = 1,
	GAME_EVENT = 2,
	TEAM_ASSIGNMENT = 5,  # チーム割り当て（ホスト→ゲスト）
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

		# アニメーション状態を取得
		var is_moving = false
		var is_running = false
		if "is_moving" in player_node:
			is_moving = player_node.is_moving
		if "is_running" in player_node:
			is_running = player_node.is_running

		var data = {
			"sender": _local_user_id,  # 送信者IDを追加
			"name": player_node.name,  # キャラクター名を追加
			"x": position.x,
			"y": position.y,
			"z": position.z,
			"r": rotation,
			"m": is_moving,  # 移動中フラグ
			"run": is_running,  # 走りフラグ
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
	# 自分自身のデータは無視（sender_idが空でない場合のみ）
	if not sender_id.is_empty() and sender_id == _local_user_id:
		return

	match op_code:
		OpCode.PLAYER_POSITION:
			_handle_player_position(sender_id, data)
		OpCode.PLAYER_ACTION:
			_handle_player_action(sender_id, data)
		OpCode.GAME_EVENT:
			_handle_game_event(data)
		OpCode.TEAM_ASSIGNMENT:
			_handle_team_assignment(data)
		_:
			print("[NetworkSync] Unknown op_code: ", op_code)

func _handle_player_position(sender_id: String, data: Dictionary) -> void:
	# データからsender_idを取得（presenceが含まれない場合の対策）
	var actual_sender = data.get("sender", sender_id)
	if actual_sender.is_empty():
		actual_sender = sender_id

	# 自分自身のデータは無視
	if actual_sender == _local_user_id:
		return

	var character_name = data.get("name", "")
	var position = Vector3(
		data.get("x", 0.0),
		data.get("y", 0.0),
		data.get("z", 0.0)
	)
	var rotation = data.get("r", 0.0)
	var is_moving = data.get("m", false)
	var is_running = data.get("run", false)

	# リモートプレイヤー情報を更新
	if _remote_players.has(actual_sender):
		_remote_players[actual_sender].position = position
		_remote_players[actual_sender].rotation = rotation
		_remote_players[actual_sender].character_name = character_name
		_remote_players[actual_sender].is_moving = is_moving
		_remote_players[actual_sender].is_running = is_running
	else:
		_remote_players[actual_sender] = {
			"position": position,
			"rotation": rotation,
			"character_name": character_name,
			"is_moving": is_moving,
			"is_running": is_running,
			"node": null
		}

	remote_player_updated.emit(actual_sender, character_name, position, rotation, is_moving, is_running)

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
# チーム割り当て
# =====================================

## チーム割り当てを送信（ホストのみ）
## host_team: ホストに割り当てるチーム（0=CT, 1=TERRORIST）
func send_team_assignment(host_team: int) -> void:
	if not GameManager.is_host:
		return

	var guest_team = 1 - host_team  # 反対のチーム
	var data = {
		"host_team": host_team,
		"guest_team": guest_team
	}
	NakamaClient.send_match_data(OpCode.TEAM_ASSIGNMENT, data)
	print("[NetworkSync] Sent team assignment: host=%d, guest=%d" % [host_team, guest_team])

## チーム割り当て受信ハンドラ（ゲスト側）
func _handle_team_assignment(data: Dictionary) -> void:
	# ゲストはguest_teamを自分のチームとして受け取る
	var my_team = data.get("guest_team", 0)
	var opponent_team = data.get("host_team", 1)

	GameManager.assigned_team = my_team as GameManager.Team
	print("[NetworkSync] Received team assignment: my_team=%d, opponent=%d" % [my_team, opponent_team])

	team_assigned.emit(my_team, opponent_team)

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
