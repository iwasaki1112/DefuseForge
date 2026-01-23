# VisionComponent

Fog of Warシステム用の視界コンポーネント。等間隔レイキャスト方式で動的障害物（ドア等）にも即時対応する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/characters/vision_component.gd` |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `vision_updated` | `visible_points: PackedVector3Array` | 視界が更新されたとき |

## Enums

### Quality
品質プリセット（FogOfWarSystem.Qualityと連動）。

| 値 | ray_count | update_hz | 説明 |
|----|-----------|-----------|------|
| `LOW` | 36 | 15 | モバイル向け |
| `MEDIUM` | 54 | 20 | バランス |
| `HIGH` | 72 | 30 | PC向け |

## Export Properties

### Vision Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `fov_degrees` | `float` | `90.0` | 視野角（度） |
| `view_distance` | `float` | `15.0` | 視界距離（メートル） |
| `ray_count` | `int` | `36` | FOV範囲のレイ数（等間隔） |
| `eye_height` | `float` | `1.5` | 目の高さ |

### Collision Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `wall_collision_mask` | `int` | `2` | 壁の衝突マスク |

### Debug
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `debug_draw` | `bool` | `false` | デバッグ表示のON/OFF |
| `debug_color` | `Color` | 緑半透明 | 視界コーンの塗りつぶし色 |
| `debug_line_color` | `Color` | 緑 | 視界境界線の色 |
| `debug_hit_color` | `Color` | 赤 | レイキャストヒットポイントの色 |

## Public API

### get_visible_polygon() -> PackedVector3Array
可視ポリゴンを取得する（FogOfWarSystemが使用）。

**戻り値:** 可視領域を表す3D頂点配列

### force_update() -> void
即座に視界を更新する。

### set_quality(q: Quality) -> void
品質プリセットを設定する。

**引数:**
- `q` - 品質レベル（LOW/MEDIUM/HIGH）

### apply_quality_settings(settings: Dictionary) -> void
辞書形式で品質設定を適用する（FogOfWarSystemとの同期用）。

**引数:**
- `settings` - `ray_count`と`update_hz`を含む辞書

### set_fov(degrees: float) -> void
視野角を設定する。

**引数:**
- `degrees` - 視野角（1.0〜360.0度）

### set_view_distance(distance: float) -> void
視界距離を設定する。

**引数:**
- `distance` - 距離（最小1.0メートル）

### disable() -> void
視界を無効化する（死亡時など）。

### enable() -> void
視界を有効化する。

### is_enabled() -> bool
視界が有効か確認する。

**戻り値:** 有効なら`true`

### is_position_in_view(world_pos: Vector3) -> bool
指定位置が視界内か軽量判定する（単一レイキャスト）。EnemyVisibilitySystemの軽量モードで使用。

**引数:**
- `world_pos` - 判定対象のワールド座標

**戻り値:** 視界内なら`true`

**判定ロジック:**
1. 距離チェック（view_distance以内か）
2. FOV角度チェック（XZ平面で視野角内か）
3. 壁遮蔽チェック（1本のレイキャストで障害物がないか）

**使用例:**
```gdscript
# 敵位置が味方視界内かチェック
if friendly.vision.is_position_in_view(enemy.global_position):
    print("Enemy in sight!")
```

### set_debug_draw(enabled: bool) -> void
デバッグ表示を実行時に切り替える。

**引数:**
- `enabled` - trueでデバッグ表示ON

**表示内容:**
- 視界コーン（半透明の扇形）
- FOV境界線（左右の視界端）
- 外周アーク（視界範囲の外縁）
- ヒットポイント（壁との交点に赤い十字）

**使用例:**
```gdscript
# デバッグ表示をON
character.vision.set_debug_draw(true)

# デバッグ表示をOFF
character.vision.set_debug_draw(false)
```

## 使用例

```gdscript
# VisionComponent作成
var vision = VisionComponent.new()
character.add_child(vision)

# 設定
vision.set_fov(90.0)
vision.set_view_distance(15.0)
vision.set_quality(VisionComponent.Quality.HIGH)

# FoWシステムに登録
fog_of_war.register_vision(vision)

# シグナル接続
vision.vision_updated.connect(_on_vision_updated)
```

## 内部動作

### 等間隔レイキャスト方式
1. 視点位置からFOV範囲に等間隔でレイをキャスト
2. 壁・ドア等の障害物との交点を取得
3. 交点で可視ポリゴンを構築
4. `vision_updated`シグナルを発火

**特徴:**
- **動的障害物対応**: 壁コーナーキャッシュを使用しないため、ドア開閉時に即時更新される
- **シンプルな実装**: 等間隔レイキャストのみで視界を計算

### 最適化
- **静止時最適化**: 3フレーム連続で変化なしなら更新間隔を3倍に延長
- **テンポラルスムージング**: 位置・角度を平滑化して歩行揺れを吸収
- **RIDキャッシュ**: キャラクターのRIDをキャッシュしてレイキャスト除外を高速化

### 壁検出

視界を遮る壁として検出されるには、以下の条件を満たす必要がある：

| 条件 | 必須 | 説明 |
|------|------|------|
| `collision_layer` | **2** | `wall_collision_mask`と一致する必要がある |

**検出対象:**
- `collision_layer = 2`のStaticBody3D（GLTFインポート壁）
- `collision_layer = 2`のCSGBox3D
- `collision_layer = 2`のドア（開閉状態も即時反映）

**GLTFマップでの壁設定:**
GLTFからインポートされたStaticBody3Dは`collision_layer`がデフォルト（1）のため、スクリプトで2に変更する必要がある。

```gdscript
# マップスクリプト例（bank.gd）
const WALL_COLLISION_LAYER: int = 2

func _ready() -> void:
    _setup_wall_collisions(self)

func _setup_wall_collisions(node: Node) -> void:
    if node is StaticBody3D:
        var parent = node.get_parent()
        if parent and "wall" in parent.name.to_lower():
            node.collision_layer = WALL_COLLISION_LAYER
    for child in node.get_children():
        _setup_wall_collisions(child)
```

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `vision_updated` | `visible_points: PackedVector3Array` |

### メソッド
- `get_visible_polygon() -> PackedVector3Array`
- `force_update() -> void`
- `set_quality(q: Quality) -> void`
- `apply_quality_settings(settings: Dictionary) -> void`
- `set_fov(degrees: float) -> void`
- `set_view_distance(distance: float) -> void`
- `disable() -> void`
- `enable() -> void`
- `is_enabled() -> bool`
- `is_position_in_view(world_pos: Vector3) -> bool`
- `set_debug_draw(enabled: bool) -> void`
