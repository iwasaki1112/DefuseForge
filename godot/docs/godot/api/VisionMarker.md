# VisionMarker

視線ポイントマーカー。円形背景と矢印で視線方向を示す。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `MeshInstance3D` |
| ファイルパス | `scripts/effects/vision_marker.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `circle_radius` | `float` | `0.3` | 円の半径 |
| `circle_color` | `Color` | 暗灰色(0.1, 0.1, 0.1, 0.95) | 円の背景色 |
| `arrow_color` | `Color` | 白(1.0) | 矢印の色 |
| `arrow_thickness` | `float` | `0.04` | 矢印の太さ |
| `height_offset` | `float` | `0.03` | 地面からの高さ |
| `segments` | `int` | `32` | 円のセグメント数 |

## Public API

### set_position_and_direction(anchor: Vector3, direction: Vector3) -> void
マーカーを配置して方向を設定する。

**引数:**
- `anchor` - パス上のアンカー位置
- `direction` - 視線方向（正規化済み）

### set_colors(bg_color: Color, fg_color: Color) -> void
色を変更する。

**引数:**
- `bg_color` - 背景円の色
- `fg_color` - 矢印の色

## 使用例

```gdscript
var marker = MeshInstance3D.new()
marker.set_script(preload("res://scripts/effects/vision_marker.gd"))
add_child(marker)

# 位置と方向を設定
marker.set_position_and_direction(
    Vector3(5, 0, 3),          # アンカー位置
    Vector3(1, 0, 0).normalized()  # 視線方向
)

# 色を変更
marker.set_colors(Color.BLACK, Color.YELLOW)
```

## 内部動作

### メッシュ構成
1. **塗りつぶし円**: 中心点から放射状に三角形を生成
2. **矢印**: シャフト（縦棒）+ 矢印頭（三角形）

### マテリアル
- 円: `SHADING_MODE_UNSHADED`, `TRANSPARENCY_ALPHA`, `render_priority = 10`
- 矢印: 発光有効（energy 1.2）, `render_priority = 10`

フォグより上にレンダリングされるため、常に視認可能。

## 関連クラス

- `PathDrawer` - 視線ポイント設定モードでVisionMarkerを生成
- `CharacterColorManager` - キャラクター個別色の取得
