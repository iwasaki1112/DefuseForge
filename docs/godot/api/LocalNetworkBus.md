# LocalNetworkBus

ローカルネットワークシミュレーター。同一PC上でHost/Client間のメッセージ通信をシミュレート。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `LocalNetworkBus` |
| ファイルパス | `scripts/network/local_network_bus.gd` |

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `HOST_PEER_ID` | `1` | ホストのpeer_id |
| `CLIENT_PEER_ID` | `2` | クライアントのpeer_id |

## Exportプロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `simulated_latency_ms` | `float` | `0.0` | シミュレートする遅延（ミリ秒） |
| `packet_loss_rate` | `float` | `0.0` | パケットロス率（0.0〜1.0） |

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `message_received` | `from_peer: int, to_peer: int, msg_type: int, data: Dictionary` | メッセージ受信時 |
| `peer_connected` | `peer_id: int` | ピア接続時 |
| `peer_disconnected` | `peer_id: int` | ピア切断時 |

## メソッド

### 接続管理

```gdscript
# ピアを接続
func connect_peer(peer_id: int) -> void

# ピアを切断
func disconnect_peer(peer_id: int) -> void

# 全ピアを切断
func disconnect_all() -> void

# Host/Client両方をセットアップ
func setup_local_session() -> void
```

### メッセージ送信

```gdscript
# メッセージを送信
func send_message(from_peer: int, to_peer: int, msg_type: int, data: Dictionary) -> void

# ブロードキャスト（Hostから全Clientへ）
func broadcast_from_host(msg_type: int, data: Dictionary) -> void
```

### ユーティリティ

```gdscript
# 接続中のピア一覧を取得
func get_connected_peers() -> Array[int]

# ピアが接続中か確認
func is_peer_connected(peer_id: int) -> bool

# ログを取得
func get_message_log() -> Array[Dictionary]

# ログをクリア
func clear_log() -> void

# メッセージタイプ名を取得（デバッグ用）
func get_message_type_name(msg_type: int) -> String

# ログエントリをフォーマット
func format_log_entry(entry: Dictionary) -> String
```

## 使用例

```gdscript
# セットアップ
var bus = LocalNetworkBus.new()
add_child(bus)
bus.setup_local_session()

# シグナル接続
bus.message_received.connect(_on_message)

# メッセージ送信
bus.send_message(
    LocalNetworkBus.HOST_PEER_ID,
    LocalNetworkBus.CLIENT_PEER_ID,
    NetworkConstants.MessageType.GAME_STATE_SYNC,
    {"timestamp": Time.get_ticks_msec()}
)

# 遅延シミュレーション
bus.simulated_latency_ms = 50.0  # 50ms遅延

# パケットロスシミュレーション
bus.packet_loss_rate = 0.1  # 10%ロス
```

## 関連クラス

- [MultiplayerSyncController](MultiplayerSyncController.md) - 同期処理
- [NetworkConstants](NetworkConstants.md) - メッセージタイプ定数
