# NetworkMessages

ネットワーク同期用メッセージ型定義クラス。

## 概要

パス確定、ラウンド状態、キャラクター状態、ゲームイベントなど、ネットワーク越しにやり取りするデータ構造を定義する。

## ファイル

`godot/scripts/network/network_messages.gd`

## メッセージクラス

### PathConfirmMessage

パス確定時に送信するメッセージ。キャラクターの移動パスと全マーカー情報を含む。

```gdscript
class PathConfirmMessage extends RefCounted:
    var player_id: int              # 送信元プレイヤーID
    var character_id: int           # 対象キャラクターID
    var path: Array[Vector3]        # パス座標配列
    var vision_markers: Array[Dictionary]      # 視線マーカー
    var run_segments: Array[Dictionary]        # Run区間
    var clear_markers: Array[Dictionary]       # Clearマーカー
    var grenade_markers: Array[Dictionary]     # グレネードマーカー
    var door_markers: Array[Dictionary]        # ドアマーカー
    var wait_markers: Array[Dictionary]        # Waitマーカー
    var smoke_grenade_markers: Array[Dictionary] # スモークグレネードマーカー
    var timestamp: int              # タイムスタンプ（msec）

    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
```

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
    var character_id: int       # キャラクターID
    var position: Vector3       # ワールド座標
    var rotation: float         # Y軸回転（ラジアン）
    var current_health: int     # 現在のHP
    var is_alive: bool          # 生存フラグ
    var animation_state: String # アニメーション状態
    var velocity: Vector3       # 移動速度（m/s）
    var is_crouching: bool      # しゃがみ状態
    var timestamp: int          # タイムスタンプ

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

### create_path_confirm

```gdscript
static func create_path_confirm(player_id: int, character_id: int, path: Array[Vector3]) -> PathConfirmMessage
```

PathConfirmMessageを作成。

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
# パス確定メッセージの作成
var path: Array[Vector3] = [Vector3(0, 0, 0), Vector3(5, 0, 3)]
var msg = NetworkMessages.create_path_confirm(1, 100, path)
msg.vision_markers.append({
    "path_ratio": 0.5,
    "target_point": [10.0, 1.0, 5.0],
    "has_target": true
})

# シリアライズ
var dict = msg.to_dict()

# デシリアライズ
var restored = NetworkMessages.PathConfirmMessage.new()
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
- [ActionMarkerData](ActionMarkerData.md) - マーカーデータ構造
