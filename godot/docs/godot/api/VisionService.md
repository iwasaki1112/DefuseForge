# VisionService

## 概要

視界/FoW/敵可視性の統合サービス。FogOfWarSystemとEnemyVisibilitySystemの初期化と切替を担当する。

## クラス情報

- **継承**: `Node`
- **ファイル**: `scripts/systems/vision_service.gd`

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `fog_of_war_system` | `Node3D` | FogOfWarSystem参照 |
| `enemy_visibility_system` | `Node` | EnemyVisibilitySystem参照 |
| `is_vision_enabled` | `bool` | 視界システムの有効/無効 |

## メソッド

### `setup(map_size: Vector2, vision_enabled: bool) -> void`
FogOfWarSystemとEnemyVisibilitySystemを生成して初期化する。

### `set_enabled(enabled: bool) -> void`
FoW表示と敵可視性モードを切り替える。

### `unregister_character(character: Node) -> void`
キャラクターを視界システムから解除する。

## 関連クラス

- [GameManager](GameManager.md)
- [FogOfWarSystem](FogOfWarSystem.md)
- [EnemyVisibilitySystem](EnemyVisibilitySystem.md)
