# NetworkSerializer

シリアライズ/デシリアライズユーティリティクラス。

## 概要

ネットワーク転送用のデータ圧縮・展開を行う。Vector3配列の圧縮、キャラクター状態のバイナリシリアライズ、メッセージラッピングなどの機能を提供する。

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

## ゲーム状態のシリアライズ

### serialize_game_state

```gdscript
static func serialize_game_state(snapshot: SyncState.GameStateSnapshot) -> PackedByteArray
```

GameStateSnapshotをJSON形式でPackedByteArrayに変換。

### deserialize_game_state

```gdscript
static func deserialize_game_state(data: PackedByteArray) -> SyncState.GameStateSnapshot
```

PackedByteArrayからGameStateSnapshotを復元。

## キャラクター状態のバイナリシリアライズ

### serialize_character_state_binary

```gdscript
static func serialize_character_state_binary(state: NetworkMessages.CharacterStateMessage) -> PackedByteArray
```

CharacterStateMessageを36バイトのバイナリ形式でシリアライズ。

**フォーマット:** `[char_id:u32][pos_x:i16][pos_y:i16][pos_z:i16][rot:i16][vel_x:i16][vel_y:i16][vel_z:i16][hp:u8][flags:u8][anim_state:16bytes]`

### deserialize_character_state_binary

```gdscript
static func deserialize_character_state_binary(data: PackedByteArray) -> NetworkMessages.CharacterStateMessage
```

バイナリ形式のCharacterStateMessageをデシリアライズ。

### serialize_character_states_binary

```gdscript
static func serialize_character_states_binary(states: Array[NetworkMessages.CharacterStateMessage]) -> PackedByteArray
```

複数キャラクター状態をバイナリでシリアライズ。

**フォーマット:** `[count:u8][char_states...]`

### deserialize_character_states_binary

```gdscript
static func deserialize_character_states_binary(data: PackedByteArray) -> Array[NetworkMessages.CharacterStateMessage]
```

バイナリ形式の複数キャラクター状態をデシリアライズ。

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

## 使用例

### Vector3配列の圧縮・復元

```gdscript
var positions: Array[Vector3] = [
    Vector3(0, 0, 0),
    Vector3(5.5, 0, 3.2),
    Vector3(10.1, 0, 8.7)
]
var compressed = NetworkSerializer.compress_vector3_array(positions)
print("Compressed size: ", compressed.size(), " bytes")

var restored = NetworkSerializer.decompress_vector3_array(compressed)
```

### キャラクター状態のバイナリ送受信

```gdscript
# バイナリシリアライズ
var state = character.to_character_state()
var binary = NetworkSerializer.serialize_character_state_binary(state)

# 一括シリアライズ
var states: Array[NetworkMessages.CharacterStateMessage] = []
for char in characters:
    states.append(char.to_character_state())
var batch_binary = NetworkSerializer.serialize_character_states_binary(states)

# デシリアライズ
var restored_state = NetworkSerializer.deserialize_character_state_binary(binary)
var restored_states = NetworkSerializer.deserialize_character_states_binary(batch_binary)
```

## 関連クラス

- [NetworkConstants](NetworkConstants.md) - ネットワーク定数
- [NetworkMessages](NetworkMessages.md) - メッセージ型定義
- [SyncState](SyncState.md) - 同期状態クラス
