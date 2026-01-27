# NetworkConstants

ネットワーク関連の定数定義クラス。

## 概要

メッセージタイプID、同期設定、タイムアウト値などネットワーク同期に必要な定数を一元管理する。

## ファイル

`godot/scripts/network/network_constants.gd`

## メッセージタイプ

```gdscript
enum MessageType {
    GAME_STATE_SYNC = 0,  # ゲーム状態の同期
    PATH_CONFIRM = 1,     # パス確定メッセージ
    PATH_EXECUTE = 2,     # パス実行開始メッセージ
    CHARACTER_UPDATE = 3, # キャラクター状態更新
    ROUND_STATE = 4,      # ラウンド状態
    GAME_EVENT = 5,       # ゲームイベント（ダメージ、死亡等）
    PLAYER_READY = 6,     # プレイヤー準備完了
    TEAM_CHANGE = 7,      # チーム変更
}
```

## ゲームイベントタイプ

```gdscript
enum GameEventType {
    DAMAGE = 0,        # ダメージ発生
    DEATH = 1,         # キャラクター死亡
    GRENADE_THROW = 2, # グレネード投擲
    DOOR_KICK = 3,     # ドアキック
    WEAPON_FIRE = 4,   # 武器発射
    RELOAD = 5,        # リロード
}
```

## 同期設定

| 定数 | 値 | 説明 |
|------|-----|------|
| `SYNC_RATE_HZ` | 20 | 同期レート（Hz） |
| `SYNC_INTERVAL` | 0.05 | 同期間隔（秒） |
| `POSITION_PRECISION` | 100 | 位置精度（1cm単位） |
| `ROTATION_PRECISION` | 1000 | 回転精度（0.001ラジアン単位） |
| `MAX_PATH_POINTS` | 256 | パス座標の最大数 |
| `MAX_MARKERS_PER_TYPE` | 32 | マーカーの最大数（各種類ごと） |

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
```

## 関連クラス

- [NetworkMessages](NetworkMessages.md) - メッセージ型定義
- [SyncState](SyncState.md) - 同期状態クラス
- [NetworkSerializer](NetworkSerializer.md) - シリアライズユーティリティ
