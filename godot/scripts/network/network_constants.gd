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
	## パス確定メッセージ
	PATH_CONFIRM = 1,
	## パス実行開始メッセージ
	PATH_EXECUTE = 2,
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
}

# ============================================
# 同期設定
# ============================================

## 同期レート（Hz）- 1秒あたりの同期回数
const SYNC_RATE_HZ: int = 30

## 同期間隔（秒）
const SYNC_INTERVAL: float = 1.0 / SYNC_RATE_HZ

## 位置精度（1cm単位 = 100）
## Vector3座標をintに変換する際の乗数
const POSITION_PRECISION: int = 100

## 回転精度（0.001ラジアン単位 = 1000）
const ROTATION_PRECISION: int = 1000

## パス座標の最大数
const MAX_PATH_POINTS: int = 256

## マーカーの最大数（各種類ごと）
const MAX_MARKERS_PER_TYPE: int = 32

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
	## ドアキック
	DOOR_KICK = 3,
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
}

# ============================================
# ユーティリティ関数
# ============================================

## MessageTypeを文字列に変換
static func message_type_to_string(msg_type: MessageType) -> String:
	match msg_type:
		MessageType.GAME_STATE_SYNC:
			return "GAME_STATE_SYNC"
		MessageType.PATH_CONFIRM:
			return "PATH_CONFIRM"
		MessageType.PATH_EXECUTE:
			return "PATH_EXECUTE"
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
		GameEventType.DOOR_KICK:
			return "DOOR_KICK"
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
		_:
			return "UNKNOWN"
