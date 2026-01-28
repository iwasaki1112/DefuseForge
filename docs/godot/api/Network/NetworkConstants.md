# NetworkConstants

ネットワーク関連の定数定義クラス。

## 概要

メッセージタイプID、同期設定、タイムアウト値などネットワーク同期に必要な定数を一元管理する。

## ファイル

`godot/scripts/network/network_constants.gd`

## メッセージタイプ

```gdscript
enum MessageType {
    GAME_STATE_SYNC = 0,           # ゲーム状態の同期
    PATH_CONFIRM = 1,              # パス確定メッセージ
    PATH_EXECUTE = 2,              # パス実行開始メッセージ
    CHARACTER_UPDATE = 3,          # キャラクター状態更新
    ROUND_STATE = 4,               # ラウンド状態
    GAME_EVENT = 5,                # ゲームイベント（ダメージ、死亡等）
    PLAYER_READY = 6,              # プレイヤー準備完了
    TEAM_CHANGE = 7,               # チーム変更
    PLAYER_INPUT = 8,              # プレイヤー入力
    SELECTION_UPDATE = 9,          # 選択状態更新
    CHARACTER_UPDATE_BINARY = 10,  # キャラクター状態更新（バイナリ形式）
    CHARACTER_BATCH_UPDATE_BINARY = 11,  # 複数キャラクター一括更新（バイナリ形式）
}
```

## ゲームイベントタイプ

```gdscript
enum GameEventType {
    DAMAGE = 0,              # ダメージ発生
    DEATH = 1,               # キャラクター死亡
    GRENADE_THROW = 2,       # グレネード投擲
    DOOR_KICK = 3,           # ドアキック
    WEAPON_FIRE = 4,         # 武器発射
    RELOAD = 5,              # リロード
    SMOKE_GRENADE_THROW = 6, # スモークグレネード投擲
    GRENADE_EXPLODE = 7,     # グレネード爆発（位置同期用）
    SMOKE_DEPLOY = 8,        # スモーク展開（位置同期用）
    ANIMATION_EVENT = 9,     # アニメーションイベント（即時同期）
}
```

## アニメーションイベントタイプ

```gdscript
enum AnimationEventType {
    FIRE = 0,          # 発砲アニメーション
    RELOAD = 1,        # リロードアニメーション
    HIT_REACTION = 2,  # ヒットリアクション
    DEATH = 3,         # 死亡アニメーション
    GRENADE_THROW = 4, # グレネード投擲アニメーション
    CROUCH_START = 5,  # しゃがみ開始
    CROUCH_END = 6,    # しゃがみ終了
}
```

## Tick設定

| 定数 | 値 | 説明 |
|------|-----|------|
| `SIMULATION_TICK_HZ` | 60 | シミュレーションTick（Hz）- ゲームロジック更新頻度 |
| `NETWORK_SEND_HZ` | 15 | ネットワーク送信Tick（Hz）- ネットワーク更新頻度 |
| `SEND_EVERY_N_TICKS` | 4 | 送信間隔（シミュレーションTickごと） |

## 同期設定

| 定数 | 値 | 説明 |
|------|-----|------|
| `SYNC_RATE_HZ` | 15 | 同期レート（Hz）- NETWORK_SEND_HZと同値 |
| `SYNC_INTERVAL` | 0.067 | 同期間隔（秒） |
| `POSITION_PRECISION` | 100 | 位置精度（1cm単位） |
| `ROTATION_PRECISION` | 1000 | 回転精度（0.001ラジアン単位） |
| `MAX_PATH_POINTS` | 256 | パス座標の最大数 |
| `MAX_MARKERS_PER_TYPE` | 32 | マーカーの最大数（各種類ごと） |

## 補間設定

| 定数 | 値 | 説明 |
|------|-----|------|
| `INTERPOLATION_DELAY` | 0.08 | 補間バッファ遅延（秒）- 80ms |
| `SNAPSHOT_BUFFER_SIZE` | 30 | スナップショットバッファサイズ（約1秒分） |
| `MAX_EXTRAPOLATION_TIME` | 0.15 | 外挿の最大時間（秒）- 150ms |
| `IDLE_VELOCITY_THRESHOLD` | 0.1 | 静止時の送信間引き閾値 |
| `IDLE_SEND_MULTIPLIER` | 3 | 静止時の送信間隔倍率 |

## タイムアウト設定

| 定数 | 値 | 説明 |
|------|-----|------|
| `CONNECTION_TIMEOUT_MS` | 10000 | 接続タイムアウト（ミリ秒） |
| `HEARTBEAT_INTERVAL` | 1.0 | ハートビート間隔（秒） |
| `DISCONNECT_TIMEOUT` | 5.0 | 切断判定までの無応答時間（秒） |
| `RECONNECT_ATTEMPTS` | 3 | 再接続試行回数 |
| `RECONNECT_DELAY` | 2.0 | 再接続待機時間（秒） |

## チャンネル設定

| 定数 | 値 | 説明 |
|------|-----|------|
| `CHANNEL_RELIABLE` | 0 | 信頼性のあるチャンネル（順序保証・再送あり） |
| `CHANNEL_UNRELIABLE` | 1 | 高速チャンネル（順序保証なし・再送なし） |
| `CHANNEL_ORDERED` | 2 | 順序付きチャンネル（順序保証・再送なし） |

## リレーサーバー設定

| 定数 | 値 | 説明 |
|------|-----|------|
| `RELAY_SERVER_URL` | `wss://...` | 本番リレーサーバーURL |
| `RELAY_SERVER_URL_LOCAL` | `ws://localhost:8080/ws` | ローカル開発用URL |
| `USE_LOCAL_RELAY` | `false` | 開発モードフラグ |

## ユーティリティ関数

### message_type_to_string

```gdscript
static func message_type_to_string(msg_type: MessageType) -> String
```

MessageTypeを文字列に変換。デバッグ用。

### event_type_to_string

```gdscript
static func event_type_to_string(event_type: GameEventType) -> String
```

GameEventTypeを文字列に変換。デバッグ用。

## 使用例

```gdscript
# メッセージタイプの使用
var msg_type = NetworkConstants.MessageType.PATH_CONFIRM
print(NetworkConstants.message_type_to_string(msg_type))  # "PATH_CONFIRM"

# 同期間隔の使用
var timer := Timer.new()
timer.wait_time = NetworkConstants.SYNC_INTERVAL

# 補間遅延の調整（滑らかさ vs レスポンス）
# INTERPOLATION_DELAYを大きくすると滑らかになるがラグが増える
# 推奨範囲: 0.06 ~ 0.12 (60ms ~ 120ms)
```

## パフォーマンスチューニング

### 滑らかさ優先

```gdscript
# network_constants.gd を編集
const INTERPOLATION_DELAY: float = 0.12  # 120ms
const NETWORK_SEND_HZ: int = 20          # 20Hz送信
```

### レスポンス優先

```gdscript
const INTERPOLATION_DELAY: float = 0.05  # 50ms
const NETWORK_SEND_HZ: int = 30          # 30Hz送信（帯域注意）
```

## 関連クラス

- [NetworkMessages](NetworkMessages.md) - メッセージ型定義
- [SyncState](SyncState.md) - 同期状態クラス
- [NetworkSerializer](NetworkSerializer.md) - シリアライズユーティリティ
- [MultiplayerSyncController](MultiplayerSyncController.md) - 同期コントローラー
