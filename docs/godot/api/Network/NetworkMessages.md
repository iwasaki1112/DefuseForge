# NetworkMessages

ネットワーク同期用メッセージ型定義クラス。

## 概要

ラウンド状態、キャラクター状態、ゲームイベントなど、ネットワーク越しにやり取りするデータ構造を定義する。

## ファイル

`godot/scripts/network/network_messages.gd`

## メッセージクラス

### RoundStateMessage

ラウンド状態を同期するメッセージ。

```gdscript
class RoundStateMessage extends RefCounted:
    var phase: int              # RoundManager.RoundPhase相当（0:NONE, 1:ACTIVE, 2:ENDED）
    var remaining_time: float   # 残り時間（秒）
    var ct_alive_count: int     # CT生存者数
    var t_alive_count: int      # T生存者数
    var winner_team: int        # 勝利チーム（GameCharacter.Team相当）
    var end_reason: int         # 終了理由（RoundManager.EndReason相当）
    var timestamp: int          # タイムスタンプ

    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
```

### CharacterStateMessage

キャラクター状態を同期するメッセージ。

```gdscript
class CharacterStateMessage extends RefCounted:
    var character_id: int            # キャラクターID
    var position: Vector3            # ワールド座標
    var rotation: float              # Y軸回転（ラジアン）
    var current_health: int          # 現在のHP
    var is_alive: bool               # 生存フラグ
    var animation_state: String      # @deprecated TPS移行後は move_state ベースの同期に変更
    var velocity: Vector3            # 移動速度（m/s）
    var character_preset_id: String  # キャラクタープリセットID（初期同期用）
    var weapon_id: String            # 武器ID（初期同期用）
    var timestamp: int               # タイムスタンプ

    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
```

### GameEventMessage

ゲーム内イベントを通知するメッセージ。

```gdscript
class GameEventMessage extends RefCounted:
    var event_type: int         # NetworkConstants.GameEventType
    var source_id: int          # イベント発生源のID
    var target_id: int          # イベント対象のID
    var data: Dictionary        # イベント固有データ
    var timestamp: int          # タイムスタンプ

    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
```

**イベント固有データの例:**

| イベント | dataの内容 |
|----------|-----------|
| DAMAGE | `{ damage: float, is_headshot: bool }` |
| DEATH | `{ killer_id: int, is_headshot: bool }` |
| GRENADE_THROW | `{ target_pos: Array, grenade_type: int }` |
| DOOR_KICK | `{ door_id: int }` |

### PlayerReadyMessage

プレイヤーの準備完了状態を通知するメッセージ。

```gdscript
class PlayerReadyMessage extends RefCounted:
    var player_id: int    # プレイヤーID
    var is_ready: bool    # 準備完了フラグ
    var timestamp: int    # タイムスタンプ

    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
```

## ファクトリメソッド

### get_timestamp

```gdscript
static func get_timestamp() -> int
```

現在時刻のタイムスタンプを取得。

### create_round_state

```gdscript
static func create_round_state(phase: int, remaining_time: float, ct_count: int, t_count: int) -> RoundStateMessage
```

RoundStateMessageを作成。

### create_character_state

```gdscript
static func create_character_state(char_id: int, pos: Vector3, rot: float, health: int, alive: bool) -> CharacterStateMessage
```

CharacterStateMessageを作成。

### create_game_event

```gdscript
static func create_game_event(event_type: int, source_id: int, target_id: int, data: Dictionary = {}) -> GameEventMessage
```

GameEventMessageを作成。

## 使用例

```gdscript
# キャラクター状態メッセージの作成
var msg = NetworkMessages.create_character_state(100, Vector3(5, 0, 3), 1.57, 80, true)

# シリアライズ
var dict = msg.to_dict()

# デシリアライズ
var restored = NetworkMessages.CharacterStateMessage.new()
restored.from_dict(dict)

# ゲームイベントの作成
var damage_event = NetworkMessages.create_game_event(
    NetworkConstants.GameEventType.DAMAGE,
    101,  # 攻撃者ID
    102,  # 被害者ID
    { "damage": 25.0, "is_headshot": false }
)
```

## 関連クラス

- [NetworkConstants](NetworkConstants.md) - ネットワーク定数
- [SyncState](SyncState.md) - 同期状態クラス
- [NetworkSerializer](NetworkSerializer.md) - シリアライズユーティリティ
