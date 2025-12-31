extends Node
## Nakamaサーバーとの通信を管理するクライアント
## Autoloadとして登録して使用

# =====================================
# シグナル
# =====================================
signal authenticated(session: NakamaSession)
signal authentication_failed(error: String)
signal socket_connected()
signal socket_disconnected()
signal socket_error(error: String)
signal match_joined(match_id: String)
signal match_left()
signal match_data_received(op_code: int, data: Dictionary, sender_id: String)
signal match_presence_joined(presences: Array)
signal match_presence_left(presences: Array)
signal matchmaker_matched(match_id: String, token: String, users: Array)
signal room_created(match_id: String, room_code: String)
signal room_create_failed(error: String)
signal rooms_listed(rooms: Array)
signal join_by_code_failed(error: String)

# =====================================
# 設定
# =====================================
@export var server_host: String = "127.0.0.1"
@export var server_port: int = 7350
@export var server_key: String = "supportrate_dev_key"
@export var use_ssl: bool = false

# =====================================
# 内部変数
# =====================================
var _http_client: HTTPRequest
var _websocket: WebSocketPeer
var _session: NakamaSession
var _current_match_id: String = ""
var _is_socket_connected: bool = false
var _pending_requests: Dictionary = {}
var _request_id_counter: int = 0

# =====================================
# 初期化
# =====================================
func _ready() -> void:
	_http_client = HTTPRequest.new()
	add_child(_http_client)
	_http_client.request_completed.connect(_on_http_request_completed)

	_websocket = WebSocketPeer.new()

func _process(_delta: float) -> void:
	if _websocket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_websocket.poll()

		var state = _websocket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not _is_socket_connected:
				_is_socket_connected = true
				socket_connected.emit()

			while _websocket.get_available_packet_count() > 0:
				var packet = _websocket.get_packet()
				_handle_socket_message(packet.get_string_from_utf8())

		elif state == WebSocketPeer.STATE_CLOSED:
			if _is_socket_connected:
				_is_socket_connected = false
				socket_disconnected.emit()

# =====================================
# 認証
# =====================================

## デバイス認証（ゲスト）
func authenticate_device(device_id: String = "", create: bool = true, username: String = "") -> void:
	var actual_device_id = device_id
	if actual_device_id.is_empty():
		actual_device_id = _get_or_create_device_id()

	var url = _build_url("/v2/account/authenticate/device")
	if create:
		url += "?create=true"
		if not username.is_empty():
			url += "&username=" + username.uri_encode()

	var body = JSON.stringify({"id": actual_device_id})
	var headers = _get_auth_headers(true)

	_make_request("authenticate_device", url, HTTPClient.METHOD_POST, headers, body)

## メール認証
func authenticate_email(email: String, password: String, create: bool = false, username: String = "") -> void:
	var url = _build_url("/v2/account/authenticate/email")
	if create:
		url += "?create=true"
		if not username.is_empty():
			url += "&username=" + username.uri_encode()

	var body = JSON.stringify({"email": email, "password": password})
	var headers = _get_auth_headers(true)

	_make_request("authenticate_email", url, HTTPClient.METHOD_POST, headers, body)

## セッションリフレッシュ
func refresh_session() -> void:
	if not _session or _session.refresh_token.is_empty():
		push_error("No session to refresh")
		return

	var url = _build_url("/v2/account/session/refresh")
	var body = JSON.stringify({"token": _session.refresh_token})
	var headers = _get_auth_headers(true)

	_make_request("refresh_session", url, HTTPClient.METHOD_POST, headers, body)

# =====================================
# WebSocket接続
# =====================================

## ソケット接続
func connect_socket() -> void:
	if not _session:
		push_error("Must authenticate before connecting socket")
		return

	var protocol = "wss" if use_ssl else "ws"
	var url = "%s://%s:%d/ws?token=%s" % [protocol, server_host, server_port, _session.token]

	var err = _websocket.connect_to_url(url)
	if err != OK:
		socket_error.emit("Failed to connect: " + str(err))

## ソケット切断
func disconnect_socket() -> void:
	_websocket.close()
	_is_socket_connected = false

# =====================================
# マッチ
# =====================================

## マッチに参加
func join_match(match_id: String) -> void:
	if not _is_socket_connected:
		push_error("Socket not connected")
		return

	var message = {
		"match_join": {
			"match_id": match_id
		}
	}
	_send_socket_message(message)

## マッチを離脱
func leave_match() -> void:
	if _current_match_id.is_empty():
		return

	var message = {
		"match_leave": {
			"match_id": _current_match_id
		}
	}
	_send_socket_message(message)
	_current_match_id = ""
	match_left.emit()

## マッチデータ送信
func send_match_data(op_code: int, data: Dictionary) -> void:
	if _current_match_id.is_empty():
		push_error("Not in a match")
		return

	var message = {
		"match_data_send": {
			"match_id": _current_match_id,
			"op_code": str(op_code),
			"data": Marshalls.utf8_to_base64(JSON.stringify(data))
		}
	}
	_send_socket_message(message)

# =====================================
# RPC
# =====================================

## ルーム作成
func create_room(team_size: int = 5, is_private: bool = false) -> void:
	var payload = JSON.stringify({
		"team_size": team_size,
		"is_private": is_private
	})
	_call_rpc("create_room", payload)

## ルームコードで参加
func join_by_code(room_code: String) -> void:
	var payload = JSON.stringify({"room_code": room_code})
	_call_rpc("join_by_code", payload)

## 公開ルーム一覧取得
func list_rooms(team_size: int = -1) -> void:
	var payload = "{}"
	if team_size > 0:
		payload = JSON.stringify({"team_size": team_size})
	_call_rpc("list_rooms", payload)

## ランダムマッチメイキング参加
func join_matchmaking(team_size: int = 5) -> void:
	if not _is_socket_connected:
		push_error("Socket not connected")
		return

	var message = {
		"matchmaker_add": {
			"min_count": team_size * 2,
			"max_count": team_size * 2,
			"query": "+properties.team_size:" + str(team_size),
			"string_properties": {
				"team_size": str(team_size)
			}
		}
	}
	_send_socket_message(message)

## マッチメイキングキャンセル
func cancel_matchmaking(ticket: String) -> void:
	var message = {
		"matchmaker_remove": {
			"ticket": ticket
		}
	}
	_send_socket_message(message)

# =====================================
# ユーティリティ
# =====================================

func get_session() -> NakamaSession:
	return _session

func is_authenticated() -> bool:
	return _session != null and not _session.is_expired()

func is_socket_connected() -> bool:
	return _is_socket_connected

func get_current_match_id() -> String:
	return _current_match_id

func get_user_id() -> String:
	if _session:
		return _session.user_id
	return ""

func get_session_id() -> String:
	if _session:
		return _session.session_id
	return ""

# =====================================
# 内部メソッド
# =====================================

func _build_url(path: String) -> String:
	var protocol = "https" if use_ssl else "http"
	return "%s://%s:%d%s" % [protocol, server_host, server_port, path]

func _get_auth_headers(basic_auth: bool = false) -> PackedStringArray:
	var headers = PackedStringArray()
	headers.append("Content-Type: application/json")

	if basic_auth:
		var credentials = Marshalls.utf8_to_base64(server_key + ":")
		headers.append("Authorization: Basic " + credentials)
	elif _session:
		headers.append("Authorization: Bearer " + _session.token)

	return headers

func _get_or_create_device_id() -> String:
	# テスト用: 毎回新しいIDを生成（同一マシンで複数クライアントをテストするため）
	# 本番では保存されたIDを使用するように変更
	if OS.has_feature("debug"):
		# デバッグビルドではランダムIDを生成（テスト用）
		var random_id = _generate_uuid()
		print("[NakamaClient] Debug mode: Generated new device ID: ", random_id)
		return random_id

	var config_path = "user://device_id.cfg"
	var config = ConfigFile.new()

	if config.load(config_path) == OK:
		return config.get_value("device", "id", "")

	# 新しいデバイスID生成
	var device_id = _generate_uuid()
	config.set_value("device", "id", device_id)
	config.save(config_path)
	return device_id

func _generate_uuid() -> String:
	var chars = "abcdef0123456789"
	var uuid = ""
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		uuid += chars[randi() % chars.length()]
	return uuid

func _make_request(request_type: String, url: String, method: int, headers: PackedStringArray, body: String = "") -> void:
	var request_id = _request_id_counter
	_request_id_counter += 1
	_pending_requests[request_id] = request_type

	# HTTPRequestノードを動的に作成（複数リクエスト対応）
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_dynamic_http_completed.bind(request_id, http))

	if body.is_empty():
		http.request(url, headers, method)
	else:
		http.request(url, headers, method, body)

func _on_dynamic_http_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request_id: int, http_node: HTTPRequest) -> void:
	http_node.queue_free()

	var request_type = _pending_requests.get(request_id, "")
	_pending_requests.erase(request_id)

	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_request_error(request_type, "HTTP request failed: " + str(result))
		return

	if response_code < 200 or response_code >= 300:
		var error_body = body.get_string_from_utf8()
		_handle_request_error(request_type, "HTTP error %d: %s" % [response_code, error_body])
		return

	var json_body = body.get_string_from_utf8()
	var json = JSON.new()
	var parse_result = json.parse(json_body)

	if parse_result != OK:
		_handle_request_error(request_type, "Failed to parse JSON response")
		return

	var data = json.data
	_handle_request_success(request_type, data)

func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# 基本的なHTTPリクエスト完了（互換性のため残す）
	pass

func _handle_request_success(request_type: String, data: Dictionary) -> void:
	match request_type:
		"authenticate_device", "authenticate_email", "refresh_session":
			_session = NakamaSession.new()
			_session.token = data.get("token", "")
			_session.refresh_token = data.get("refresh_token", "")
			_session.created = data.get("created", false)
			_parse_jwt(_session.token)
			authenticated.emit(_session)

		"create_room":
			var match_id = data.get("match_id", "")
			var room_code = data.get("room_code", "")
			print("Room created: ", match_id, " Code: ", room_code)
			room_created.emit(match_id, room_code if room_code else "")

		"join_by_code":
			var match_id = data.get("match_id", "")
			var error = data.get("error", "")
			if not match_id.is_empty():
				join_match(match_id)
			elif not error.is_empty():
				join_by_code_failed.emit(error)
			else:
				join_by_code_failed.emit("Unknown error")

		"list_rooms":
			var rooms = data.get("rooms", [])
			print("Available rooms: ", rooms)
			rooms_listed.emit(rooms)

		_:
			print("Unhandled request type: ", request_type, " Data: ", data)

func _handle_request_error(request_type: String, error: String) -> void:
	match request_type:
		"authenticate_device", "authenticate_email", "refresh_session":
			authentication_failed.emit(error)
		_:
			push_error("Request failed [%s]: %s" % [request_type, error])

func _call_rpc(function_name: String, payload: String) -> void:
	var url = _build_url("/v2/rpc/" + function_name + "?unwrap=true")
	var headers = _get_auth_headers()
	_make_request(function_name, url, HTTPClient.METHOD_POST, headers, payload)

func _send_socket_message(message: Dictionary) -> void:
	var json_str = JSON.stringify(message)
	_websocket.send_text(json_str)

func _handle_socket_message(message: String) -> void:
	var json = JSON.new()
	if json.parse(message) != OK:
		push_error("Failed to parse socket message: " + message)
		return

	var data = json.data

	# マッチ参加成功
	if data.has("match"):
		var match_data = data.match
		_current_match_id = match_data.get("match_id", "")

		# 自分のプレゼンスからsession_idを取得して保存
		var self_presence = match_data.get("self", {})
		if self_presence.has("session_id") and _session:
			_session.session_id = self_presence.get("session_id", "")
			print("[NakamaClient] Stored session_id from match join: ", _session.session_id)

		match_joined.emit(_current_match_id)

		# 初期プレゼンス
		var presences = match_data.get("presences", [])
		if presences.size() > 0:
			match_presence_joined.emit(presences)

	# マッチデータ受信
	elif data.has("match_data"):
		var match_data = data.match_data
		var op_code = int(match_data.get("op_code", "0"))
		var payload_base64 = match_data.get("data", "")
		var payload_str = Marshalls.base64_to_utf8(payload_base64)
		var payload = {}
		if not payload_str.is_empty():
			var payload_json = JSON.new()
			if payload_json.parse(payload_str) == OK:
				payload = payload_json.data
		var sender = match_data.get("presence", {}).get("user_id", "")
		match_data_received.emit(op_code, payload, sender)

	# プレゼンス更新
	elif data.has("match_presence_event"):
		print("[NakamaClient] match_presence_event received")
		var event = data.match_presence_event
		print("[NakamaClient] event data: ", event)
		var joins = event.get("joins", [])
		var leaves = event.get("leaves", [])
		print("[NakamaClient] joins: ", joins)
		print("[NakamaClient] leaves: ", leaves)
		if joins.size() > 0:
			print("[NakamaClient] Emitting match_presence_joined signal with: ", joins)
			match_presence_joined.emit(joins)
		if leaves.size() > 0:
			match_presence_left.emit(leaves)

	# マッチメイカーマッチ
	elif data.has("matchmaker_matched"):
		var matched = data.matchmaker_matched
		var match_id = matched.get("match_id", "")
		var token = matched.get("token", "")
		var users = matched.get("users", [])
		matchmaker_matched.emit(match_id, token, users)

func _parse_jwt(token: String) -> void:
	if not _session:
		return

	var parts = token.split(".")
	if parts.size() < 2:
		return

	# Base64デコード（パディング追加）
	var payload_base64 = parts[1]
	while payload_base64.length() % 4 != 0:
		payload_base64 += "="

	var payload_str = Marshalls.base64_to_utf8(payload_base64)
	var json = JSON.new()
	if json.parse(payload_str) == OK:
		var payload = json.data
		_session.user_id = payload.get("uid", "")
		_session.username = payload.get("usn", "")
		_session.session_id = payload.get("sid", "")
		_session.expires_at = payload.get("exp", 0)
		print("[NakamaClient] Parsed JWT - user_id: %s, session_id: %s" % [_session.user_id, _session.session_id])


# =====================================
# セッションクラス
# =====================================
class NakamaSession:
	var token: String = ""
	var refresh_token: String = ""
	var user_id: String = ""
	var username: String = ""
	var session_id: String = ""
	var created: bool = false
	var expires_at: int = 0

	func is_expired() -> bool:
		if expires_at == 0:
			return true
		return Time.get_unix_time_from_system() >= expires_at

	func is_refresh_expired() -> bool:
		# リフレッシュトークンの有効期限（デフォルト7日）
		return Time.get_unix_time_from_system() >= (expires_at + 604800)
