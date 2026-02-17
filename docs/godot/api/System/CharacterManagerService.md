# CharacterManagerService

キャラクター管理サービス。キャラクターの登録・検索・フィルタリングを一元管理。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `CharacterManagerService` |
| ファイルパス | `scripts/systems/character_manager_service.gd` |
| 抽出元 | GameManager |

## 概要

GameManagerから抽出されたキャラクター管理コンポーネント。キャラクターの登録・登録解除、ネットワークID検索、ローカル/リモートフィルタリング、スナップショット取得を担当する。

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `character_registered` | `character: Node` | キャラクター登録時 |
| `character_unregistered` | `character: Node` | キャラクター登録解除時 |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `characters` | `Array[Node]` | 登録されたキャラクターリスト |

## メソッド

### set_multiplayer_mode(enabled: bool, local_peer_id: int) -> void
マルチプレイヤーモードを設定する。

### register_character(character: Node) -> bool
キャラクターを登録する。既に登録済みの場合は`false`を返す。

### unregister_character(character: Node) -> bool
キャラクターを登録解除する。

### register_character_with_network(character: Node, owner_peer_id: int, network_id: int) -> bool
キャラクターをマルチプレイヤー対応で登録する。

### is_local_character(character: Node) -> bool
キャラクターがローカルプレイヤーのものか判定する。シングルプレイヤーモードでは常に`true`。

### has_control_permission(character: Node) -> bool
キャラクターに対する操作権限があるか判定する。

### find_character_by_network_id(network_id: int) -> GameCharacter
ネットワークIDからキャラクターを検索する。

### find_characters_by_owner(owner_peer_id: int) -> Array[GameCharacter]
peer_idからキャラクターを検索する（複数可）。

### filter_local_characters(chars: Array) -> Array[Node]
ローカルキャラクターのみをフィルタリングする。

### filter_remote_characters(chars: Array) -> Array[Node]
リモートキャラクターのみをフィルタリングする。

### get_local_friendly_characters() -> Array[Node]
ローカルプレイヤーの味方キャラクター一覧を取得する。

### get_remote_characters() -> Array[Node]
リモートプレイヤーのキャラクター一覧を取得する。

### get_all_character_snapshots() -> Array[SyncState.CharacterSnapshot]
全キャラクターの状態をスナップショットとして取得する。

### get_character_count() -> int
キャラクター数を取得する。

### get_all_characters() -> Array[Node]
全キャラクターを取得する。

### has_character(character: Node) -> bool
キャラクターを含むか判定する。

### clear_all() -> void
全キャラクターをクリアする（登録解除シグナルは発火しない）。

## 使用例

```gdscript
# GameSystemFactory経由で生成
var character_manager = factory.create_character_manager_service()

# キャラクター登録
character_manager.register_character(character)

# ネットワーク検索
var target = character_manager.find_character_by_network_id(network_id)

# フィルタリング
var local_chars = character_manager.filter_local_characters()
var remote_chars = character_manager.filter_remote_characters()
```

## 関連クラス

- [GameManager](GameManager.md) - 使用者
- [GameCharacter](../Character/GameCharacter.md) - 管理対象
- [GameSystemFactory](GameSystemFactory.md) - 生成元

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `character_registered` | `character: Node` |
| `character_unregistered` | `character: Node` |

### メソッド
- `set_multiplayer_mode(enabled: bool, local_peer_id: int) -> void`
- `register_character(character: Node) -> bool`
- `unregister_character(character: Node) -> bool`
- `register_character_with_network(character: Node, owner_peer_id: int, network_id: int) -> bool`
- `is_local_character(character: Node) -> bool`
- `has_control_permission(character: Node) -> bool`
- `find_character_by_network_id(network_id: int) -> GameCharacter`
- `find_characters_by_owner(owner_peer_id: int) -> Array[GameCharacter]`
- `filter_local_characters(chars: Array) -> Array[Node]`
- `filter_remote_characters(chars: Array) -> Array[Node]`
- `get_local_friendly_characters() -> Array[Node]`
- `get_remote_characters() -> Array[Node]`
- `get_all_character_snapshots() -> Array[SyncState.CharacterSnapshot]`
- `get_character_count() -> int`
- `get_all_characters() -> Array[Node]`
- `has_character(character: Node) -> bool`
- `clear_all() -> void`
