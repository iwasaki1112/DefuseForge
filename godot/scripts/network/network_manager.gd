extends Node
class_name NetworkManager
## ネットワーク接続管理
## ENetを使用したP2P接続（ホスト/クライアント）

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

## 設定
const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

## 状態
var _state: ConnectionState = ConnectionState.DISCONNECTED
var _local_peer_id: int = 0
var _host_ip: String = ""
var _port: int = DEFAULT_PORT
var _peer: ENetMultiplayerPeer = null

## プレイヤー情報
var _players: Dictionary = {}  # { peer_id: { "name": String, "ready": bool, "team": int } }


func _ready() -> void:
	# マルチプレイヤーシグナル接続
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## ========================================
## 接続管理
## ========================================

## ホストとしてゲームを開始
func host_game(port: int = DEFAULT_PORT, player_name: String = "Host") -> bool:
	if _state != ConnectionState.DISCONNECTED:
		push_warning("NetworkManager: Already connected")
		return false

	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("NetworkManager: Failed to create server: %s" % error_string(error))
		connection_failed.emit("サーバー作成失敗: %s" % error_string(error))
		return false

	multiplayer.multiplayer_peer = _peer
	_port = port
	_local_peer_id = 1  # ホストは常にID=1
	_state = ConnectionState.HOST

	# 自分自身をプレイヤーリストに追加（ホストは常にCT）
	_players[_local_peer_id] = {
		"name": player_name,
		"ready": false,
		"team": GameCharacter.Team.COUNTER_TERRORIST
	}

	connection_state_changed.emit(_state)
	players_updated.emit()
	print("NetworkManager: Hosting on port %d" % port)
	return true


## クライアントとしてゲームに参加
func join_game(ip: String, port: int = DEFAULT_PORT, player_name: String = "Client") -> bool:
	if _state != ConnectionState.DISCONNECTED:
		push_warning("NetworkManager: Already connected")
		return false

	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(ip, port)
	if error != OK:
		push_error("NetworkManager: Failed to connect: %s" % error_string(error))
		connection_failed.emit("接続失敗: %s" % error_string(error))
		return false

	multiplayer.multiplayer_peer = _peer
	_host_ip = ip
	_port = port
	_state = ConnectionState.CONNECTING

	# 仮のプレイヤー情報（接続成功後に正式登録）
	_players[0] = {
		"name": player_name,
		"ready": false,
		"team": GameCharacter.Team.NONE
	}

	connection_state_changed.emit(_state)
	print("NetworkManager: Connecting to %s:%d" % [ip, port])
	return true


## 切断
func disconnect_from_game() -> void:
	if _peer:
		_peer.close()
		_peer = null

	multiplayer.multiplayer_peer = null
	_state = ConnectionState.DISCONNECTED
	_local_peer_id = 0
	_players.clear()

	connection_state_changed.emit(_state)
	print("NetworkManager: Disconnected")


## ========================================
## プレイヤー管理
## ========================================

## ローカルプレイヤーを準備完了に設定
func set_ready(is_ready: bool) -> void:
	if _local_peer_id == 0:
		return

	if _players.has(_local_peer_id):
		_players[_local_peer_id]["ready"] = is_ready

	# 全プレイヤーに通知
	rpc("_sync_player_ready", _local_peer_id, is_ready)

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
	rpc("_sync_player_team", _local_peer_id, team)


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

## メッセージを送信（特定のピアへ）
func send_message(to_peer: int, msg_type: int, data: Dictionary) -> void:
	if _state == ConnectionState.DISCONNECTED:
		return

	rpc_id(to_peer, "_receive_message", _local_peer_id, msg_type, data)


## メッセージをブロードキャスト（全員へ）
func broadcast_message(msg_type: int, data: Dictionary) -> void:
	if _state == ConnectionState.DISCONNECTED:
		return

	rpc("_receive_message", _local_peer_id, msg_type, data)


## メッセージをホストへ送信
func send_to_host(msg_type: int, data: Dictionary) -> void:
	if _state == ConnectionState.DISCONNECTED:
		return

	if is_host():
		# 自分がホストなら自分で処理
		message_received.emit(_local_peer_id, msg_type, data)
	else:
		rpc_id(1, "_receive_message", _local_peer_id, msg_type, data)


@rpc("any_peer", "reliable")
func _receive_message(from_peer: int, msg_type: int, data: Dictionary) -> void:
	message_received.emit(from_peer, msg_type, data)


## ========================================
## プレイヤー同期RPC
## ========================================

@rpc("any_peer", "reliable", "call_local")
func _sync_player_ready(peer_id: int, is_ready: bool) -> void:
	if _players.has(peer_id):
		_players[peer_id]["ready"] = is_ready

	# ホストは全員準備完了チェック
	if is_host() and _check_all_ready():
		all_peers_ready.emit()


@rpc("any_peer", "reliable", "call_local")
func _sync_player_team(peer_id: int, team: int) -> void:
	if _players.has(peer_id):
		_players[peer_id]["team"] = team


@rpc("authority", "reliable")
func _sync_all_players(players_data: Dictionary) -> void:
	_players = players_data.duplicate(true)
	players_updated.emit()


@rpc("any_peer", "reliable")
func _register_client_info(peer_id: int, info: Dictionary) -> void:
	if not is_host():
		return

	# クライアントの情報を更新
	_players[peer_id] = info.duplicate(true)

	# チームを自動割り当て（CTとTを交互に）
	var ct_count := 0
	var t_count := 0
	for pid in _players:
		if pid == peer_id:
			continue
		var team: int = _players[pid].get("team", GameCharacter.Team.NONE)
		if team == GameCharacter.Team.COUNTER_TERRORIST:
			ct_count += 1
		elif team == GameCharacter.Team.TERRORIST:
			t_count += 1

	# 人数が少ない方のチームに割り当て
	var assigned_team: int
	if ct_count <= t_count:
		assigned_team = GameCharacter.Team.COUNTER_TERRORIST
	else:
		assigned_team = GameCharacter.Team.TERRORIST
	_players[peer_id]["team"] = assigned_team

	# 全プレイヤー情報を再同期
	rpc("_sync_all_players", _players)

	# ホスト側のUIも更新
	players_updated.emit()


## ========================================
## 接続イベントハンドラ
## ========================================

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected: %d" % peer_id)

	if is_host():
		# ホストは新しいプレイヤーを登録
		_players[peer_id] = {
			"name": "Player %d" % peer_id,
			"ready": false,
			"team": GameCharacter.Team.NONE
		}

		# 全プレイヤー情報を同期
		rpc("_sync_all_players", _players)

	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer disconnected: %d" % peer_id)
	_players.erase(peer_id)
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server")
	_local_peer_id = multiplayer.get_unique_id()
	_state = ConnectionState.CONNECTED

	# 仮のプレイヤー情報を正式なIDで更新
	if _players.has(0):
		var player_info: Dictionary = _players[0]
		_players.erase(0)
		_players[_local_peer_id] = player_info

		# ホストに自分のプレイヤー情報を送信
		rpc_id(1, "_register_client_info", _local_peer_id, player_info)

	connection_state_changed.emit(_state)


func _on_connection_failed() -> void:
	print("NetworkManager: Connection failed")
	_state = ConnectionState.DISCONNECTED
	_peer = null
	multiplayer.multiplayer_peer = null
	connection_failed.emit("接続に失敗しました")
	connection_state_changed.emit(_state)


func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected")
	disconnect_from_game()


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


## 接続先IPを取得
func get_host_ip() -> String:
	return _host_ip


## ポートを取得
func get_port() -> int:
	return _port


## ローカルIPアドレスを取得（ホスト表示用）
func get_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		# IPv4でプライベートアドレスを優先
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	# 見つからなければ最初のIPv4
	for addr in addresses:
		if addr.count(".") == 3 and not addr.begins_with("127."):
			return addr
	return "127.0.0.1"
