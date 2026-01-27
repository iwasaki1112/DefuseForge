# GrenadeMarker

パス上のグレネード投擲位置マーカー。円形背景とスターバースト型爆発アイコンで投擲位置を示し、ターゲットへの軌道線を描画する。バウンス投擲にも対応。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `MeshInstance3D` |
| ファイルパス | `scripts/effects/grenade_marker.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `circle_radius` | `float` | `0.3` | 円の半径 |
| `circle_color` | `Color` | 黒系(0.1, 0.1, 0.1, 0.95) | 円の背景色 |
| `icon_color` | `Color` | オレンジ(1.0, 0.5, 0.0, 1.0) | アイコンの色 |
| `height_offset` | `float` | `0.03` | 地面からの高さ |
| `segments` | `int` | `32` | 円のセグメント数 |
| `trajectory_line_color` | `Color` | オレンジ半透明(1.0, 0.5, 0.0, 0.8) | 軌道線の色 |
| `trajectory_line_width` | `float` | `0.02` | 軌道線の太さ |

## Public API

### set_position_and_target(anchor: Vector3, target: Vector3, bounce: Vector3 = Vector3.ZERO) -> void
マーカーを配置してターゲット位置を設定する。

**引数:**
- `anchor` - パス上のアンカー位置（投擲位置）
- `target` - 投擲目標位置
- `bounce` - バウンスポイント（壁に当たる位置、省略可）

### get_target_position() -> Vector3
ターゲット位置を取得する。

**戻り値:** 投擲目標位置

### get_bounce_point() -> Vector3
バウンスポイントを取得する。

**戻り値:** バウンスポイント（設定されていない場合はVector3.ZERO）

### has_bounce_point() -> bool
バウンスポイントが設定されているか確認する。

**戻り値:** バウンスポイントがある場合true

### set_colors(bg_color: Color, fg_color: Color) -> void
マーカーの色を変更する。

**引数:**
- `bg_color` - 背景円の色
- `fg_color` - アイコンの色

### set_trajectory_color(color: Color) -> void
軌道線の色を設定する。

**引数:**
- `color` - 軌道線の色

## 使用例

```gdscript
var marker = GrenadeMarker.new()
add_child(marker)

# 直接投擲（バウンスなし）
marker.set_position_and_target(
    Vector3(5, 0, 3),   # 投擲位置
    Vector3(10, 0, 8)   # 目標位置
)

# バウンス投擲（壁に当てて投げる）
marker.set_position_and_target(
    Vector3(5, 0, 3),   # 投擲位置
    Vector3(12, 0, 10), # 最終目標
    Vector3(8, 1, 6)    # 壁に当たる位置
)

# 色を変更（キャラクター個別色）
marker.set_colors(Color(0.2, 0.2, 0.2), Color.ORANGE)
```

## 内部動作

### メッシュ構成
1. **塗りつぶし円**: 中心点から放射状に三角形を生成
2. **スターバーストアイコン**: 8頂点の星形（爆発を表現）
3. **軌道線**: アンカーからターゲットへの線（バウンスポイント経由可能）
4. **ダイヤモンドマーカー**: ターゲット位置とバウンスポイントを示す

### マテリアル
- 円: `SHADING_MODE_UNSHADED`, `TRANSPARENCY_ALPHA`, `render_priority = 10`
- アイコン: 発光有効（energy 1.2）, `render_priority = 11`
- 軌道線: `render_priority = 9`

フォグより上にレンダリングされるため、常に視認可能。

## 関連クラス

- `PathDrawer` - グレネードマーカー設定モードでGrenadeMarkerを生成
- `PathFollowingController` - マーカー位置到達時にシグナルを発火
- `GameManager` - グレネード投擲を実行
- `Grenade` - 実際のグレネードオブジェクト
- `CharacterColorManager` - キャラクター個別色の取得

## シグナルフロー

```
PathDrawer (grenade_marker_added)
    ↓
PathExecutionManager (confirm_path)
    ↓
PathFollowingController (grenade_marker_reached)
    ↓
GameManager (投擲実行)
```

## APIリファレンス

### シグナル
なし

### メソッド
- `set_position_and_target(anchor: Vector3, target: Vector3, bounce: Vector3 = Vector3.ZERO) -> void`
- `get_target_position() -> Vector3`
- `get_bounce_point() -> Vector3`
- `has_bounce_point() -> bool`
- `set_colors(bg_color: Color, fg_color: Color) -> void`
- `set_trajectory_color(color: Color) -> void`
