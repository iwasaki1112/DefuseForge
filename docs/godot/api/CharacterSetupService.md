# CharacterSetupService

## 概要

キャラクターの初期セットアップ（視界・戦闘認識・武器装備・色/ラベル付与）をまとめて担当する。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/systems/character_setup_service.gd`

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `enemy_visibility_system` | `Node` | 敵可視性システム参照 |
| `fog_of_war_system` | `Node3D` | FoWシステム参照 |
| `label_manager` | `CharacterLabelManager` | ラベル管理 |
| `default_weapon_id` | `String` | 初期武器ID |
| `is_vision_enabled` | `bool` | 視界システムの有効/無効 |
| `default_vision_fov` | `float` | 視界FOV |
| `default_vision_range` | `float` | 視界距離 |

## メソッド

### `setup(visibility_system, fow_system, label_mgr, weapon_id, vision_enabled, vision_fov, vision_range) -> void`
依存システムと初期設定を登録する。

### `setup_character(character: Node) -> void`
キャラクターの視界/戦闘/武器/色を初期化する。

### `assign_color_and_label(character: Node) -> void`
キャラクターの色とラベルを付与する。

## 関連クラス

- [GameManager](GameManager.md)
- [CharacterLabelManager](CharacterLabelManager.md)
- [EnemyVisibilitySystem](EnemyVisibilitySystem.md)
- [FogOfWarSystem](FogOfWarSystem.md)

## APIリファレンス

### シグナル
なし

### メソッド
- `setup(`
- `setup_character(character: Node) -> void`
- `assign_color_and_label(character: Node) -> void`
