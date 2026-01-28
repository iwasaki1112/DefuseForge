# NetworkManager

**継承:** `Node`

ネットワーク接続管理クラス。
WebSocketリレーサーバー経由でのマルチプレイ接続、ルーム管理、プレイヤー管理、メッセージリレーを担当します。

## アーキテクチャ

```
┌─────────┐     ┌─────────────────┐     ┌─────────┐
│ Player1 │────▶│   Cloud Run     │◀────│ Player2 │
│ (Host)  │◀────│ WebSocket Relay │────▶│(Client) │
└─────────┘     └─────────────────┘     └─────────┘
```

- **ホスト**: ルームを作成し、`peer_id=1`を持つ
- **クライアント**: ルームリストから選択して参加

## 状態列挙体 (ConnectionState)

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `DISCONNECTED` | `0` | 未接続 |
| `CONNECTING` | `1` | 接続試行中 |
| `CONNECTED` | `2` | ルームに参加済み（クライアント） |
| `HOST` | `3` | ホストとして動作中 |

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `connection_state_changed` | `state: ConnectionState` | 接続状態が変化した時 |
| `peer_connected` | `peer_id: int` | 新しいピアがルームに参加した時 |
| `peer_disconnected` | `peer_id: int` | ピアがルームから退出した時 |
| `connection_failed` | `reason: String` | 接続に失敗した時 |
| `message_received` | `from_peer: int, msg_type: int, data: Dictionary` | リレーメッセージを受信した時 |
| `all_peers_ready` | `void` | 全プレイヤーの準備が完了した時（ホストのみ） |
| `players_updated` | `void` | プレイヤーリストが更新された時 |
| `room_list_received` | `rooms: Array` | ルーム一覧を受信した時 |
| `room_created` | `room_id: String` | ルーム作成が完了した時 |
| `room_joined` | `room_id: String` | ルーム参加が完了した時 |

## メソッド

### ルーム管理

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `create_room(room_name, player_name)` | `bool` | ルームを作成してホストになります。 |
| `join_room(room_id, player_name)` | `bool` | 指定IDのルームに参加します。 |
| `request_room_list()` | `bool` | 利用可能なルーム一覧を要求します。 |
| `disconnect_from_game()` | `void` | ルームから退出し、接続を切断します。 |

### プレイヤー管理

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `set_ready(ready: bool)` | `void` | ローカルプレイヤーの準備完了状態を設定し、同期します。 |
| `set_team(team: int)` | `void` | ローカルプレイヤーのチームを設定し、同期します。 |
| `get_players()` | `Dictionary` | 現在の全プレイヤー情報のコピーを取得します。 |

### メッセージング

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `send_message(to, type, data)` | `void` | 特定のピアにメッセージを送信します。 |
| `broadcast_message(type, data)` | `void` | 全員にメッセージを送信します（自分以外）。 |
| `send_to_host(type, data)` | `void` | ホストにメッセージを送信します。 |

### ユーティリティ

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `is_host()` | `bool` | ホストかどうか |
| `is_connected_to_game()` | `bool` | ルームに接続中かどうか |
| `get_local_peer_id()` | `int` | ローカルのピアID |
| `get_state()` | `ConnectionState` | 現在の接続状態 |
| `get_room_id()` | `String` | 現在のルームID |
| `get_room_name()` | `String` | 現在のルーム名 |

## 使用例

```gdscript
# ルーム作成（ホスト）
func _on_host_pressed():
    if network_manager.create_room("My Room", "HostPlayer"):
        print("ルーム作成中...")

# ルーム一覧取得
func _on_join_pressed():
    network_manager.room_list_received.connect(_on_room_list)
    network_manager.request_room_list()

func _on_room_list(rooms: Array):
    for room in rooms:
        print("Room: %s (%d/%d)" % [room.name, room.player_count, room.max_players])

# ルーム参加
func _join_room(room_id: String):
    if network_manager.join_room(room_id, "ClientPlayer"):
        print("参加中...")
```

## 非推奨API

以下のAPIは後方互換性のために残されていますが、使用は推奨されません：

| 名前 | 代替 |
| :--- | :--- |
| `host_game(port, name)` | `create_room(room_name, player_name)` |
| `join_game(ip, port, name)` | `join_room(room_id, player_name)` |
| `get_local_ip()` | 不要（リレー方式では使用しない） |
| `get_port()` | 不要（リレー方式では使用しない） |
