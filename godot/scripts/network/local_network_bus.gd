extends Node
class_name LocalNetworkBus
## ローカルネットワークシミュレーター
## 同一PC上でHost/Client間のメッセージ通信をシミュレート

## メッセージ受信シグナル
signal message_received(from_peer: int, to_peer: int, msg_type: int, data: Dictionary)
## 接続状態変更シグナル
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

## 定数
const HOST_PEER_ID: int = 1
const CLIENT_PEER_ID: int = 2

## 設定
@export var simulated_latency_ms: float = 0.0  ## シミュレートする遅延（ミリ秒）
@export var packet_loss_rate: float = 0.0  ## パケットロス率（0.0〜1.0）

## 内部状態
var _connected_peers: Array[int] = []
var _pending_messages: Array[Dictionary] = []
var _message_log: Array[Dictionary] = []
var _log_enabled: bool = true
var _max_log_size: int = 100


func _ready() -> void:
	set_process(simulated_latency_ms > 0)


func _process(delta: float) -> void:
	_process_pending_messages(delta)


## ピアを接続
func connect_peer(peer_id: int) -> void:
	if peer_id in _connected_peers:
		return
	_connected_peers.append(peer_id)
	peer_connected.emit(peer_id)
	_log_event("CONNECT", peer_id, 0, {})


## ピアを切断
func disconnect_peer(peer_id: int) -> void:
	if peer_id not in _connected_peers:
		return
	_connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)
	_log_event("DISCONNECT", peer_id, 0, {})


## 全ピアを切断
func disconnect_all() -> void:
	for peer_id in _connected_peers.duplicate():
		disconnect_peer(peer_id)


## メッセージを送信
func send_message(from_peer: int, to_peer: int, msg_type: int, data: Dictionary) -> void:
	# パケットロスシミュレーション
	if packet_loss_rate > 0 and randf() < packet_loss_rate:
		_log_event("DROPPED", from_peer, msg_type, {"to": to_peer})
		return

	var message := {
		"from": from_peer,
		"to": to_peer,
		"type": msg_type,
		"data": data.duplicate(true),
		"timestamp": Time.get_ticks_msec(),
		"deliver_at": Time.get_ticks_msec() + int(simulated_latency_ms)
	}

	if simulated_latency_ms > 0:
		_pending_messages.append(message)
		set_process(true)
	else:
		_deliver_message(message)


## ブロードキャスト（Hostから全Clientへ）
func broadcast_from_host(msg_type: int, data: Dictionary) -> void:
	for peer_id in _connected_peers:
		if peer_id != HOST_PEER_ID:
			send_message(HOST_PEER_ID, peer_id, msg_type, data)


## Host/Client両方をセットアップ
func setup_local_session() -> void:
	connect_peer(HOST_PEER_ID)
	connect_peer(CLIENT_PEER_ID)


## 保留中のメッセージを処理
func _process_pending_messages(_delta: float) -> void:
	var current_time := Time.get_ticks_msec()
	var delivered: Array[int] = []

	for i in range(_pending_messages.size()):
		var msg: Dictionary = _pending_messages[i]
		if current_time >= msg["deliver_at"]:
			_deliver_message(msg)
			delivered.append(i)

	# 逆順で削除
	delivered.reverse()
	for i in delivered:
		_pending_messages.remove_at(i)

	if _pending_messages.is_empty():
		set_process(false)


## メッセージを配信
func _deliver_message(message: Dictionary) -> void:
	var to_peer: int = message["to"]

	# 宛先が接続中か確認
	if to_peer not in _connected_peers and to_peer != 0:
		_log_event("UNDELIVERED", message["from"], message["type"], {"to": to_peer})
		return

	_log_event("DELIVERED", message["from"], message["type"], message["data"])
	message_received.emit(message["from"], message["to"], message["type"], message["data"])


## イベントをログに記録
func _log_event(event: String, peer: int, msg_type: int, data: Dictionary) -> void:
	if not _log_enabled:
		return

	var entry := {
		"time": Time.get_ticks_msec(),
		"event": event,
		"peer": peer,
		"msg_type": msg_type,
		"data": data
	}
	_message_log.append(entry)

	# ログサイズ制限
	while _message_log.size() > _max_log_size:
		_message_log.pop_front()


## ログを取得
func get_message_log() -> Array[Dictionary]:
	return _message_log.duplicate()


## ログをクリア
func clear_log() -> void:
	_message_log.clear()


## ログ出力を有効/無効
func set_log_enabled(enabled: bool) -> void:
	_log_enabled = enabled


## 接続中のピア一覧を取得
func get_connected_peers() -> Array[int]:
	return _connected_peers.duplicate()


## ピアが接続中か確認
func is_peer_connected(peer_id: int) -> bool:
	return peer_id in _connected_peers


## メッセージタイプ名を取得（デバッグ用）
func get_message_type_name(msg_type: int) -> String:
	match msg_type:
		NetworkConstants.MessageType.GAME_STATE_SYNC:
			return "GAME_STATE_SYNC"
		NetworkConstants.MessageType.CHARACTER_UPDATE:
			return "CHARACTER_UPDATE"
		NetworkConstants.MessageType.ROUND_STATE:
			return "ROUND_STATE"
		NetworkConstants.MessageType.GAME_EVENT:
			return "GAME_EVENT"
		NetworkConstants.MessageType.PLAYER_READY:
			return "PLAYER_READY"
		NetworkConstants.MessageType.PLAYER_INPUT:
			return "PLAYER_INPUT"
		NetworkConstants.MessageType.SELECTION_UPDATE:
			return "SELECTION_UPDATE"
		_:
			return "UNKNOWN(%d)" % msg_type


## ログをフォーマット（デバッグ表示用）
func format_log_entry(entry: Dictionary) -> String:
	var time_str := "%.3f" % (entry["time"] / 1000.0)
	var type_name := get_message_type_name(entry["msg_type"]) if entry["msg_type"] != 0 else ""
	return "[%s] %s peer=%d %s" % [time_str, entry["event"], entry["peer"], type_name]
