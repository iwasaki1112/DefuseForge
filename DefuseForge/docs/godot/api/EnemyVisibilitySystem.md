# EnemyVisibilitySystem

敵キャラクター可視性管理システム。味方の視界ポリゴンに基づいて敵キャラクターの表示/非表示を制御。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/systems/enemy_visibility_system.gd` |
| 依存 | `PlayerState`, `VisionComponent`, `FogOfWarSystem` |

## Signals

### visibility_changed(enemy: Node, is_visible: bool)
敵キャラクターの可視性が変更されたときに発火。

**引数:**
- `enemy` - 可視性が変更された敵キャラクター
- `is_visible` - 新しい可視性状態

## Public API

### setup(fog_of_war: Node3D) -> void
FogOfWarSystemを設定して初期化。PlayerStateのチーム変更シグナルに自動接続。

**引数:**
- `fog_of_war` - FogOfWarSystemインスタンス

### register_character(character: Node) -> void
キャラクターを可視性管理対象として登録。VisionComponentのシグナルに自動接続し、初期可視性を設定。

**引数:**
- `character` - GameCharacterインスタンス

### unregister_character(character: Node) -> void
キャラクターを管理対象から解除。

**引数:**
- `character` - GameCharacterインスタンス

### enable() -> void
システムを有効化（通常ゲームプレイ）。敵は味方視界内のみ表示。

### disable() -> void
システムを無効化（デバッグモード）。全キャラクター表示、全視界をFoWに表示。

### is_enabled() -> bool
システムが有効かどうかを取得。

**戻り値:** 有効なら `true`

### update_visibility() -> void
全敵キャラクターの可視性を再計算して更新。

### is_position_visible(world_pos: Vector3) -> bool
指定位置が味方の視界内かどうかを判定。

**引数:**
- `world_pos` - ワールド座標

**戻り値:** 視界内なら `true`

### get_visibility(character: Node) -> bool
キャラクターのキャッシュされた可視性を取得。

**引数:**
- `character` - 対象キャラクター

**戻り値:** 可視なら `true`

## 使用例

```gdscript
# セットアップ
var enemy_vis = EnemyVisibilitySystem.new()
add_child(enemy_vis)
enemy_vis.setup(fog_of_war_system)

# キャラクター登録
for character in all_characters:
    enemy_vis.register_character(character)

# デバッグモード切替
enemy_vis.disable()  # 全員表示
enemy_vis.enable()   # 通常モード

# 可視性変更を監視
enemy_vis.visibility_changed.connect(_on_enemy_visibility_changed)

func _on_enemy_visibility_changed(enemy: Node, is_visible: bool) -> void:
    if is_visible:
        print("Enemy spotted: %s" % enemy.name)
```

## 内部動作

### 可視性判定アルゴリズム
1. 味方キャラクターのVisionComponentから視界ポリゴンを取得
2. 3Dポリゴンをxz平面に射影して2Dポリゴンに変換
3. `Geometry2D.is_point_in_polygon()`で敵位置が視界内か判定
4. いずれかの味方視界に含まれれば可視

### FoW連携
- 味方キャラクター: FoWに登録して視界を表示
- 敵キャラクター: FoWから解除して視界を非表示

### 更新タイミング
- 味方VisionComponentの`vision_updated`シグナル発火時
- PlayerStateのチーム変更時
- `enable()`/`disable()`呼び出し時

### 最適化
- キャッシュによる変更検出（変化時のみ`visible`を更新）
- シグナル駆動で必要時のみ更新
