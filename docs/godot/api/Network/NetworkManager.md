# NetworkManager

**継承:** `Node`

ネットワーク接続管理クラス。
ENetを使用したP2P接続（ホスト/クライアント）、プレイヤー管理、RPCによるメッセージ同期を担当します。

## 状態列挙体 (ConnectionState)

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `DISCONNECTED` | `0` | 未接続 |
| `CONNECTING` | `1` | 接続試行中 |
| `CONNECTED` | `2` | サーバーに接続済み（クライアント） |
| `HOST` | `3` | ホストとして動作中 |

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `connection_state_changed` | `state: ConnectionState` | 接続状態が変化した時 |
| `peer_connected` | `peer_id: int` | 新しいピアが接続した時 |
| `peer_disconnected` | `peer_id: int` | ピアが切断した時 |
| `connection_failed` | `reason: String` | 接続に失敗した時 |
| `message_received` | `from_peer: int, msg_type: int, data: Dictionary` | 汎用メッセージを受信した時 |
| `all_peers_ready` | `void` | 全プレイヤーの準備が完了した時（ホストのみ） |
| `players_updated` | `void` | プレイヤーリストが更新された時 |

## メソッド

### 接続管理

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `host_game(port, name)` | `bool` | 指定ポートでホストとしてサーバーを起動します。 |
| `join_game(ip, port, name)` | `bool` | 指定IP・ポートのサーバーに接続します。 |
| `disconnect_from_game()` | `void` | 接続を切断し、状態をリセットします。 |

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
| `broadcast_message(type, data)` | `void` | 全員にメッセージを送信します。 |
| `send_to_host(type, data)` | `void` | ホストにメッセージを送信します。 |
