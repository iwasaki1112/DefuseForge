# VisionService

## 概要

視界/FoW/敵可視性の統合サービス。FogOfWarSystemとEnemyVisibilitySystemの初期化と切替を担当する。

## クラス情報

- **継承**: `Node`
- **クラス名**: `VisionService`
- **ファイル**: `scripts/systems/vision_service.gd`

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `fog_of_war_system` | `Node3D` | FogOfWarSystem参照 |
| `enemy_visibility_system` | `Node` | EnemyVisibilitySystem参照 |
| `is_vision_enabled` | `bool` | 視界システムの有効/無効 |
| `_smoke_area_manager` | `SmokeAreaManager` | スモークエリアマネージャ参照（内部） |
| `_debug_draw_enabled` | `bool` | デバッグ表示有効フラグ（内部） |
| `_registered_visions` | `Array` | 登録済みVisionComponentの追跡リスト（内部） |

## メソッド

### `setup(map_size: Vector2, vision_enabled: bool) -> void`
FogOfWarSystemとEnemyVisibilitySystemを生成して初期化する。

### `set_enabled(enabled: bool) -> void`
FoW表示と敵可視性モードを切り替える。
- `true`: FoW表示 + EnemyVisibilitySystem `enable_full()`
- `false`: FoW非表示 + EnemyVisibilitySystem `enable_lightweight()`

### `register_character(character: Node) -> void`
キャラクターのVisionComponentをFoWとEnemyVisibilitySystemに登録する。味方キャラクターのみFoWに登録される。デバッグ表示が有効な場合は自動適用。

### `unregister_character(character: Node) -> void`
キャラクターを視界システムから解除する。

### `set_smoke_area_manager(manager: SmokeAreaManager) -> void`
SmokeAreaManagerを設定する。EnemyVisibilitySystemにも連携し、スモークエリアの追加/削除シグナルを接続する。

### `extract_occluders_from_map(map_node: Node3D) -> void`
マップからFoWオクルーダーを抽出する。FogOfWarSystemに委譲。

### `set_door_open(door: Node3D, is_open: bool) -> void`
ドアオクルーダーの有効/無効を切り替える。ドアが開いた場合はオクルーダーを無効化し、FoWの遮蔽を解除する。

### `set_debug_draw(enabled: bool) -> void`
味方キャラクターの視界デバッグ表示（視界コーン描画）を切り替える。登録済みの全VisionComponentに適用。

### `is_debug_draw_enabled() -> bool`
デバッグ表示が有効かどうかを返す。

## 関連クラス

- [GameManager](GameManager.md)
- [FogOfWarSystem](FogOfWarSystem.md)
- [EnemyVisibilitySystem](EnemyVisibilitySystem.md)
- [SmokeAreaManager](SmokeAreaManager.md)

## APIリファレンス

### シグナル
なし

### メソッド
- `setup(map_size: Vector2, vision_enabled: bool) -> void`
- `set_enabled(enabled: bool) -> void`
- `register_character(character: Node) -> void`
- `unregister_character(character: Node) -> void`
- `set_smoke_area_manager(manager: SmokeAreaManager) -> void`
- `extract_occluders_from_map(map_node: Node3D) -> void`
- `set_door_open(door: Node3D, is_open: bool) -> void`
- `set_debug_draw(enabled: bool) -> void`
- `is_debug_draw_enabled() -> bool`
