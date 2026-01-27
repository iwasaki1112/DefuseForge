# VisionMarker

視線ポイントマーカー。円形背景と矢印で視線方向を示す。ターゲットポイントモードでは、ターゲット地点への線も描画する。

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
| `target_line_color` | `Color` | オレンジ(1.0, 0.5, 0.0, 0.8) | ターゲット線の色 |
| `target_line_width` | `float` | `0.02` | ターゲット線の太さ |

## Public API

### set_position_and_direction(anchor: Vector3, direction: Vector3) -> void
マーカーを配置して固定方向を設定する（後方互換用）。

**引数:**
- `anchor` - パス上のアンカー位置
- `direction` - 視線方向（正規化済み）

### set_position_and_target(anchor: Vector3, target: Vector3) -> void
マーカーを配置してターゲット地点を設定する（ターゲットポイントモード）。
キャラクターはマーカー到達後、移動しながらターゲット地点を見続ける。

**引数:**
- `anchor` - パス上のアンカー位置
- `target` - ターゲット地点（キャラクターがここを見続ける）

### get_target_point() -> Vector3
ターゲット地点を取得する。

**戻り値:** ターゲット地点（ターゲットモードでない場合はVector3.ZERO）

### has_target_point() -> bool
ターゲットポイントモードかどうかを確認する。

**戻り値:** ターゲットポイントが設定されていれば`true`

### set_colors(bg_color: Color, fg_color: Color) -> void
色を変更する。

**引数:**
- `bg_color` - 背景円の色
- `fg_color` - 矢印の色

### set_target_line_color(color: Color) -> void
ターゲット線の色を設定する。

**引数:**
- `color` - ターゲット線の色

## 使用例

### 固定方向モード（後方互換）
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

### ターゲットポイントモード
```gdscript
var marker = MeshInstance3D.new()
marker.set_script(preload("res://scripts/effects/vision_marker.gd"))
add_child(marker)

# 位置とターゲットを設定
marker.set_position_and_target(
    Vector3(5, 0, 3),   # アンカー位置（マーカーの位置）
    Vector3(10, 0, 8)   # ターゲット地点（キャラクターが見続ける位置）
)

# 色を変更
marker.set_colors(Color.BLACK, Color.YELLOW)
marker.set_target_line_color(Color.ORANGE)
```

## 内部動作

### メッシュ構成
1. **塗りつぶし円**: 中心点から放射状に三角形を生成
2. **矢印**: シャフト（縦棒）+ 矢印頭（三角形）
3. **ターゲット線**（ターゲットモード時）: アンカーからターゲットへの線 + ダイヤモンドマーカー

### マテリアル
- 円: `SHADING_MODE_UNSHADED`, `TRANSPARENCY_ALPHA`, `render_priority = 10`
- 矢印: 発光有効（energy 1.2）, `render_priority = 11`
- ターゲット線: `render_priority = 9`（円より下）

フォグより上にレンダリングされるため、常に視認可能。

## 関連クラス

- `PathDrawer` - 視線ポイント設定モードでVisionMarkerを生成
- `CharacterColorManager` - キャラクター個別色の取得
- `PathFollowingController` - ターゲットポイントに基づいて動的に視線方向を計算

## APIリファレンス

### シグナル
なし

### メソッド
- `set_position_and_direction(anchor: Vector3, direction: Vector3) -> void`
- `set_colors(bg_color: Color, fg_color: Color) -> void`
- `set_position_and_target(anchor: Vector3, target: Vector3) -> void`
- `get_target_point() -> Vector3`
- `has_target_point() -> bool`
- `set_target_line_color(color: Color) -> void`
