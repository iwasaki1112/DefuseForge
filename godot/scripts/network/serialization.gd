class_name NetworkSerializer
extends RefCounted
## シリアライズ/デシリアライズユーティリティ
##
## ネットワーク転送用のデータ圧縮・展開を行う
## パス座標の圧縮、ポイントデータのシリアライズなど

# ============================================
# Vector3配列の圧縮
# ============================================

## Vector3配列を圧縮してPackedByteArrayに変換
## 各座標はint16として格納し、precision倍で丸める
## フォーマット: [count:uint16][x:int16][y:int16][z:int16]...
static func compress_vector3_array(arr: Array[Vector3], precision: int = NetworkConstants.POSITION_PRECISION) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false

	# 要素数（uint16）
	buffer.put_u16(mini(arr.size(), 65535))

	# 各座標を圧縮
	for vec in arr:
		buffer.put_16(int(vec.x * precision))
		buffer.put_16(int(vec.y * precision))
		buffer.put_16(int(vec.z * precision))

	return buffer.data_array


## PackedByteArrayからVector3配列を復元
static func decompress_vector3_array(data: PackedByteArray, precision: int = NetworkConstants.POSITION_PRECISION) -> Array[Vector3]:
	var result: Array[Vector3] = []

	if data.size() < 2:
		return result

	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = data

	# 要素数を読み取り
	var count := buffer.get_u16()

	# 各座標を復元
	var inv_precision := 1.0 / precision
	for i in count:
		if buffer.get_position() + 6 > data.size():
			break
		var x := buffer.get_16() * inv_precision
		var y := buffer.get_16() * inv_precision
		var z := buffer.get_16() * inv_precision
		result.append(Vector3(x, y, z))

	return result


# ============================================
# パスメッセージのシリアライズ
# ============================================

## PathConfirmMessageを圧縮してPackedByteArrayに変換
static func serialize_path_message(msg: NetworkMessages.PathConfirmMessage) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false

	# ヘッダー
	buffer.put_32(msg.player_id)
	buffer.put_32(msg.character_id)
	buffer.put_64(msg.timestamp)

	# パス座標を圧縮
	var path_data := compress_vector3_array(msg.path)
	buffer.put_u16(path_data.size())
	buffer.put_data(path_data)

	# ポイントデータ（JSON形式で簡易シリアライズ）
	var points_dict := {
		"vision": msg.vision_points,
		"wait": msg.wait_points,
	}
	var points_json := JSON.stringify(points_dict)
	var points_bytes := points_json.to_utf8_buffer()
	buffer.put_u32(points_bytes.size())
	buffer.put_data(points_bytes)

	return buffer.data_array


## PackedByteArrayからPathConfirmMessageを復元
static func deserialize_path_message(data: PackedByteArray) -> NetworkMessages.PathConfirmMessage:
	var msg := NetworkMessages.PathConfirmMessage.new()

	if data.size() < 18:  # 最小ヘッダーサイズ
		return msg

	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = data

	# ヘッダー読み取り
	msg.player_id = buffer.get_32()
	msg.character_id = buffer.get_32()
	msg.timestamp = buffer.get_64()

	# パス座標を復元
	var path_size := buffer.get_u16()
	if path_size > 0:
		var path_data := buffer.get_data(path_size)[1] as PackedByteArray
		msg.path = decompress_vector3_array(path_data)

	# ポイントデータを復元
	if buffer.get_position() + 4 <= data.size():
		var points_size := buffer.get_u32()
		if points_size > 0 and buffer.get_position() + points_size <= data.size():
			var points_bytes := buffer.get_data(points_size)[1] as PackedByteArray
			var points_json := points_bytes.get_string_from_utf8()
			var json := JSON.new()
			if json.parse(points_json) == OK:
				var points_dict: Dictionary = json.data
				msg.vision_points.assign(points_dict.get("vision", []))
				msg.wait_points.assign(points_dict.get("wait", []))

	return msg


# ============================================
# ゲーム状態のシリアライズ
# ============================================

## GameStateSnapshotを圧縮してPackedByteArrayに変換
static func serialize_game_state(snapshot: SyncState.GameStateSnapshot) -> PackedByteArray:
	# 完全なスナップショットはJSON形式で簡易シリアライズ
	var json := JSON.stringify(snapshot.to_dict())
	return json.to_utf8_buffer()


## PackedByteArrayからGameStateSnapshotを復元
static func deserialize_game_state(data: PackedByteArray) -> SyncState.GameStateSnapshot:
	var snapshot := SyncState.GameStateSnapshot.new()

	var json_str := data.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_str) == OK and json.data is Dictionary:
		snapshot.from_dict(json.data)

	return snapshot


# ============================================
# キャラクター状態のバイナリシリアライズ（高効率版）
# ============================================

## CharacterStateMessageをバイナリ形式でシリアライズ
## フォーマット: 36 bytes
## [char_id:u32][pos_x:i16][pos_y:i16][pos_z:i16][rot:i16]
## [vel_x:i16][vel_y:i16][vel_z:i16][hp:u8][flags:u8][anim_state:16 bytes]
static func serialize_character_state_binary(state: NetworkMessages.CharacterStateMessage) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false

	# キャラクターID (4 bytes)
	buf.put_u32(state.character_id)

	# 位置 (6 bytes) - cm単位で量子化
	buf.put_16(int(clampf(state.position.x * NetworkConstants.POSITION_PRECISION, -32768, 32767)))
	buf.put_16(int(clampf(state.position.y * NetworkConstants.POSITION_PRECISION, -32768, 32767)))
	buf.put_16(int(clampf(state.position.z * NetworkConstants.POSITION_PRECISION, -32768, 32767)))

	# 回転 (2 bytes) - mrad単位で量子化
	buf.put_16(int(clampf(state.rotation * NetworkConstants.ROTATION_PRECISION, -32768, 32767)))

	# 速度 (6 bytes) - cm/s単位で量子化
	buf.put_16(int(clampf(state.velocity.x * NetworkConstants.POSITION_PRECISION, -32768, 32767)))
	buf.put_16(int(clampf(state.velocity.y * NetworkConstants.POSITION_PRECISION, -32768, 32767)))
	buf.put_16(int(clampf(state.velocity.z * NetworkConstants.POSITION_PRECISION, -32768, 32767)))

	# HP (1 byte) - 0-255
	buf.put_u8(clampi(state.current_health, 0, 255))

	# フラグ (1 byte) - ビットパック
	var flags: int = 0
	if state.is_alive:
		flags |= 0x01
	if state.is_crouching:
		flags |= 0x02
	buf.put_u8(flags)

	# アニメーション状態 (16 bytes) - 固定長文字列
	var anim_bytes := state.animation_state.to_utf8_buffer()
	anim_bytes.resize(16)  # 16バイトにパディング/切り詰め
	buf.put_data(anim_bytes)

	return buf.data_array


## バイナリ形式のCharacterStateMessageをデシリアライズ
static func deserialize_character_state_binary(data: PackedByteArray) -> NetworkMessages.CharacterStateMessage:
	var state := NetworkMessages.CharacterStateMessage.new()

	if data.size() < 36:  # 20 + 16 bytes for animation_state
		return state

	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = data

	var inv_pos_precision := 1.0 / NetworkConstants.POSITION_PRECISION
	var inv_rot_precision := 1.0 / NetworkConstants.ROTATION_PRECISION

	# キャラクターID
	state.character_id = buf.get_u32()

	# 位置
	state.position = Vector3(
		buf.get_16() * inv_pos_precision,
		buf.get_16() * inv_pos_precision,
		buf.get_16() * inv_pos_precision
	)

	# 回転
	state.rotation = buf.get_16() * inv_rot_precision

	# 速度
	state.velocity = Vector3(
		buf.get_16() * inv_pos_precision,
		buf.get_16() * inv_pos_precision,
		buf.get_16() * inv_pos_precision
	)

	# HP
	state.current_health = buf.get_u8()

	# フラグ
	var flags := buf.get_u8()
	state.is_alive = (flags & 0x01) != 0
	state.is_crouching = (flags & 0x02) != 0

	# アニメーション状態 (16 bytes)
	var anim_data := buf.get_data(16)[1] as PackedByteArray
	state.animation_state = anim_data.get_string_from_utf8().strip_edges()

	return state


## 複数キャラクター状態をバイナリでシリアライズ
## フォーマット: [count:u8][char_states...]
static func serialize_character_states_binary(states: Array[NetworkMessages.CharacterStateMessage]) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false

	# キャラクター数 (最大255)
	buf.put_u8(mini(states.size(), 255))

	# 各キャラクター状態
	for state in states:
		var state_data := serialize_character_state_binary(state)
		buf.put_data(state_data)

	return buf.data_array


## バイナリ形式の複数キャラクター状態をデシリアライズ
static func deserialize_character_states_binary(data: PackedByteArray) -> Array[NetworkMessages.CharacterStateMessage]:
	var result: Array[NetworkMessages.CharacterStateMessage] = []

	if data.size() < 1:
		return result

	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = data

	var count := buf.get_u8()
	const CHAR_STATE_SIZE := 36  # 20 + 16 bytes for animation_state

	for i in count:
		if buf.get_position() + CHAR_STATE_SIZE > data.size():
			break
		var state_data := buf.get_data(CHAR_STATE_SIZE)[1] as PackedByteArray
		result.append(deserialize_character_state_binary(state_data))

	return result


# ============================================
# 汎用シリアライズ
# ============================================

## Dictionaryを圧縮してPackedByteArrayに変換
static func serialize_dict(dict: Dictionary) -> PackedByteArray:
	var json := JSON.stringify(dict)
	return json.to_utf8_buffer()


## PackedByteArrayからDictionaryを復元
static func deserialize_dict(data: PackedByteArray) -> Dictionary:
	var json_str := data.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_str) == OK and json.data is Dictionary:
		return json.data
	return {}


## ネットワークメッセージをラップして送信用フォーマットに変換
## フォーマット: [msg_type:uint8][payload_size:uint32][payload:bytes]
static func wrap_message(msg_type: NetworkConstants.MessageType, payload: PackedByteArray) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false

	buffer.put_u8(msg_type)
	buffer.put_u32(payload.size())
	buffer.put_data(payload)

	return buffer.data_array


## ラップされたメッセージをアンラップ
## @return [msg_type: int, payload: PackedByteArray] または空配列（エラー時）
static func unwrap_message(data: PackedByteArray) -> Array:
	if data.size() < 5:
		return []

	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = data

	var msg_type := buffer.get_u8()
	var payload_size := buffer.get_u32()

	if buffer.get_position() + payload_size > data.size():
		return []

	var payload := buffer.get_data(payload_size)[1] as PackedByteArray
	return [msg_type, payload]


# ============================================
# 差分圧縮ユーティリティ（将来用）
# ============================================

## 2つのVector3配列の差分を計算
## @return 差分データ（変更があったインデックスと値のペア配列）
static func compute_path_delta(old_path: Array[Vector3], new_path: Array[Vector3]) -> Dictionary:
	var changes: Array = []

	# 長さの変更
	var old_len := old_path.size()
	var new_len := new_path.size()

	# 変更されたポイントを検出
	var min_len := mini(old_len, new_len)
	for i in min_len:
		if not old_path[i].is_equal_approx(new_path[i]):
			changes.append({"i": i, "v": [new_path[i].x, new_path[i].y, new_path[i].z]})

	# 追加されたポイント
	for i in range(min_len, new_len):
		changes.append({"i": i, "v": [new_path[i].x, new_path[i].y, new_path[i].z]})

	return {
		"old_len": old_len,
		"new_len": new_len,
		"changes": changes,
	}


## 差分データを適用してパスを更新
static func apply_path_delta(base_path: Array[Vector3], delta: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var new_len: int = delta.get("new_len", 0)
	var changes: Array = delta.get("changes", [])

	# 新しい長さで初期化（元のデータをコピー）
	result.resize(new_len)
	for i in mini(base_path.size(), new_len):
		result[i] = base_path[i]

	# 差分を適用
	for change in changes:
		var idx: int = change.get("i", 0)
		var val: Array = change.get("v", [0, 0, 0])
		if idx < new_len and val.size() >= 3:
			result[idx] = Vector3(val[0], val[1], val[2])

	return result


# ============================================
# バリデーション
# ============================================

## パスメッセージの妥当性を検証
static func validate_path_message(msg: NetworkMessages.PathConfirmMessage) -> bool:
	# パスが空でないこと
	if msg.path.is_empty():
		return false

	# パス座標数が上限以内
	if msg.path.size() > NetworkConstants.MAX_PATH_POINTS:
		return false

	# ポイント数が上限以内
	if msg.vision_points.size() > NetworkConstants.MAX_POINTS_PER_TYPE:
		return false
	if msg.wait_points.size() > NetworkConstants.MAX_POINTS_PER_TYPE:
		return false

	return true
