# SyncState

同期可能な状態クラス群。

## 概要

ゲーム状態のスナップショットを表現し、ネットワーク同期に使用する。ゲーム全体、プレイヤー、キャラクターそれぞれの状態をカプセル化する。

## ファイル

`godot/scripts/network/sync_state.gd`

## クラス

### GameStateSnapshot

ゲーム状態全体のスナップショット。サーバーからクライアントへの完全同期、または差分同期のベースとして使用。

```gdscript
class GameStateSnapshot extends RefCounted:
    var timestamp: int                                      # 生成時タイムスタンプ
    var is_game_started: bool                               # ゲーム開始済みか
    var round_state: NetworkMessages.RoundStateMessage      # ラウンド状態
    var characters: Array[NetworkMessages.CharacterStateMessage]  # 全キャラクター状態
    var round_number: int                                   # ラウンド番号

    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
```

### PlayerStateData

プレイヤー固有の状態データ。ロビーからゲーム中まで一貫して管理される。

```gdscript
class PlayerStateData extends RefCounted:
    var peer_id: int              # ネットワークpeer_id
    var player_name: String       # プレイヤー名
    var team: int                 # 所属チーム（GameCharacter.Team相当）
    var money: int                # 所持金
    var is_ready: bool            # 準備完了フラグ
    var connection_active: bool   # 接続済みフラグ
    var last_active_time: int     # 最終アクティブ時刻（msec）
    var wins: int                 # 勝利ラウンド数
    var losses: int               # 敗北ラウンド数
    var loss_streak: int          # 連敗数（敗北報酬計算用）

    func _init(p_peer_id: int = 0, p_name: String = "")
    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
    func update_active_time() -> void
    func toggle_ready() -> void
    func on_round_win() -> void
    func on_round_loss() -> void
```

### CharacterSnapshot

キャラクター状態の完全スナップショット。補間処理や予測に必要な情報を含む。

```gdscript
class CharacterSnapshot extends RefCounted:
    var character_id: int         # キャラクターID
    var owner_peer_id: int        # 所属プレイヤーID
    var position: Vector3         # ワールド座標
    var rotation: float           # Y軸回転（ラジアン）
    var facing_direction: Vector3 # 向いている方向ベクトル
    var velocity: Vector3         # 速度ベクトル
    var current_health: float     # 現在HP
    var max_health: float         # 最大HP
    var is_alive: bool            # 生存フラグ
    var team: int                 # チーム
    var weapon_id: String         # 装備中の武器ID
    var animation_state: String   # アニメーション状態
    var timestamp: int            # タイムスタンプ

    static func from_message(msg: NetworkMessages.CharacterStateMessage) -> CharacterSnapshot
    func to_message() -> NetworkMessages.CharacterStateMessage
    func to_dict() -> Dictionary
    func from_dict(data: Dictionary) -> void
    static func interpolate(from_snap: CharacterSnapshot, to_snap: CharacterSnapshot, t: float) -> CharacterSnapshot
```

## 使用例

### ゲーム状態スナップショットの作成

```gdscript
# スナップショットの作成
var snapshot = SyncState.GameStateSnapshot.new()
snapshot.is_game_started = true
snapshot.round_number = 3

# ラウンド状態を設定
snapshot.round_state.phase = RoundManager.RoundPhase.ACTIVE
snapshot.round_state.remaining_time = 90.0
snapshot.round_state.ct_alive_count = 5
snapshot.round_state.t_alive_count = 4

# キャラクター状態を追加
var char_state = NetworkMessages.CharacterStateMessage.new()
char_state.character_id = 1
char_state.position = Vector3(10, 0, 5)
char_state.is_alive = true
snapshot.characters.append(char_state)

# シリアライズ
var dict = snapshot.to_dict()
```

### プレイヤー状態の管理

```gdscript
# プレイヤー状態の作成
var player = SyncState.PlayerStateData.new(1, "Player1")
player.team = GameCharacter.Team.COUNTER_TERRORIST
player.money = 5000

# 準備完了をトグル
player.toggle_ready()

# ラウンド結果の反映
if won:
    player.on_round_win()
else:
    player.on_round_loss()
```

### キャラクターの補間

```gdscript
# 2つのスナップショット間を補間
var interpolated = SyncState.CharacterSnapshot.interpolate(
    previous_snapshot,
    current_snapshot,
    0.5  # 50%の位置
)

# 補間結果を適用
character.global_position = interpolated.position
character.set_facing_direction(interpolated.rotation)
```

## 関連クラス

- [NetworkConstants](NetworkConstants.md) - ネットワーク定数
- [NetworkMessages](NetworkMessages.md) - メッセージ型定義
- [NetworkSerializer](NetworkSerializer.md) - シリアライズユーティリティ
- [PlayerState](../System/PlayerState.md) - プレイヤー状態管理（Autoload）
