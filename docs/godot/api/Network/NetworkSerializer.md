# NetworkSerializer

シリアライズ/デシリアライズユーティリティクラス。

## 概要

ネットワーク転送用のデータ圧縮・展開を行う。パス座標の圧縮、マーカーデータのシリアライズ、差分圧縮などの機能を提供する。

## ファイル

`godot/scripts/network/serialization.gd`

## Vector3配列の圧縮

### compress_vector3_array

```gdscript
static func compress_vector3_array(arr: Array[Vector3], precision: int = NetworkConstants.POSITION_PRECISION) -> PackedByteArray
```

Vector3配列を圧縮してPackedByteArrayに変換。各座標はint16として格納し、precision倍で丸める。

**フォーマット:** `[count:uint16][x:int16][y:int16][z:int16]...`

### decompress_vector3_array

```gdscript
static func decompress_vector3_array(data: PackedByteArray, precision: int = NetworkConstants.POSITION_PRECISION) -> Array[Vector3]
```

PackedByteArrayからVector3配列を復元。

## パスメッセージのシリアライズ

### serialize_path_message

```gdscript
static func serialize_path_message(msg: NetworkMessages.PathConfirmMessage) -> PackedByteArray
```

PathConfirmMessageを圧縮してPackedByteArrayに変換。

### deserialize_path_message

```gdscript
static func deserialize_path_message(data: PackedByteArray) -> NetworkMessages.PathConfirmMessage
```

PackedByteArrayからPathConfirmMessageを復元。

## ゲーム状態のシリアライズ

### serialize_game_state

```gdscript
static func serialize_game_state(snapshot: SyncState.GameStateSnapshot) -> PackedByteArray
```

GameStateSnapshotを圧縮してPackedByteArrayに変換。

### deserialize_game_state

```gdscript
static func deserialize_game_state(data: PackedByteArray) -> SyncState.GameStateSnapshot
```

PackedByteArrayからGameStateSnapshotを復元。

## 汎用シリアライズ

### serialize_dict

```gdscript
static func serialize_dict(dict: Dictionary) -> PackedByteArray
```

DictionaryをJSON形式で圧縮してPackedByteArrayに変換。

### deserialize_dict

```gdscript
static func deserialize_dict(data: PackedByteArray) -> Dictionary
```

PackedByteArrayからDictionaryを復元。

## メッセージラッピング

### wrap_message

```gdscript
static func wrap_message(msg_type: NetworkConstants.MessageType, payload: PackedByteArray) -> PackedByteArray
```

ネットワークメッセージをラップして送信用フォーマットに変換。

**フォーマット:** `[msg_type:uint8][payload_size:uint32][payload:bytes]`

### unwrap_message

```gdscript
static func unwrap_message(data: PackedByteArray) -> Array
```

ラップされたメッセージをアンラップ。

**戻り値:** `[msg_type: int, payload: PackedByteArray]` または空配列（エラー時）

## 差分圧縮ユーティリティ

### compute_path_delta

```gdscript
static func compute_path_delta(old_path: Array[Vector3], new_path: Array[Vector3]) -> Dictionary
```

2つのVector3配列の差分を計算。

**戻り値:**
```gdscript
{
    "old_len": int,
    "new_len": int,
    "changes": [{ "i": int, "v": [float, float, float] }, ...]
}
```

### apply_path_delta

```gdscript
static func apply_path_delta(base_path: Array[Vector3], delta: Dictionary) -> Array[Vector3]
```

差分データを適用してパスを更新。

## バリデーション

### validate_path_message

```gdscript
static func validate_path_message(msg: NetworkMessages.PathConfirmMessage) -> bool
```

パスメッセージの妥当性を検証。

**検証内容:**
- パスが空でないこと
- パス座標数が `MAX_PATH_POINTS` 以内
- 各マーカー数が `MAX_MARKERS_PER_TYPE` 以内

## 使用例

### パス座標の圧縮・復元

```gdscript
# パス座標を圧縮
var path: Array[Vector3] = [
    Vector3(0, 0, 0),
    Vector3(5.5, 0, 3.2),
    Vector3(10.1, 0, 8.7)
]
var compressed = NetworkSerializer.compress_vector3_array(path)
print("Compressed size: ", compressed.size(), " bytes")  # 約20バイト

# 復元
var restored = NetworkSerializer.decompress_vector3_array(compressed)
for i in path.size():
    print("Original: ", path[i], " Restored: ", restored[i])
```

### パスメッセージの送受信

```gdscript
# 送信側
var msg = NetworkMessages.create_path_confirm(peer_id, char_id, path)
msg.vision_points.append({"path_ratio": 0.5, "direction": [1, 0, 0]})

# シリアライズ
var payload = NetworkSerializer.serialize_path_message(msg)
var wrapped = NetworkSerializer.wrap_message(NetworkConstants.MessageType.PATH_CONFIRM, payload)

# ネットワーク送信...
peer.put_packet(wrapped)

# 受信側
var received_data = peer.get_packet()
var unwrapped = NetworkSerializer.unwrap_message(received_data)
if unwrapped.size() == 2:
    var msg_type = unwrapped[0]
    var msg_payload = unwrapped[1]

    if msg_type == NetworkConstants.MessageType.PATH_CONFIRM:
        var path_msg = NetworkSerializer.deserialize_path_message(msg_payload)
        # パスメッセージを処理...
```

### 差分同期

```gdscript
# 差分を計算
var old_path: Array[Vector3] = [Vector3(0, 0, 0), Vector3(5, 0, 5)]
var new_path: Array[Vector3] = [Vector3(0, 0, 0), Vector3(5, 0, 6), Vector3(10, 0, 10)]
var delta = NetworkSerializer.compute_path_delta(old_path, new_path)

# 差分を適用
var restored_path = NetworkSerializer.apply_path_delta(old_path, delta)
# restored_path == new_path
```

## 関連クラス

- [NetworkConstants](NetworkConstants.md) - ネットワーク定数
- [NetworkMessages](NetworkMessages.md) - メッセージ型定義
- [SyncState](SyncState.md) - 同期状態クラス
