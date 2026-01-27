# DoorMarker

パス上のドアキック位置マーカー。円形背景とドアアイコンでキック位置を示し、対象ドアへの接続線を描画する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `MeshInstance3D` |
| ファイルパス | `scripts/effects/door_marker.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `circle_radius` | `float` | `0.3` | 円の半径 |
| `circle_color` | `Color` | 黒系(0.1, 0.1, 0.1, 0.95) | 円の背景色 |
| `icon_color` | `Color` | ブラウン(0.8, 0.6, 0.3, 1.0) | アイコンの色 |
| `height_offset` | `float` | `0.03` | 地面からの高さ |
| `segments` | `int` | `32` | 円のセグメント数 |
| `connection_line_color` | `Color` | ブラウン半透明(0.8, 0.6, 0.3, 0.8) | 接続線の色 |
| `connection_line_width` | `float` | `0.02` | 接続線の太さ |

## Public API

### set_position_and_door(anchor: Vector3, door: Node3D) -> void
マーカーを配置して対象ドアを設定する。

**引数:**
- `anchor` - パス上のアンカー位置（キック位置）
- `door` - 対象ドアのNode3D

### get_door_node() -> Node3D
対象ドアノードを取得する。

**戻り値:** ドアノード（設定されていない場合はnull）

### get_door_position() -> Vector3
ドアの位置を取得する。

**戻り値:** ドアのグローバル位置

### set_colors(bg_color: Color, fg_color: Color) -> void
マーカーの色を変更する。

**引数:**
- `bg_color` - 背景円の色
- `fg_color` - アイコンの色

### set_connection_color(color: Color) -> void
接続線の色を設定する。

**引数:**
- `color` - 接続線の色

## 使用例

```gdscript
var marker = DoorMarker.new()
add_child(marker)

# ドアマーカーを設定
var door = get_node("Door1")
marker.set_position_and_door(
    Vector3(5, 0, 3),  # キック位置（ドアの手前0.6m）
    door               # 対象ドア
)

# 色を変更（キャラクター個別色）
marker.set_colors(Color(0.2, 0.2, 0.2), Color(0.8, 0.6, 0.3))
```

## 内部動作

### メッシュ構成
1. **塗りつぶし円**: 中心点から放射状に三角形を生成
2. **ドアアイコン**: 長方形の枠 + 取っ手
3. **接続線**: マーカーからドアへの線
4. **ダイヤモンドマーカー**: ドア位置を示す

### マテリアル
- 円: `SHADING_MODE_UNSHADED`, `TRANSPARENCY_ALPHA`, `render_priority = 10`
- アイコン: 発光有効（energy 1.2）, `render_priority = 11`
- 接続線: `render_priority = 9`

フォグより上にレンダリングされるため、常に視認可能。

### マーカー配置ロジック
ドアを選択すると、PathDrawerがパス上の最も近いポイントを探し、そこからドア方向に0.6mオフセットした位置にマーカーを配置する。これによりキャラクターはドアから適切な距離で停止する。

## 関連クラス

- `PathDrawer` - ドアマーカー設定モードでDoorMarkerを生成
- `PathFollowingController` - マーカー位置到達時にシグナルを発火し一時停止
- `GameManager` - ドアキックを実行し、完了後にパス追従を再開

## シグナルフロー

```
PathDrawer (door_marker_added)
    ↓
PathExecutionManager (confirm_path)
    ↓
PathFollowingController (door_marker_reached, 一時停止)
    ↓
GameManager (ドアキック実行)
    ↓
PathFollowingController (resume_after_door, パス再開)
```

## APIリファレンス

### シグナル
なし

### メソッド
- `set_position_and_door(anchor: Vector3, door: Node3D) -> void`
- `get_door_node() -> Node3D`
- `get_door_position() -> Vector3`
- `set_colors(bg_color: Color, fg_color: Color) -> void`
- `set_connection_color(color: Color) -> void`
