# GrenadeService

グレネード管理サービス。グレネードの生成・投擲・ネットワーク同期を一元管理。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `GrenadeService` |
| ファイルパス | `scripts/systems/grenade_service.gd` |
| 抽出元 | GameManager |

## 概要

GameManagerから抽出されたグレネード管理コンポーネント。通常グレネードとスモークグレネードの生成・投擲、ネットワーク同期（リモートスポーン・爆発位置同期）を担当する。

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `grenade_thrown` | `grenade: Node3D, character: Node` | グレネード投擲時 |
| `smoke_grenade_thrown` | `smoke_grenade: Node3D, character: Node` | スモークグレネード投擲時 |
| `grenade_network_event` | `start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int` | グレネード投擲ネットワークイベント |
| `grenade_explode_network_event` | `grenade_id: int, position: Vector3, is_smoke: bool` | グレネード爆発ネットワークイベント |

## メソッド

### setup(mesh_parent: Node3D, smoke_area_manager: SmokeAreaManager) -> void
セットアップ。グレネードの親ノードとスモークエリアマネージャーを設定する。

### set_smoke_area_manager(manager: SmokeAreaManager) -> void
スモークエリアマネージャーを設定する。

### set_fow_system(fow) -> void
FogOfWarSystemを設定する（リモートグレネードのFoW可視性チェック用）。

### spawn_and_throw_grenade(start_pos: Vector3, target_pos: Vector3, thrower: Node3D) -> Array
グレネードを生成して投擲する。戻り値: `[grenade, velocity, grenade_id]`

### spawn_and_throw_smoke_grenade(start_pos: Vector3, target_pos: Vector3, thrower: Node3D) -> Array
スモークグレネードを生成して投擲する。戻り値: `[smoke_grenade, velocity, grenade_id]`

### spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void
ネットワークからグレネードをスポーンする（リモート用）。

### spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void
ネットワークからスモークグレネードをスポーンする（リモート用）。

### handle_grenade_explode_from_network(grenade_id: int, position: Vector3, is_smoke: bool) -> void
ネットワークからの爆発イベントを処理する（リモートグレネード用）。

### emit_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int) -> void
ネットワークイベントを発火する（グレネード投擲）。

### get_active_grenade_count() -> int
アクティブなグレネード数を取得する。

### clear_all() -> void
全グレネードをクリアする。

## 使用例

```gdscript
# GameSystemFactory経由で生成
var grenade_service = factory.create_grenade_service(mesh_parent, smoke_area_manager)

# グレネード投擲
var result = grenade_service.spawn_and_throw_grenade(start_pos, target_pos, thrower)
var grenade = result[0]
var velocity = result[1]
var grenade_id = result[2]

# ネットワーク同期
grenade_service.grenade_network_event.connect(_on_grenade_network_event)
```

## 関連クラス

- [GameManager](GameManager.md) - 使用者
- [SmokeAreaManager](SmokeAreaManager.md) - スモークエリア管理
- [GameSystemFactory](GameSystemFactory.md) - 生成元

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `grenade_thrown` | `grenade: Node3D, character: Node` |
| `smoke_grenade_thrown` | `smoke_grenade: Node3D, character: Node` |
| `grenade_network_event` | `start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int` |
| `grenade_explode_network_event` | `grenade_id: int, position: Vector3, is_smoke: bool` |

### メソッド
- `setup(mesh_parent: Node3D, smoke_area_manager: SmokeAreaManager) -> void`
- `set_smoke_area_manager(manager: SmokeAreaManager) -> void`
- `set_fow_system(fow) -> void`
- `spawn_and_throw_grenade(start_pos: Vector3, target_pos: Vector3, thrower: Node3D) -> Array`
- `spawn_and_throw_smoke_grenade(start_pos: Vector3, target_pos: Vector3, thrower: Node3D) -> Array`
- `spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void`
- `spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void`
- `handle_grenade_explode_from_network(grenade_id: int, position: Vector3, is_smoke: bool) -> void`
- `emit_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int) -> void`
- `get_active_grenade_count() -> int`
- `clear_all() -> void`
