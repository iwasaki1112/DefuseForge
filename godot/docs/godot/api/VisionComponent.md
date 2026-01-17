# VisionComponent

Fog of Warシステム用の視界コンポーネント。シャドウキャスト法を使用して安定した可視性計算を行う。

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
品質プリセット。

| 値 | ray_count | update_interval | corner_rays | 説明 |
|----|-----------|-----------------|-------------|------|
| `LOW` | 45 | 0.05 | 1 | モバイル向け |
| `MEDIUM` | 90 | 0.033 | 3 | バランス |
| `HIGH` | 180 | 0.033 | 5 | PC向け |

## Export Properties

### Vision Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `fov_degrees` | `float` | `90.0` | 視野角（度） |
| `view_distance` | `float` | `15.0` | 視界距離（メートル） |
| `edge_ray_count` | `int` | `90` | FOVエッジ用レイ数 |
| `update_interval` | `float` | `0.033` | 更新間隔（秒） |
| `eye_height` | `float` | `1.5` | 目の高さ |
| `corner_extra_rays` | `int` | `3` | コーナーごとの追加レイ数 |

### Collision Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `wall_collision_mask` | `int` | `2` | 壁の衝突マスク |

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

### シャドウキャスト法
1. 視点位置からFOV範囲にレイをキャスト
2. 壁コーナーに向けて追加レイをキャスト（影のエッジ精度向上）
3. ヒットポイントで可視ポリゴンを構築

### 最適化
- **壁コーナーキャッシュ**: 1秒間隔で再構築
- **静止時最適化**: 3フレーム連続で変化なしなら100ms間隔に
- **角度スナップ**: 0.5度単位でスナップしてフリッカー防止
- **テンポラルスムージング**: 位置・角度を平滑化して歩行揺れを吸収

### 壁検出
- `"walls"`グループのStaticBody3D（BoxShape3D）
- collision_layer 2のCSGBox3D
