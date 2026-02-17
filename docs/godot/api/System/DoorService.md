# DoorService

ドア管理サービス。ドアID管理・キック処理・ネットワーク同期を一元管理。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `DoorService` |
| ファイルパス | `scripts/systems/door_service.gd` |
| 抽出元 | GameManager |

## 概要

GameManagerから抽出されたドア管理コンポーネント。ドアの登録・ID管理、キック処理、ネットワーク同期を担当する。

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `door_kick_network_event` | `door_id: int, character_network_id: int` | ドアキック時のネットワークイベント |
| `door_open_network_event` | `door_id: int, character_network_id: int` | ドア開け（静か）時のネットワークイベント |
| `door_opened` | `door: Node3D, character: Node` | ドア開き処理開始時 |

## メソッド

### setup(character_manager: CharacterManagerService) -> void
セットアップ。CharacterManagerServiceへの参照を設定する。

### set_multiplayer_mode(enabled: bool) -> void
マルチプレイヤーモードを設定する。

### set_vision_update_callback(callback: Callable) -> void
ドア開閉時の視界更新コールバックを設定する。

### register_door(door: Node3D) -> int
ドアを登録し、一意のIDを割り当てる。

### get_door_by_id(door_id: int) -> Node3D
ドアIDからドアノードを取得する。

### get_door_id(door: Node3D) -> int
ドアノードからドアIDを取得する。

### clear_door_registry() -> void
全ドアを登録解除する。

### register_all_doors_in_map() -> void
マップ内の全ドアを"doors"グループから取得して登録する。

### on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void
ドアキックインパクト時の処理。ローカルキャラクターのキックならネットワークイベントを送信し、ドアを開く。

### open_door(door: Node3D, character: CharacterBody3D) -> void
ドアを開く処理（ローカル・リモート共通）。キャラクター位置からドアの開く方向を自動判定し、Tweenアニメーションで回転させる。開く前に壁との衝突スイープテストを行い、最大開角度を自動制限する。

### apply_door_kick_from_network(door_id: int, character_network_id: int) -> void
ネットワークからのドアキックイベントを適用する（リモート側用）。

### on_door_open_done(door: Node3D, character: CharacterBody3D) -> void
ドア開けインパクト時の処理。ローカルキャラクターの開けならネットワークイベントを送信し、ドアを静かに開く。

### open_door_quietly(door: Node3D, character: CharacterBody3D) -> void
ドアを静かに開く処理。キックと異なり、160°回転・0.8秒・EASE_IN_OUTで穏やかに開く。開く前に壁との衝突スイープテストを行い、最大開角度を自動制限する。

### apply_door_open_from_network(door_id: int, character_network_id: int) -> void
ネットワークからのドア開けイベントを適用する（リモート側用）。

### get_registered_door_count() -> int
登録されているドア数を取得する。

### is_door_open(door: Node3D) -> bool
ドアが開いているか確認する。

## 使用例

```gdscript
# GameSystemFactory経由で生成
var door_service = factory.create_door_service(character_manager, _force_update_all_vision)

# ドアキック処理
door_service.on_door_kick_done(door, character)

# ドア開け処理（静かに）
door_service.on_door_open_done(door, character)

# ネットワーク同期
door_service.door_kick_network_event.connect(_on_door_kick_network_event)
door_service.door_open_network_event.connect(_on_door_open_network_event)
```

## 関連クラス

- [GameManager](GameManager.md) - 使用者
- [CharacterManagerService](CharacterManagerService.md) - キャラクター検索（ネットワーク同期用）
- [GameSystemFactory](GameSystemFactory.md) - 生成元

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `door_kick_network_event` | `door_id: int, character_network_id: int` |
| `door_open_network_event` | `door_id: int, character_network_id: int` |
| `door_opened` | `door: Node3D, character: Node` |

### メソッド
- `setup(character_manager: CharacterManagerService) -> void`
- `set_multiplayer_mode(enabled: bool) -> void`
- `set_vision_update_callback(callback: Callable) -> void`
- `register_door(door: Node3D) -> int`
- `get_door_by_id(door_id: int) -> Node3D`
- `get_door_id(door: Node3D) -> int`
- `clear_door_registry() -> void`
- `register_all_doors_in_map() -> void`
- `on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void`
- `open_door(door: Node3D, character: CharacterBody3D) -> void`
- `on_door_open_done(door: Node3D, character: CharacterBody3D) -> void`
- `open_door_quietly(door: Node3D, character: CharacterBody3D) -> void`
- `apply_door_kick_from_network(door_id: int, character_network_id: int) -> void`
- `apply_door_open_from_network(door_id: int, character_network_id: int) -> void`
- `get_registered_door_count() -> int`
- `is_door_open(door: Node3D) -> bool`
