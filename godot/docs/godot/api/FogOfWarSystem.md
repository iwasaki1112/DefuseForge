# FogOfWarSystem

Fog of Warシステム。SubViewportテクスチャ方式で可視領域を描画し、シェーダーでフォグを表示。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/systems/fog_of_war_system.gd` |

## Enums

### Quality
品質設定。

| 値 | resolution | msaa | 説明 |
|----|-----------|------|------|
| `LOW` | 512 | DISABLED | モバイル向け |
| `MEDIUM` | 1024 | 2X | バランス |
| `HIGH` | 2048 | 4X | PC向け |

## Export Properties

### Map Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `map_size` | `Vector2` | `(40, 40)` | マップサイズ |
| `fog_height` | `float` | `0.02` | フォグの高さ |

### Visual Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `fog_color` | `Color` | 暗青(0.85 alpha) | フォグの色 |
| `quality` | `Quality` | `HIGH` | 品質設定 |

## Public API

### register_vision(vision: VisionComponent) -> void
VisionComponentを登録する。

**引数:**
- `vision` - VisionComponentインスタンス

### unregister_vision(vision: VisionComponent) -> void
VisionComponentを解除する。

**引数:**
- `vision` - VisionComponentインスタンス

### set_fog_visible(fog_visible: bool) -> void
フォグの表示/非表示を切り替える。

### set_fog_color(color: Color) -> void
フォグの色を設定する。

### get_visibility_texture() -> ViewportTexture
可視性テクスチャを取得する（壁の照明などに使用可能）。

**戻り値:** ViewportTextureまたは`null`

### force_update() -> void
強制的に可視性テクスチャを更新する。VisionComponentの再登録後などに使用。

## 使用例

```gdscript
# FoWシステム作成
var fow = FogOfWarSystem.new()
fow.map_size = Vector2(50, 50)
fow.quality = FogOfWarSystem.Quality.HIGH
add_child(fow)

# VisionComponent登録
var vision = character.setup_vision(90.0, 15.0)
fow.register_vision(vision)

# 色変更
fow.set_fog_color(Color(0.1, 0.1, 0.2, 0.9))

# 非表示
fow.set_fog_visible(false)
```

## 内部動作

### アーキテクチャ
1. **SubViewport**: 可視領域を白、不可視領域を黒で描画
2. **Polygon2D**: 各VisionComponentの可視ポリゴンを2Dに変換して描画
3. **PlaneMesh + Shader**: SubViewportテクスチャをサンプリングしてフォグを表示

### シェーダー処理
1. ワールド座標をUV座標に変換
2. 3x3 Gaussianブラーでエッジを滑らかに
3. `smoothstep(0.45, 0.55, ...)`で自然なグラデーション
4. 可視領域は透明、不可視領域はフォグ色

### 最適化
- **シグナル駆動**: `vision_updated`シグナルで変更時のみ更新
- **手動レンダリング**: `UPDATE_ONCE`モードで必要時のみ描画
- **複数視界対応**: 複数のVisionComponentを同時に処理可能
