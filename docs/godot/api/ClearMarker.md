# ClearMarker

Clearポイントマーカー。円形背景と回転アイコンで「リセット」を示す。このポイント以降はVision/Runがクリアされ、キャラクターは進行方向を向く。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `MeshInstance3D` |
| ファイルパス | `scripts/effects/clear_marker.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `circle_radius` | `float` | `0.3` | 円の半径 |
| `circle_color` | `Color` | 青系(0.2, 0.6, 0.9, 0.95) | 円の背景色 |
| `icon_color` | `Color` | 白(1.0) | アイコンの色 |
| `height_offset` | `float` | `0.03` | 地面からの高さ |
| `segments` | `int` | `32` | 円のセグメント数 |

## Public API

### set_marker_position(pos: Vector3) -> void
マーカーを配置する。

**引数:**
- `pos` - パス上の位置

### set_colors(bg_color: Color, fg_color: Color) -> void
色を変更する。

**引数:**
- `bg_color` - 背景円の色
- `fg_color` - アイコンの色

## 使用例

```gdscript
var marker = MeshInstance3D.new()
marker.set_script(preload("res://scripts/effects/clear_marker.gd"))
add_child(marker)

# 位置を設定
marker.set_marker_position(Vector3(5, 0, 3))

# 色を変更
marker.set_colors(Color.BLUE, Color.WHITE)
```

## 内部動作

### メッシュ構成
1. **塗りつぶし円**: 中心点から放射状に三角形を生成
2. **リセットアイコン**: 円弧（回転矢印風）と矢印の先端

### マテリアル
- 円: `SHADING_MODE_UNSHADED`, `TRANSPARENCY_ALPHA`, `render_priority = 10`
- アイコン: 発光有効（energy 1.2）, `render_priority = 11`

フォグより上にレンダリングされるため、常に視認可能。

## 関連クラス

- `PathDrawer` - Clearマーカー設定モードでClearMarkerを生成
- `PathFollowingController` - Clearポイントで視線・Run状態をリセット
- `CharacterColorManager` - キャラクター個別色の取得
