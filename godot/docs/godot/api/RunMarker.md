# RunMarker

Run区間の開始/終点を示すマーカー。開始点は三角再生アイコン、終点は四角停止アイコンで表示。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `MeshInstance3D` |
| ファイルパス | `scripts/effects/run_marker.gd` |

## Enums

### MarkerType
マーカーの種類。

| 値 | 説明 |
|----|------|
| `START` | Run区間の開始点（オレンジ色、三角再生アイコン） |
| `END` | Run区間の終点（赤オレンジ色、四角停止アイコン） |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `circle_radius` | `float` | `0.3` | 円の半径 |
| `start_color` | `Color` | オレンジ(1.0, 0.5, 0.0, 0.95) | 開始点の背景色 |
| `end_color` | `Color` | 赤オレンジ(0.9, 0.3, 0.1, 0.95) | 終点の背景色 |
| `icon_color` | `Color` | 白(1.0) | アイコンの色 |
| `height_offset` | `float` | `0.03` | 地面からの高さ |
| `segments` | `int` | `32` | 円のセグメント数 |

## Public API

### set_position_and_type(pos: Vector3, type: MarkerType) -> void
マーカーを配置してタイプを設定する。

**引数:**
- `pos` - パス上の位置
- `type` - `MarkerType.START` または `MarkerType.END`

### get_marker_type() -> MarkerType
現在のマーカータイプを取得する。

### set_colors(bg_color: Color, fg_color: Color) -> void
マーカーの色を変更する。キャラクター個別色を適用する際に使用。

**引数:**
- `bg_color` - 背景円の色
- `fg_color` - アイコンの色

```gdscript
# キャラクター色を適用
var char_color = CharacterColorManager.get_character_color(character)
marker.set_colors(char_color, Color.WHITE)
```

## 使用例

```gdscript
var marker = MeshInstance3D.new()
marker.set_script(preload("res://scripts/effects/run_marker.gd"))
add_child(marker)

# 開始点を設置
marker.set_position_and_type(
    Vector3(5, 0, 3),
    RunMarker.MarkerType.START
)

# 終点に変更
marker.set_position_and_type(
    Vector3(10, 0, 3),
    RunMarker.MarkerType.END
)
```

## 内部動作

### メッシュ構成
1. **塗りつぶし円**: 中心点から放射状に三角形を生成
2. **アイコン**: タイプに応じて三角形（再生）または四角形（停止）

### マテリアル
- 円: `SHADING_MODE_UNSHADED`, `TRANSPARENCY_ALPHA`, `render_priority = 10`
- アイコン: 発光有効（energy 1.2）, `render_priority = 10`

フォグより上にレンダリングされるため、常に視認可能。

## 関連クラス

- `PathDrawer` - Run区間設定モードでRunMarkerを生成
- `PathFollowingController` - Run区間内で走行速度を適用
- `CharacterColorManager` - キャラクター個別色の取得
