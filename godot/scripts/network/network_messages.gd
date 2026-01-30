class_name NetworkMessages
extends RefCounted
## ネットワーク同期用メッセージ型定義
##
## パス確定、ラウンド状態、キャラクター状態、ゲームイベントなど
## ネットワーク越しにやり取りするデータ構造を定義

# ============================================
# PathConfirmMessage - パス確定データ
# ============================================

## パス確定時に送信するメッセージ
## キャラクターの移動パスと全ポイント情報を含む
class PathConfirmMessage extends RefCounted:
	## 送信元プレイヤーID（peer_id）
	var player_id: int = 0

	## 対象キャラクターID
	var character_id: int = 0

	## パス座標配列
	var path: Array[Vector3] = []

	## 視線ポイントデータ配列
	## 各要素: { path_ratio, target_point/direction, has_target }
	var vision_points: Array[Dictionary] = []

	## Waitポイントデータ配列
	## 各要素: { path_ratio, anchor, wait_duration }
	var wait_points: Array[Dictionary] = []

	## メッセージ生成タイムスタンプ（msec）
	var timestamp: int = 0


	## Dictionaryに変換（シリアライズ用）
	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"character_id": character_id,
			"path": _path_to_array(),
			"vision_points": vision_points,
			"wait_points": wait_points,
			"timestamp": timestamp,
		}


	## Dictionaryから復元（デシリアライズ用）
	func from_dict(data: Dictionary) -> void:
		player_id = data.get("player_id", 0)
		character_id = data.get("character_id", 0)
		_array_to_path(data.get("path", []))
		vision_points.assign(data.get("vision_points", []))
		wait_points.assign(data.get("wait_points", []))
		timestamp = data.get("timestamp", 0)


	## パスをArray[Array]形式に変換（JSON互換）
	func _path_to_array() -> Array:
		var result: Array = []
		for point in path:
			result.append([point.x, point.y, point.z])
		return result


	## Array形式からパスを復元
	func _array_to_path(arr: Array) -> void:
		path.clear()
		for item in arr:
			if item is Array and item.size() >= 3:
				path.append(Vector3(item[0], item[1], item[2]))


# ============================================
# RoundStateMessage - ラウンド状態
# ============================================

## ラウンド状態を同期するメッセージ
class RoundStateMessage extends RefCounted:
	## ラウンドフェーズ（RoundManager.RoundPhase相当）
	## 0: NONE, 1: ACTIVE, 2: ENDED
	var phase: int = 0

	## 残り時間（秒）
	var remaining_time: float = 0.0

	## CT生存者数
	var ct_alive_count: int = 0

	## T生存者数
	var t_alive_count: int = 0

	## 勝利チーム（GameCharacter.Team相当）
	## 0: NONE, 1: COUNTER_TERRORIST, 2: TERRORIST
	var winner_team: int = 0

	## 終了理由（RoundManager.EndReason相当）
	## 0: TIME_UP, 1: CT_ELIMINATED, 2: T_ELIMINATED
	var end_reason: int = 0

	## タイムスタンプ
	var timestamp: int = 0


	func to_dict() -> Dictionary:
		return {
			"phase": phase,
			"remaining_time": remaining_time,
			"ct_alive_count": ct_alive_count,
			"t_alive_count": t_alive_count,
			"winner_team": winner_team,
			"end_reason": end_reason,
			"timestamp": timestamp,
		}


	func from_dict(data: Dictionary) -> void:
		phase = data.get("phase", 0)
		remaining_time = data.get("remaining_time", 0.0)
		ct_alive_count = data.get("ct_alive_count", 0)
		t_alive_count = data.get("t_alive_count", 0)
		winner_team = data.get("winner_team", 0)
		end_reason = data.get("end_reason", 0)
		timestamp = data.get("timestamp", 0)


# ============================================
# CharacterStateMessage - キャラクター状態
# ============================================

## キャラクター状態を同期するメッセージ
class CharacterStateMessage extends RefCounted:
	## キャラクターID
	var character_id: int = 0

	## ワールド座標
	var position: Vector3 = Vector3.ZERO

	## Y軸回転（ラジアン）
	var rotation: float = 0.0

	## 現在のHP
	var current_health: int = 100

	## 生存フラグ
	var is_alive: bool = true

	## 現在のアニメーション状態
	var animation_state: String = ""

	## 移動速度（m/s）
	var velocity: Vector3 = Vector3.ZERO

	## しゃがみ状態
	var is_crouching: bool = false

	## タイムスタンプ
	var timestamp: int = 0


	func to_dict() -> Dictionary:
		return {
			"character_id": character_id,
			"position": [position.x, position.y, position.z],
			"rotation": rotation,
			"current_health": current_health,
			"is_alive": is_alive,
			"animation_state": animation_state,
			"velocity": [velocity.x, velocity.y, velocity.z],
			"is_crouching": is_crouching,
			"timestamp": timestamp,
		}


	func from_dict(data: Dictionary) -> void:
		character_id = data.get("character_id", 0)
		var pos = data.get("position", [0, 0, 0])
		if pos is Array and pos.size() >= 3:
			position = Vector3(pos[0], pos[1], pos[2])
		rotation = data.get("rotation", 0.0)
		current_health = data.get("current_health", 100)
		is_alive = data.get("is_alive", true)
		animation_state = data.get("animation_state", "")
		var vel = data.get("velocity", [0, 0, 0])
		if vel is Array and vel.size() >= 3:
			velocity = Vector3(vel[0], vel[1], vel[2])
		is_crouching = data.get("is_crouching", false)
		timestamp = data.get("timestamp", 0)


# ============================================
# GameEventMessage - ゲームイベント
# ============================================

## ゲーム内イベントを通知するメッセージ
class GameEventMessage extends RefCounted:
	## イベントタイプ（NetworkConstants.GameEventType）
	var event_type: int = 0

	## イベント発生源のID（キャラクターID等）
	var source_id: int = 0

	## イベント対象のID（ダメージを受けたキャラクター等）
	var target_id: int = 0

	## イベント固有データ
	## DAMAGE: { damage: float, is_headshot: bool }
	## DEATH: { killer_id: int, is_headshot: bool }
	## GRENADE_THROW: { target_pos: Array, grenade_type: int }
	## DOOR_KICK: { door_id: int }
	## WEAPON_FIRE: { weapon_id: String }
	var data: Dictionary = {}

	## タイムスタンプ
	var timestamp: int = 0


	func to_dict() -> Dictionary:
		return {
			"event_type": event_type,
			"source_id": source_id,
			"target_id": target_id,
			"data": data,
			"timestamp": timestamp,
		}


	func from_dict(dict_data: Dictionary) -> void:
		event_type = dict_data.get("event_type", 0)
		source_id = dict_data.get("source_id", 0)
		target_id = dict_data.get("target_id", 0)
		data = dict_data.get("data", {})
		timestamp = dict_data.get("timestamp", 0)


# ============================================
# PlayerReadyMessage - プレイヤー準備完了
# ============================================

## プレイヤーの準備完了状態を通知するメッセージ
class PlayerReadyMessage extends RefCounted:
	## プレイヤーID
	var player_id: int = 0

	## 準備完了フラグ
	var is_ready: bool = false

	## タイムスタンプ
	var timestamp: int = 0


	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"is_ready": is_ready,
			"timestamp": timestamp,
		}


	func from_dict(data: Dictionary) -> void:
		player_id = data.get("player_id", 0)
		is_ready = data.get("is_ready", false)
		timestamp = data.get("timestamp", 0)


# ============================================
# ファクトリメソッド
# ============================================

## 現在時刻のタイムスタンプを取得
static func get_timestamp() -> int:
	return Time.get_ticks_msec()


## PathConfirmMessageを作成
static func create_path_confirm(player_id: int, character_id: int, path: Array[Vector3]) -> PathConfirmMessage:
	var msg := PathConfirmMessage.new()
	msg.player_id = player_id
	msg.character_id = character_id
	msg.path = path.duplicate()
	msg.timestamp = get_timestamp()
	return msg


## RoundStateMessageを作成
static func create_round_state(phase: int, remaining_time: float, ct_count: int, t_count: int) -> RoundStateMessage:
	var msg := RoundStateMessage.new()
	msg.phase = phase
	msg.remaining_time = remaining_time
	msg.ct_alive_count = ct_count
	msg.t_alive_count = t_count
	msg.timestamp = get_timestamp()
	return msg


## CharacterStateMessageを作成
static func create_character_state(char_id: int, pos: Vector3, rot: float, health: int, alive: bool) -> CharacterStateMessage:
	var msg := CharacterStateMessage.new()
	msg.character_id = char_id
	msg.position = pos
	msg.rotation = rot
	msg.current_health = health
	msg.is_alive = alive
	msg.timestamp = get_timestamp()
	return msg


## GameEventMessageを作成
static func create_game_event(event_type: int, source_id: int, target_id: int, data: Dictionary = {}) -> GameEventMessage:
	var msg := GameEventMessage.new()
	msg.event_type = event_type
	msg.source_id = source_id
	msg.target_id = target_id
	msg.data = data.duplicate()
	msg.timestamp = get_timestamp()
	return msg
