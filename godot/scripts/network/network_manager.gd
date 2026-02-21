extends Node
class_name NetworkManager
## ネットワーク接続管理
## WebSocketリレーサーバー経由でのマルチプレイ接続

## 接続状態
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	HOST,
}

## シグナル
signal connection_state_changed(state: ConnectionState)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal message_received(from_peer: int, msg_type: int, data: Dictionary)
signal all_peers_ready()
signal players_updated()

## マッチメイキングシグナル
signal match_found(room_id: String, map_id: String)

## 設定
const MAX_PLAYERS: int = 4

## 状態
var _state: ConnectionState = ConnectionState.DISCONNECTED
var _local_peer_id: int = 0
var _room_id: String = ""

## WebSocket
var _ws: WebSocketPeer = null
var _heartbeat_timer: float = 0.0

## リトライ用
var _pending_action_sent: Dictionary = {}  # 送信済みアクション（リトライ用）
var _pending_action_timer: float = 0.0
var _pending_action_retries: int = 0
const PENDING_ACTION_TIMEOUT: float = 3.0  # 3秒でリトライ
const PENDING_ACTION_MAX_RETRIES: int = 3

## プレイヤー情報
var _players: Dictionary[int, Dictionary] = {}  # { peer_id: { "name": String, "ready": bool, "team": int } }


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _ws == null:
		return

	_ws.poll()

	var ws_state := _ws.get_ready_state()

	match ws_state:
		WebSocketPeer.STATE_OPEN:
			# 保留中のアクションを実行
			_check_pending_action()

			# 送信済みアクションのリトライチェック
			_check_pending_action_retry(delta)

			# リトライ失敗で切断された場合は終了
			if _ws == null:
				return

			# メッセージ受信処理
			while _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				_handle_server_message(packet.get_string_from_utf8())

			# ハートビート
			_heartbeat_timer += delta
			if _heartbeat_timer >= NetworkConstants.HEARTBEAT_INTERVAL:
				_heartbeat_timer = 0.0
				_send_to_server({"type": "HEARTBEAT"})

		WebSocketPeer.STATE_CONNECTING:
			pass  # 接続中

		WebSocketPeer.STATE_CLOSING:
			pass  # クローズ中

		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			if Debug.enabled: print("NetworkManager: WebSocket closed (code: %d, reason: %s)" % [code, reason])
			_handle_disconnect()


## ========================================
## 接続管理
## ========================================

## リレーサーバーに接続
func _connect_to_relay() -> bool:
	if _ws != null:
		_ws.close()

	_ws = WebSocketPeer.new()

	var url: String
	if NetworkConstants.USE_LOCAL_RELAY:
		url = NetworkConstants.RELAY_SERVER_URL_LOCAL
	else:
		url = NetworkConstants.RELAY_SERVER_URL

	var error := _ws.connect_to_url(url)
	if error != OK:
		push_error("NetworkManager: Failed to connect to relay: %s" % error_string(error))
		return false

	if Debug.enabled: print("NetworkManager: Connecting to relay server: %s" % url)
	return true


var _pending_action: Dictionary = {}


## マッチメイキング開始
func find_match(player_name: String = "Player") -> bool:
	if _state != ConnectionState.DISCONNECTED:
		push_warning("NetworkManager: Already connected")
		return false

	if not _connect_to_relay():
		connection_failed.emit("リレーサーバーへの接続失敗")
		return false

	_state = ConnectionState.CONNECTING
	connection_state_changed.emit(_state)

	_pending_action = {
		"type": "FIND_MATCH",
		"player_name": player_name,
		"game_mode": SettingsManager.get_game_mode()
	}

	if Debug.enabled: print("NetworkManager: Finding match as %s" % player_name)
	return true


## マッチメイキングキャンセル
func cancel_match() -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_to_server({"type": "CANCEL_MATCH"})
	disconnect_from_game()


## 切断
func disconnect_from_game() -> void:
	if _ws != null:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_send_to_server({"type": "LEAVE_ROOM"})
		_ws.close()
		_ws = null

	_state = ConnectionState.DISCONNECTED
	_local_peer_id = 0
	_room_id = ""
	_players.clear()
	_pending_action = {}

	connection_state_changed.emit(_state)
	if Debug.enabled: print("NetworkManager: Disconnected")


func _handle_disconnect() -> void:
	if _state == ConnectionState.DISCONNECTED:
		return

	_ws = null
	_clear_pending_action_sent()
	_pending_action = {}
	var was_connected := _state == ConnectionState.CONNECTED or _state == ConnectionState.HOST
	_state = ConnectionState.DISCONNECTED
	_local_peer_id = 0
	_room_id = ""
	_players.clear()

	connection_state_changed.emit(_state)
	if was_connected:
		connection_failed.emit("接続が切断されました")


## ========================================
## プレイヤー管理
## ========================================

## ローカルプレイヤーを準備完了に設定
func set_ready(is_ready: bool) -> void:
	if _local_peer_id == 0:
		return

	if _players.has(_local_peer_id):
		_players[_local_peer_id]["ready"] = is_ready

	# 全プレイヤーに通知（リレー経由）
	broadcast_message(NetworkConstants.MessageType.PLAYER_READY, {
		"peer_id": _local_peer_id,
		"ready": is_ready
	})

	# ホストは全員準備完了チェック
	if is_host() and _check_all_ready():
		all_peers_ready.emit()


## チームを設定
func set_team(team: int) -> void:
	if _local_peer_id == 0:
		return

	if _players.has(_local_peer_id):
		_players[_local_peer_id]["team"] = team

	# 全プレイヤーに通知
	broadcast_message(NetworkConstants.MessageType.TEAM_CHANGE, {
		"peer_id": _local_peer_id,
		"team": team
	})


## プレイヤー一覧を取得
func get_players() -> Dictionary:
	return _players.duplicate(true)


## 全員準備完了か確認
func _check_all_ready() -> bool:
	if _players.size() < 2:
		return false

	for peer_id in _players:
		if not _players[peer_id]["ready"]:
			return false

	return true


## ========================================
## メッセージ送受信
## ========================================

## サーバーにJSONメッセージを送信
func _send_to_server(data: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var json := JSON.stringify(data)
	_ws.send_text(json)


## メッセージを送信（特定のピアへ）
func send_message(to_peer: int, msg_type: int, data: Dictionary) -> void:
	if _state == ConnectionState.DISCONNECTED:
		return

	_send_to_server({
		"type": "RELAY",
		"to": to_peer,
		"msg_type": msg_type,
		"data": data
	})


## メッセージをブロードキャスト（全員へ）
func broadcast_message(msg_type: int, data: Dictionary) -> void:
	if _state == ConnectionState.DISCONNECTED:
		return

	_send_to_server({
		"type": "RELAY",
		"to": 0,  # 0=ブロードキャスト
		"msg_type": msg_type,
		"data": data
	})


## メッセージをホストへ送信
func send_to_host(msg_type: int, data: Dictionary) -> void:
	if _state == ConnectionState.DISCONNECTED:
		return

	if is_host():
		# 自分がホストなら自分で処理
		message_received.emit(_local_peer_id, msg_type, data)
	else:
		send_message(1, msg_type, data)  # ホストはpeer_id=1


## サーバーからのメッセージを処理
func _handle_server_message(json_string: String) -> void:
	# 複数のJSONが連結されている場合を処理
	var messages := _split_json_messages(json_string)
	for msg_str in messages:
		_process_single_message(msg_str)


## 連結されたJSONメッセージを分割
func _split_json_messages(data: String) -> Array[String]:
	var results: Array[String] = []
	var depth := 0
	var start := 0

	for i in range(data.length()):
		var c := data[i]
		if c == "{":
			if depth == 0:
				start = i
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				results.append(data.substr(start, i - start + 1))

	return results


## 単一のJSONメッセージを処理
func _process_single_message(json_string: String) -> void:
	var msg = JSON.parse_string(json_string)
	if msg == null:
		push_error("NetworkManager: Invalid JSON: %s" % json_string)
		return
	var msg_type: String = msg.get("type", "")
	var payload = msg.get("payload", {})

	match msg_type:
		"PEER_CONNECTED":
			_on_peer_connected_relay(payload)
		"PEER_DISCONNECTED":
			_on_peer_disconnected_relay(payload)
		"MESSAGE":
			_on_relay_message(payload)
		"MATCH_FOUND":
			_on_match_found(payload)
		"ERROR":
			_on_error(payload)
		"HEARTBEAT_ACK":
			pass  # ハートビート応答
		_:
			if Debug.enabled: print("NetworkManager: Unknown message type: %s" % msg_type)


## WebSocket接続完了時の処理（_processから呼び出し）
func _check_pending_action() -> void:
	if _pending_action.is_empty():
		return

	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	if Debug.enabled: print("NetworkManager: Sending pending action: %s" % _pending_action.get("type", "unknown"))
	_send_to_server(_pending_action)

	# FIND_MATCHはマッチ待機なのでリトライ不要（相手が来るまで無制限に待つ）
	if _pending_action.get("type", "") == "FIND_MATCH":
		_pending_action = {}
		return

	# それ以外のアクションはリトライ用に保存
	_pending_action_sent = _pending_action.duplicate()
	_pending_action_timer = 0.0
	_pending_action_retries = 0
	_pending_action = {}


## 送信済みアクションのリトライチェック
func _check_pending_action_retry(delta: float) -> void:
	if _pending_action_sent.is_empty():
		return

	_pending_action_timer += delta

	if _pending_action_timer >= PENDING_ACTION_TIMEOUT:
		_pending_action_retries += 1

		if _pending_action_retries > PENDING_ACTION_MAX_RETRIES:
			if Debug.enabled: print("NetworkManager: Action failed after %d retries: %s" % [PENDING_ACTION_MAX_RETRIES, _pending_action_sent.get("type", "unknown")])
			_pending_action_sent = {}
			_handle_disconnect()
			return

		if Debug.enabled: print("NetworkManager: Retrying action (%d/%d): %s" % [_pending_action_retries, PENDING_ACTION_MAX_RETRIES, _pending_action_sent.get("type", "unknown")])
		_send_to_server(_pending_action_sent)
		_pending_action_timer = 0.0


## 送信済みアクションをクリア（レスポンス受信時に呼ぶ）
func _clear_pending_action_sent() -> void:
	_pending_action_sent = {}
	_pending_action_timer = 0.0
	_pending_action_retries = 0


## ========================================
## サーバーメッセージハンドラ
## ========================================

func _on_match_found(payload: Dictionary) -> void:
	_clear_pending_action_sent()
	_room_id = payload.get("room_id", "")
	_local_peer_id = payload.get("peer_id", 0)
	var map_id: String = payload.get("map_id", "house")

	# peer_id=1ならホスト
	if _local_peer_id == 1:
		_state = ConnectionState.HOST
	else:
		_state = ConnectionState.CONNECTED

	# プレイヤー情報を構築
	_players.clear()
	var players_data: Array = payload.get("players", [])
	for player in players_data:
		var pid: int = player.get("peer_id", 0)
		if pid > 0:
			_players[pid] = {
				"name": player.get("name", "Player"),
				"ready": true,
				"team": GameCharacter.Team.COUNTER_TERRORIST if pid == 1 else GameCharacter.Team.TERRORIST
			}

	connection_state_changed.emit(_state)
	players_updated.emit()
	match_found.emit(_room_id, map_id)
	if Debug.enabled: print("NetworkManager: Match found! Room: %s, Map: %s, PeerID: %d" % [_room_id, map_id, _local_peer_id])


func _on_peer_connected_relay(payload: Dictionary) -> void:
	var pid: int = payload.get("peer_id", 0)
	var pname: String = payload.get("name", "Player")

	if pid == 0 or pid == _local_peer_id:
		return

	# チーム自動割り当て
	var assigned_team := _get_team_to_assign()

	_players[pid] = {
		"name": pname,
		"ready": false,
		"team": assigned_team
	}

	peer_connected.emit(pid)
	players_updated.emit()
	if Debug.enabled: print("NetworkManager: Peer connected - ID: %d, Name: %s" % [pid, pname])


func _on_peer_disconnected_relay(payload: Dictionary) -> void:
	var pid: int = payload.get("peer_id", 0)
	_players.erase(pid)
	peer_disconnected.emit(pid)
	players_updated.emit()
	if Debug.enabled: print("NetworkManager: Peer disconnected - ID: %d" % pid)


func _on_relay_message(payload: Dictionary) -> void:
	var from_peer: int = payload.get("from", 0)
	var msg_type: int = payload.get("msg_type", 0)
	var data: Dictionary = payload.get("data", {})

	# プレイヤー情報更新メッセージの処理
	match msg_type:
		NetworkConstants.MessageType.PLAYER_READY:
			var pid: int = data.get("peer_id", 0)
			var is_ready: bool = data.get("ready", false)
			if _players.has(pid):
				_players[pid]["ready"] = is_ready
			players_updated.emit()
			if is_host() and _check_all_ready():
				all_peers_ready.emit()

		NetworkConstants.MessageType.TEAM_CHANGE:
			var pid: int = data.get("peer_id", 0)
			var team: int = data.get("team", 0)
			if _players.has(pid):
				_players[pid]["team"] = team
			players_updated.emit()

	message_received.emit(from_peer, msg_type, data)


func _on_error(payload: Dictionary) -> void:
	_clear_pending_action_sent()
	var error_msg: String = payload.get("message", "Unknown error")
	push_error("NetworkManager: Server error: %s" % error_msg)
	connection_failed.emit(error_msg)


## ========================================
## チーム割り当て
## ========================================

func _get_team_to_assign() -> int:
	var ct_count := 0
	var t_count := 0

	for pid in _players:
		var team: int = _players[pid].get("team", GameCharacter.Team.NONE)
		if team == GameCharacter.Team.COUNTER_TERRORIST:
			ct_count += 1
		elif team == GameCharacter.Team.TERRORIST:
			t_count += 1

	if ct_count <= t_count:
		return GameCharacter.Team.COUNTER_TERRORIST
	else:
		return GameCharacter.Team.TERRORIST


## ========================================
## ユーティリティ
## ========================================

## ホストかどうか
func is_host() -> bool:
	return _state == ConnectionState.HOST


## 接続中かどうか
func is_connected_to_game() -> bool:
	return _state == ConnectionState.CONNECTED or _state == ConnectionState.HOST


## ローカルのpeer_idを取得
func get_local_peer_id() -> int:
	return _local_peer_id


## 接続状態を取得
func get_state() -> ConnectionState:
	return _state


## ルームIDを取得
func get_room_id() -> String:
	return _room_id
