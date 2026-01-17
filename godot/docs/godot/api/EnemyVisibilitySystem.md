# EnemyVisibilitySystem

敵キャラクター可視性管理システム。味方の視界ポリゴンに基づいて敵キャラクターの表示/非表示を制御。

2つの可視性判定モードをサポート:
- **FULL_VISION**: 視界ポリゴンベースの判定（FoW ON時）
- **LIGHTWEIGHT**: 単一レイキャストの軽量判定（FoW OFF時、97%レイ削減）

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/systems/enemy_visibility_system.gd` |
| 依存 | `PlayerState`, `VisionComponent`, `FogOfWarSystem` |

## Enums

### VisibilityMode
可視性判定モード。

| 値 | 説明 |
|----|------|
| `FULL_VISION` | 視界ポリゴンベースの詳細判定（FoW ON時） |
| `LIGHTWEIGHT` | 単一レイキャストの軽量判定（FoW OFF時） |

**パフォーマンス比較（敵10体 × 味方5体）:**
| モード | レイキャスト数/フレーム | 備考 |
|--------|-------------------------|------|
| FULL_VISION | 約2,200本 | 440本×5味方 |
| LIGHTWEIGHT | 50本 | 10敵×5味方 |

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
システムを有効化（`enable_full()`のエイリアス）。

### disable() -> void
システムを無効化（デバッグモード）。全キャラクター表示、全視界をFoWに表示。

### enable_full() -> void
FULL_VISIONモードで有効化（FoW ON時用）。視界ポリゴンベースの詳細判定を使用。

**動作:**
- 全味方VisionComponentを有効化してFoWに登録
- ポリゴンベースの可視性判定を使用

### enable_lightweight() -> void
LIGHTWEIGHTモードで有効化（FoW OFF時用）。単一レイキャストの軽量判定を使用。

**動作:**
- 全VisionComponentのポリゴン計算を停止（disable）
- `VisionComponent.is_position_in_view()`を使用した軽量判定
- 97%のレイキャスト削減

### is_enabled() -> bool
システムが有効かどうかを取得。

**戻り値:** 有効なら `true`

### get_mode() -> VisibilityMode
現在の可視性判定モードを取得。

**戻り値:** `FULL_VISION` または `LIGHTWEIGHT`

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

# FoW状態に応じたモード切替
func _apply_vision_state() -> void:
    if is_fow_enabled:
        enemy_vis.enable_full()      # FoW ON: 詳細モード
    else:
        enemy_vis.enable_lightweight()  # FoW OFF: 軽量モード

# デバッグモード（全員表示）
enemy_vis.disable()

# 可視性変更を監視
enemy_vis.visibility_changed.connect(_on_enemy_visibility_changed)

func _on_enemy_visibility_changed(enemy: Node, is_visible: bool) -> void:
    if is_visible:
        print("Enemy spotted: %s" % enemy.name)
```

## 内部動作

### 可視性判定アルゴリズム

#### FULL_VISIONモード
1. 味方キャラクターのVisionComponentから視界ポリゴンを取得
2. 3Dポリゴンをxz平面に射影して2Dポリゴンに変換
3. `Geometry2D.is_point_in_polygon()`で敵位置が視界内か判定
4. いずれかの味方視界に含まれれば可視

#### LIGHTWEIGHTモード
1. 各敵位置に対して味方ごとに`VisionComponent.is_position_in_view()`を呼び出し
2. 距離・FOV角度・壁遮蔽を1本のレイキャストで判定
3. いずれかの味方視界に含まれれば可視

**注意:** 軽量モードは敵の中心点のみで判定するため、「一部だけ見える」状況は検出不可。

### FoW連携
- FULL_VISIONモード: 味方VisionComponentをFoWに登録
- LIGHTWEIGHTモード: 全VisionComponentをFoWから解除（ポリゴン計算不要）

### 更新タイミング
- **FULL_VISIONモード**: 味方VisionComponentの`vision_updated`シグナル発火時
- **LIGHTWEIGHTモード**: 50ms間隔（20FPS）で自動更新
- PlayerStateのチーム変更時
- `enable_full()`/`enable_lightweight()`/`disable()`呼び出し時

### 最適化
- キャッシュによる変更検出（変化時のみ`visible`を更新）
- シグナル駆動で必要時のみ更新
- LIGHTWEIGHTモードで97%のレイキャスト削減
