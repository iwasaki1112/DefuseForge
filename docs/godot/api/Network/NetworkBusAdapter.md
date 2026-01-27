# NetworkBusAdapter

**継承:** `Node`

`NetworkManager` をラップし、`LocalNetworkBus` と互換性のあるインターフェースを提供するアダプタクラス。
これにより、`MultiplayerSyncController` などのコンポーネントが、ローカル環境とネットワーク環境の両方で同じコードを使用して動作できるようになります。

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `message_received` | `from_peer: int, to_peer: int, msg_type: int, data: Dictionary` | メッセージ受信時に発火します。`to_peer` は常にローカルピアIDになります。 |

## 定数

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `HOST_PEER_ID` | `1` | ホストのピアID |
| `BROADCAST_ID` | `0` | ブロードキャスト用ID |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `setup(network_manager: NetworkManager)` | `void` | NetworkManagerへの参照を設定し、シグナルを接続します。 |
| `send_message(from, to, type, data)` | `void` | 指定された宛先へメッセージを送信します。 |
| `broadcast_from_host(type, data)` | `void` | ホストから全クライアントへブロードキャストします（互換性用）。 |
| `is_host()` | `bool` | 現在のクライアントがホストかどうかを返します。 |
| `get_local_peer_id()` | `int` | ローカルのピアIDを取得します。 |
