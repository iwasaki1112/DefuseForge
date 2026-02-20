class_name NetworkConstants
extends RefCounted
## ネットワーク関連の定数定義
##
## メッセージタイプID、同期設定、タイムアウト値などを定義

# ============================================
# メッセージタイプ
# ============================================

## ネットワークメッセージの種別
enum MessageType {
	## ゲーム状態の同期
	GAME_STATE_SYNC = 0,
	## Historical: Values 1-2 were PATH_CONFIRM/PATH_EXECUTE (removed in TPS migration)
	## キャラクター状態更新
	CHARACTER_UPDATE = 3,
	## ラウンド状態
	ROUND_STATE = 4,
	## ゲームイベント（ダメージ、死亡等）
	GAME_EVENT = 5,
	## プレイヤー準備完了
	PLAYER_READY = 6,
	## チーム変更
	TEAM_CHANGE = 7,
	## プレイヤー入力
	PLAYER_INPUT = 8,
	## 選択状態更新
	SELECTION_UPDATE = 9,
	## キャラクター状態更新（バイナリ形式）
	CHARACTER_UPDATE_BINARY = 10,
	## 複数キャラクター状態一括更新（バイナリ形式）
	CHARACTER_BATCH_UPDATE_BINARY = 11,
}

# ============================================
# 同期設定
# ============================================

## シミュレーションTick（Hz）- ゲームロジック更新頻度
const SIMULATION_TICK_HZ: int = 60

## ネットワーク送信Tick（Hz）- ネットワーク更新頻度
const NETWORK_SEND_HZ: int = 20

## 送信間隔（シミュレーションTickごと）
@warning_ignore("integer_division")
const SEND_EVERY_N_TICKS: int = SIMULATION_TICK_HZ / NETWORK_SEND_HZ  # = 3

## 同期レート（Hz）- 後方互換用（NETWORK_SEND_HZを使用推奨）
const SYNC_RATE_HZ: int = NETWORK_SEND_HZ

## 同期間隔（秒）
const SYNC_INTERVAL: float = 1.0 / NETWORK_SEND_HZ

## 補間バッファ遅延（秒）- リモートキャラクターの描画遅延
## 高いほど滑らかだがラグが増える（推奨: 80-150ms）
const INTERPOLATION_DELAY: float = 0.12

## スナップショットバッファサイズ（約1秒分のデータを保持）
const SNAPSHOT_BUFFER_SIZE: int = 30

## 外挿の最大時間（秒）- パケット途切れ時の予測限界
const MAX_EXTRAPOLATION_TIME: float = 0.15

## 静止時の送信間引き閾値（速度がこれ以下なら送信頻度を下げる）
const IDLE_VELOCITY_THRESHOLD: float = 0.1

## 静止時の送信間隔倍率（通常の何倍の間隔で送信するか）
const IDLE_SEND_MULTIPLIER: int = 3

## 位置精度（1cm単位 = 100）
## Vector3座標をintに変換する際の乗数
const POSITION_PRECISION: int = 100

## 回転精度（0.001ラジアン単位 = 1000）
const ROTATION_PRECISION: int = 1000


# ============================================
# リレーサーバー設定
# ============================================

## リレーサーバーURL（本番環境）
const RELAY_SERVER_URL: String = "wss://rescueforge-relay-344342786567.asia-northeast1.run.app/ws"

## ローカル開発用URL
const RELAY_SERVER_URL_LOCAL: String = "ws://localhost:8080/ws"

## 開発モードフラグ（trueならローカルサーバーに接続）
const USE_LOCAL_RELAY: bool = false

# ============================================
# タイムアウト設定
# ============================================

## 接続タイムアウト（ミリ秒）
const CONNECTION_TIMEOUT_MS: int = 10000

## ハートビート間隔（秒）
const HEARTBEAT_INTERVAL: float = 1.0

## 切断判定までの無応答時間（秒）
const DISCONNECT_TIMEOUT: float = 5.0

## 再接続試行回数
const RECONNECT_ATTEMPTS: int = 3

## 再接続待機時間（秒）
const RECONNECT_DELAY: float = 2.0

# ============================================
# チャンネル設定
# ============================================

## 信頼性のあるチャンネル（順序保証・再送あり）
const CHANNEL_RELIABLE: int = 0

## 高速チャンネル（順序保証なし・再送なし）
const CHANNEL_UNRELIABLE: int = 1

## 順序付きチャンネル（順序保証・再送なし）
const CHANNEL_ORDERED: int = 2

# ============================================
# ゲームイベントタイプ
# ============================================

## ゲーム内イベントの種別
enum GameEventType {
	## ダメージ発生
	DAMAGE = 0,
	## キャラクター死亡
	DEATH = 1,
	## グレネード投擲
	GRENADE_THROW = 2,
	## 武器発射
	WEAPON_FIRE = 4,
	## リロード
	RELOAD = 5,
	## スモークグレネード投擲
	SMOKE_GRENADE_THROW = 6,
	## グレネード爆発（位置同期用）
	GRENADE_EXPLODE = 7,
	## スモーク展開（位置同期用）
	SMOKE_DEPLOY = 8,
	## アニメーションイベント（即時同期）
	ANIMATION_EVENT = 9,
	## ドア開け（静かに開く）
	DOOR_OPEN = 10,
	## ドアキック（蹴り破る）
	DOOR_KICK = 11,
}


## アニメーションイベントタイプ（即時同期用）
enum AnimationEventType {
	## 発砲アニメーション
	FIRE = 0,
	## リロードアニメーション
	RELOAD = 1,
	## ヒットリアクション
	HIT_REACTION = 2,
	## 死亡アニメーション
	DEATH = 3,
	## グレネード投擲アニメーション
	GRENADE_THROW = 4,
}

# ============================================
# ユーティリティ関数
# ============================================

## MessageTypeを文字列に変換
static func message_type_to_string(msg_type: MessageType) -> String:
	match msg_type:
		MessageType.GAME_STATE_SYNC:
			return "GAME_STATE_SYNC"
		MessageType.CHARACTER_UPDATE:
			return "CHARACTER_UPDATE"
		MessageType.ROUND_STATE:
			return "ROUND_STATE"
		MessageType.GAME_EVENT:
			return "GAME_EVENT"
		MessageType.PLAYER_READY:
			return "PLAYER_READY"
		MessageType.TEAM_CHANGE:
			return "TEAM_CHANGE"
		MessageType.PLAYER_INPUT:
			return "PLAYER_INPUT"
		MessageType.SELECTION_UPDATE:
			return "SELECTION_UPDATE"
		_:
			return "UNKNOWN"


## GameEventTypeを文字列に変換
static func event_type_to_string(event_type: GameEventType) -> String:
	match event_type:
		GameEventType.DAMAGE:
			return "DAMAGE"
		GameEventType.DEATH:
			return "DEATH"
		GameEventType.GRENADE_THROW:
			return "GRENADE_THROW"
		GameEventType.WEAPON_FIRE:
			return "WEAPON_FIRE"
		GameEventType.RELOAD:
			return "RELOAD"
		GameEventType.SMOKE_GRENADE_THROW:
			return "SMOKE_GRENADE_THROW"
		GameEventType.GRENADE_EXPLODE:
			return "GRENADE_EXPLODE"
		GameEventType.SMOKE_DEPLOY:
			return "SMOKE_DEPLOY"
		GameEventType.ANIMATION_EVENT:
			return "ANIMATION_EVENT"
		GameEventType.DOOR_OPEN:
			return "DOOR_OPEN"
		GameEventType.DOOR_KICK:
			return "DOOR_KICK"
		_:
			return "UNKNOWN"
