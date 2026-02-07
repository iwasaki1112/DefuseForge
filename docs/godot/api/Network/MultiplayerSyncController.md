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
| `network_bus` | `Node` | ネットワークバス参照（LocalNetworkBusまたはNetworkBusAdapter） |
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
    bus: Node,
    gm: GameManager,
    my_peer_id: int,
    host: bool
) -> void
```

### 状態同期

```gdscript
# 状態同期を送信（Host→Client）
func send_state_sync() -> void

# ローカルキャラクター状態を送信（Client→Host）
func send_local_character_states() -> void

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

# キャラクター更新をバイナリ形式で送信（高効率版）
func send_character_update_binary(char_state: CharacterStateMessage) -> void

# 複数キャラクター状態を一括送信（バイナリ形式）
func send_character_batch_update_binary(states: Array[CharacterStateMessage]) -> void

# ラウンド状態を送信（Host→Client）
func send_round_state() -> void

# ゲームイベントを送信
func send_game_event(event: GameEventMessage) -> void

# アニメーションイベントを即時送信
func send_animation_event(character_id: int, anim_event: AnimationEventType, extra_data: Dictionary = {}) -> void

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
1. `send_state_sync()` - 定期的な全体同期（15Hz）
2. `send_path_execute()` - パス実行指示
3. `send_round_state()` - ラウンド状態変更

### Client → Host
1. `send_path_confirm()` - パス確定リクエスト
2. `send_local_character_states()` - キャラクター状態変更（15Hz）
3. `send_game_event()` - ゲームイベント（グレネード、スモーク、ドアキック等）

### 双方向
- `send_selection_update()` - 選択状態（表示用）
- `send_animation_event()` - アニメーションイベント（即時）

### 帯域幅の最適化

- **バイナリシリアライズ**: キャラクター状態の更新は`CharacterStateMessage`をバイナリ変換し、Base64エンコードしてJSONに埋め込むことでデータサイズを削減しています。
- **一括送信 (Batching)**: 複数のローカルキャラクターの状態を1つのメッセージ(`CHARACTER_BATCH_UPDATE_BINARY`)にまとめて送信します。
- **差分更新 (Delta Compression)**: キャラクターの位置や回転、状態に有意な変化がない場合は送信をスキップします（Debug実装）。

## ラグ補償アーキテクチャ

### 補間バッファ

リモートキャラクターは補間バッファを使用して滑らかに描画される：

1. **スナップショットバッファ**: 受信した状態を時系列で保存（約1秒分）
2. **補間遅延**: 80ms遅れた時点の状態を2点間補間で描画
3. **外挿**: パケットロス時は最大150msまで速度ベースで予測

```
受信状態: ──●──────●──────●──────●───→ 時間
           t-3    t-2    t-1    t(現在)
                           ↑
                    描画位置（80ms遅延）
```

### Tick分離

- **シミュレーションTick**: 60Hz（ゲームロジック）
- **ネットワーク送信Tick**: 15Hz（帯域削減）

### アニメーション同期

| 種別 | 送信方式 | 例 |
|------|---------|-----|
| 状態同期 | 定期送信（15Hz） | 移動、しゃがみ |
| イベント同期 | 即時送信 | 発砲、リロード、死亡 |

## 関連クラス

- [LocalNetworkBus](LocalNetworkBus.md) - ローカルネットワークシミュレーター
- [NetworkBusAdapter](NetworkBusAdapter.md) - WebSocketアダプター
- [GameManager](../GameManager.md) - ゲーム管理
- [NetworkMessages](NetworkMessages.md) - メッセージ型
- [NetworkConstants](NetworkConstants.md) - 定数定義
- [SyncState](SyncState.md) - 同期状態
