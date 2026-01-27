# MultiplayerSyncController

マルチプレイヤー同期コントローラー。GameManagerとLocalNetworkBus間の同期処理を管理。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `MultiplayerSyncController` |
| ファイルパス | `scripts/network/multiplayer_sync_controller.gd` |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `network_bus` | `LocalNetworkBus` | ネットワークバス参照 |
| `game_manager` | `GameManager` | GameManager参照 |
| `peer_id` | `int` | 自分のpeer_id |
| `is_host` | `bool` | ホストかどうか |

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `sync_state_received` | `snapshot: GameStateSnapshot` | 状態同期受信時 |
| `path_confirmed_remote` | `player_id: int, path_msg: PathConfirmMessage` | リモートパス確定受信時 |
| `character_updated_remote` | `char_state: CharacterStateMessage` | キャラクター更新受信時 |
| `round_state_updated` | `round_state: RoundStateMessage` | ラウンド状態更新時 |
| `game_event_received` | `event: GameEventMessage` | ゲームイベント受信時 |

## メソッド

### セットアップ

```gdscript
func setup(
    bus: LocalNetworkBus,
    gm: GameManager,
    my_peer_id: int,
    host: bool
) -> void
```

### 状態同期

```gdscript
# 状態同期を送信（Host→Client）
func send_state_sync() -> void

# 自動同期の有効/無効
func set_auto_sync_enabled(enabled: bool) -> void

# 同期間隔を設定
func set_sync_interval(interval: float) -> void
```

### パス同期

```gdscript
# パス確定を送信
func send_path_confirm(path_msg: PathConfirmMessage) -> void

# パス実行を送信（Host→Client）
func send_path_execute(run: bool) -> void
```

### キャラクター・イベント

```gdscript
# キャラクター更新を送信
func send_character_update(char_state: CharacterStateMessage) -> void

# ラウンド状態を送信（Host→Client）
func send_round_state() -> void

# ゲームイベントを送信
func send_game_event(event: GameEventMessage) -> void

# 選択状態を送信
func send_selection_update() -> void
```

## 使用例

```gdscript
# Host側セットアップ
var host_sync = MultiplayerSyncController.new()
add_child(host_sync)
host_sync.setup(network_bus, game_manager, LocalNetworkBus.HOST_PEER_ID, true)

# Client側セットアップ
var client_sync = MultiplayerSyncController.new()
add_child(client_sync)
client_sync.setup(network_bus, game_manager, LocalNetworkBus.CLIENT_PEER_ID, false)

# シグナル接続
client_sync.sync_state_received.connect(func(snapshot):
    print("Received sync with %d characters" % snapshot.characters.size())
)

# 手動同期（Host）
host_sync.send_state_sync()

# パス実行通知（Host）
host_sync.send_path_execute(false)  # 歩き
```

## 同期フロー

### Host → Client
1. `send_state_sync()` - 定期的な全体同期（20Hz）
2. `send_path_execute()` - パス実行指示
3. `send_round_state()` - ラウンド状態変更

### Client → Host
1. `send_path_confirm()` - パス確定リクエスト
2. `send_character_update()` - キャラクター状態変更
3. `send_game_event()` - ゲームイベント

### 双方向
- `send_selection_update()` - 選択状態（表示用）

## 関連クラス

- [LocalNetworkBus](LocalNetworkBus.md) - ネットワークシミュレーター
- [GameManager](GameManager.md) - ゲーム管理
- [NetworkMessages](NetworkMessages.md) - メッセージ型
- [SyncState](SyncState.md) - 同期状態
