# NetworkManager

**継承:** `Node`

ネットワーク接続管理クラス。
WebSocketリレーサーバー経由でのマルチプレイ接続、マッチメイキング、プレイヤー管理、メッセージリレーを担当します。

## アーキテクチャ

```
┌─────────┐     ┌─────────────────┐     ┌─────────┐
│ Player1 │────▶│   Cloud Run     │◀────│ Player2 │
│ (Host)  │◀────│ WebSocket Relay │────▶│(Client) │
└─────────┘     └─────────────────┘     └─────────┘
```

- **ホスト**: マッチ成立時に先にキューに入ったプレイヤー（`peer_id=1`）
- **クライアント**: マッチ成立時に後からキューに入ったプレイヤー（`peer_id=2`）
- **マッチング**: `find_match()`でオートマッチングキューに参加、2人揃ったらサーバーがルーム自動作成・ゲーム開始

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
| `match_found` | `room_id: String, map_id: String` | オートマッチが成立した時 |

## メソッド

### マッチメイキング

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `find_match(player_name)` | `bool` | オートマッチングキューに参加します。2人揃うとサーバーがルーム自動作成し`match_found`シグナルが発火します。 |
| `cancel_match()` | `void` | マッチングをキャンセルして切断します。 |

### 接続管理

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
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

## 使用例

```gdscript
# オートマッチング（推奨）
func _ready():
    network_manager.match_found.connect(_on_match_found)
    network_manager.find_match("PlayerName")

func _on_match_found(room_id: String, map_id: String):
    print("マッチ成立！ルーム: %s, マップ: %s" % [room_id, map_id])
    _start_game(map_id)

# マッチングキャンセル
func _on_cancel_pressed():
    network_manager.cancel_match()
```

