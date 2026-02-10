class_name SyncState
extends RefCounted
## 同期可能な状態クラス群
##
## ゲーム状態のスナップショットを表現し、ネットワーク同期に使用する

# ============================================
# GameStateSnapshot - ゲーム全体のスナップショット
# ============================================

## ゲーム状態全体のスナップショット
## サーバーからクライアントへの完全同期、または差分同期のベースとして使用
class GameStateSnapshot extends RefCounted:
	## スナップショット生成時のタイムスタンプ（msec）
	var timestamp: int = 0

	## ゲームが開始しているか
	var is_game_started: bool = false

	## ラウンド状態
	var round_state: NetworkMessages.RoundStateMessage = null

	## 全キャラクターの状態
	var characters: Array[NetworkMessages.CharacterStateMessage] = []

	## 現在のラウンド番号
	var round_number: int = 1


	## スナップショットを初期化
	func _init() -> void:
		timestamp = Time.get_ticks_msec()
		round_state = NetworkMessages.RoundStateMessage.new()


	## Dictionaryに変換
	func to_dict() -> Dictionary:
		var chars_array: Array = []
		for char_state in characters:
			chars_array.append(char_state.to_dict())

		return {
			"timestamp": timestamp,
			"is_game_started": is_game_started,
			"round_state": round_state.to_dict() if round_state else {},
			"characters": chars_array,
			"round_number": round_number,
		}


	## Dictionaryから復元
	func from_dict(data: Dictionary) -> void:
		timestamp = data.get("timestamp", 0)
		is_game_started = data.get("is_game_started", false)
		round_number = data.get("round_number", 1)

		# ラウンド状態
		if data.has("round_state"):
			round_state = NetworkMessages.RoundStateMessage.new()
			round_state.from_dict(data.round_state)

		# キャラクター状態
		characters.clear()
		var chars_data = data.get("characters", [])
		for char_dict in chars_data:
			var char_state := NetworkMessages.CharacterStateMessage.new()
			char_state.from_dict(char_dict)
			characters.append(char_state)



# ============================================
# PlayerStateData - プレイヤー固有状態
# ============================================

## プレイヤー固有の状態データ
## ロビーからゲーム中まで一貫して管理される
class PlayerStateData extends RefCounted:
	## ネットワークpeer_id
	var peer_id: int = 0

	## プレイヤー名
	var player_name: String = ""

	## 所属チーム（GameCharacter.Team相当）
	var team: int = 0

	## 準備完了フラグ
	var is_ready: bool = false

	## 接続済みフラグ
	var connection_active: bool = true

	## 最終アクティブ時刻（msec）
	var last_active_time: int = 0

	## 勝利ラウンド数
	var wins: int = 0

	## 敗北ラウンド数
	var losses: int = 0

	## 連敗数（敗北報酬計算用）
	var loss_streak: int = 0


	## 初期化
	func _init(p_peer_id: int = 0, p_name: String = "") -> void:
		peer_id = p_peer_id
		player_name = p_name
		last_active_time = Time.get_ticks_msec()


	## Dictionaryに変換
	func to_dict() -> Dictionary:
		return {
			"peer_id": peer_id,
			"player_name": player_name,
			"team": team,
			"is_ready": is_ready,
			"connection_active": connection_active,
			"last_active_time": last_active_time,
			"wins": wins,
			"losses": losses,
			"loss_streak": loss_streak,
		}


	## Dictionaryから復元
	func from_dict(data: Dictionary) -> void:
		peer_id = data.get("peer_id", 0)
		player_name = data.get("player_name", "")
		team = data.get("team", 0)
		is_ready = data.get("is_ready", false)
		connection_active = data.get("connection_active", true)
		last_active_time = data.get("last_active_time", 0)
		wins = data.get("wins", 0)
		losses = data.get("losses", 0)
		loss_streak = data.get("loss_streak", 0)


	## アクティブ時刻を更新
	func update_active_time() -> void:
		last_active_time = Time.get_ticks_msec()


	## 準備完了状態をトグル
	func toggle_ready() -> void:
		is_ready = not is_ready
		update_active_time()


	## ラウンド勝利時の処理
	func on_round_win() -> void:
		wins += 1
		loss_streak = 0


	## ラウンド敗北時の処理
	func on_round_loss() -> void:
		losses += 1
		loss_streak += 1


# ============================================
# CharacterSnapshot - キャラクター状態のスナップショット
# ============================================

## キャラクター状態の完全スナップショット
## 補間処理や予測に必要な情報を含む
class CharacterSnapshot extends RefCounted:
	## キャラクターID
	var character_id: int = 0

	## 所属プレイヤーID
	var owner_peer_id: int = 0

	## ワールド座標
	var position: Vector3 = Vector3.ZERO

	## Y軸回転（ラジアン）
	var rotation: float = 0.0

	## 向いている方向ベクトル
	var facing_direction: Vector3 = Vector3.FORWARD

	## 速度ベクトル
	var velocity: Vector3 = Vector3.ZERO

	## 現在HP
	var current_health: float = 100.0

	## 最大HP
	var max_health: float = 100.0

	## 生存フラグ
	var is_alive: bool = true

	## チーム（GameCharacter.Team相当）
	var team: int = 0

	## 装備中の武器ID
	var weapon_id: String = ""

	## アニメーション状態
	var animation_state: String = ""

	## タイムスタンプ
	var timestamp: int = 0


	## CharacterStateMessageから変換
	static func from_message(msg: NetworkMessages.CharacterStateMessage) -> CharacterSnapshot:
		var snapshot := CharacterSnapshot.new()
		snapshot.character_id = msg.character_id
		snapshot.position = msg.position
		snapshot.rotation = msg.rotation
		snapshot.velocity = msg.velocity
		snapshot.current_health = msg.current_health
		snapshot.is_alive = msg.is_alive
		snapshot.animation_state = msg.animation_state
		snapshot.timestamp = msg.timestamp
		return snapshot


	## CharacterStateMessageに変換
	func to_message() -> NetworkMessages.CharacterStateMessage:
		var msg := NetworkMessages.CharacterStateMessage.new()
		msg.character_id = character_id
		msg.position = position
		msg.rotation = rotation
		msg.velocity = velocity
		msg.current_health = int(current_health)
		msg.is_alive = is_alive
		msg.animation_state = animation_state
		msg.timestamp = timestamp
		return msg


	## Dictionaryに変換
	func to_dict() -> Dictionary:
		return {
			"character_id": character_id,
			"owner_peer_id": owner_peer_id,
			"position": [position.x, position.y, position.z],
			"rotation": rotation,
			"facing_direction": [facing_direction.x, facing_direction.y, facing_direction.z],
			"velocity": [velocity.x, velocity.y, velocity.z],
			"current_health": current_health,
			"max_health": max_health,
			"is_alive": is_alive,
			"team": team,
			"weapon_id": weapon_id,
			"animation_state": animation_state,
			"timestamp": timestamp,
		}


	## Dictionaryから復元
	func from_dict(data: Dictionary) -> void:
		character_id = data.get("character_id", 0)
		owner_peer_id = data.get("owner_peer_id", 0)
		var pos = data.get("position", [0, 0, 0])
		if pos is Array and pos.size() >= 3:
			position = Vector3(pos[0], pos[1], pos[2])
		rotation = data.get("rotation", 0.0)
		var facing = data.get("facing_direction", [0, 0, 1])
		if facing is Array and facing.size() >= 3:
			facing_direction = Vector3(facing[0], facing[1], facing[2])
		var vel = data.get("velocity", [0, 0, 0])
		if vel is Array and vel.size() >= 3:
			velocity = Vector3(vel[0], vel[1], vel[2])
		current_health = data.get("current_health", 100.0)
		max_health = data.get("max_health", 100.0)
		is_alive = data.get("is_alive", true)
		team = data.get("team", 0)
		weapon_id = data.get("weapon_id", "")
		animation_state = data.get("animation_state", "")
		timestamp = data.get("timestamp", 0)


	## 2つのスナップショット間を補間
	static func interpolate(from_snap: CharacterSnapshot, to_snap: CharacterSnapshot, t: float) -> CharacterSnapshot:
		var result := CharacterSnapshot.new()
		result.character_id = to_snap.character_id
		result.owner_peer_id = to_snap.owner_peer_id
		result.position = from_snap.position.lerp(to_snap.position, t)
		result.rotation = lerp_angle(from_snap.rotation, to_snap.rotation, t)
		result.facing_direction = from_snap.facing_direction.lerp(to_snap.facing_direction, t).normalized()
		result.velocity = from_snap.velocity.lerp(to_snap.velocity, t)
		# 離散値はtoの値を使用
		result.current_health = to_snap.current_health
		result.max_health = to_snap.max_health
		result.is_alive = to_snap.is_alive
		result.team = to_snap.team
		result.weapon_id = to_snap.weapon_id
		result.animation_state = to_snap.animation_state
		result.timestamp = int(lerp(float(from_snap.timestamp), float(to_snap.timestamp), t))
		return result
