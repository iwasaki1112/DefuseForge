extends Node
class_name NetworkBusAdapter
## NetworkManagerをLocalNetworkBusと同じインターフェースでラップするアダプタ
##
## MultiplayerSyncControllerが実際のネットワーク通信でも動作するようにする

## シグナル（LocalNetworkBusと同じインターフェース）
signal message_received(from_peer: int, to_peer: int, msg_type: int, data: Dictionary)

## 定数（LocalNetworkBusと互換）
const HOST_PEER_ID: int = 1
const BROADCAST_ID: int = 0

var _network_manager: NetworkManager = null
var _local_peer_id: int = 0


func setup(network_manager: NetworkManager) -> void:
	_network_manager = network_manager
	_local_peer_id = network_manager.get_local_peer_id()

	# NetworkManagerのメッセージ受信をフック
	_network_manager.message_received.connect(_on_message_received)


## メッセージを送信
func send_message(_from_peer: int, to_peer: int, msg_type: int, data: Dictionary) -> void:
	if not _network_manager:
		return

	if to_peer == BROADCAST_ID:
		# ブロードキャスト
		_network_manager.broadcast_message(msg_type, data)
	elif to_peer == HOST_PEER_ID:
		# ホストへ送信
		_network_manager.send_to_host(msg_type, data)
	else:
		# 特定のピアへ送信
		_network_manager.send_message(to_peer, msg_type, data)


## ブロードキャスト（Hostから全Clientへ）- LocalNetworkBusとの互換性用
func broadcast_from_host(msg_type: int, data: Dictionary) -> void:
	if not _network_manager or not _network_manager.is_host():
		return
	_network_manager.broadcast_message(msg_type, data)


## ホストかどうか
func is_host() -> bool:
	return _network_manager.is_host() if _network_manager else false


## ローカルのpeer_idを取得
func get_local_peer_id() -> int:
	return _local_peer_id


## メッセージタイプ名を取得（デバッグ用）
func get_message_type_name(msg_type: int) -> String:
	return NetworkConstants.MessageType.keys()[msg_type] if msg_type < NetworkConstants.MessageType.size() else "UNKNOWN"


## ========================================
## 内部処理
## ========================================

func _on_message_received(from_peer: int, msg_type: int, data: Dictionary) -> void:
	# LocalNetworkBusと同じフォーマットでシグナル発行
	# to_peerは自分自身（受信側）
	message_received.emit(from_peer, _local_peer_id, msg_type, data)
