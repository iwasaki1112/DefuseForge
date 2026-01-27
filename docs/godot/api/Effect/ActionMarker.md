# ActionMarker

アクションマーカーの基底クラス。Vision, Clear, Run, Door, Grenadeマーカーの共通機能を提供する。

## 継承

`MeshInstance3D`

## 概要

`ActionMarker`は、パス上に配置されるすべてのアクションマーカーの共通ベースクラス。
円形の背景とアイコンを持つマーカーの基本的な描画機能とインターフェースを提供する。

## 継承クラス

- `VisionMarker` - 視線方向マーカー
- `ClearMarker` - クリアポイントマーカー
- `RunMarker` - ダッシュ区間マーカー
- `DoorMarker` - ドアキックマーカー
- `GrenadeMarker` - グレネード投擲マーカー
- `WaitMarker` - 待機マーカー

## MarkerType列挙型

```gdscript
enum MarkerType {
    VISION,   # 視線マーカー
    CLEAR,    # クリアマーカー
    RUN,      # ダッシュマーカー
    DOOR,     # ドアマーカー
    GRENADE,  # グレネードマーカー
    WAIT      # 待機マーカー
}
```

## エクスポートプロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `circle_radius` | `float` | `0.3` | 円の半径 |
| `circle_color` | `Color` | `Color(0.1, 0.1, 0.1, 0.95)` | 円の背景色 |
| `icon_color` | `Color` | `Color(1.0, 1.0, 1.0, 1.0)` | アイコンの色 |
| `height_offset` | `float` | `0.03` | 地面からの高さ |
| `segments` | `int` | `32` | 円のセグメント数 |

## 内部変数

| 変数 | 型 | 説明 |
|-----|-----|------|
| `_array_mesh` | `ArrayMesh` | メッシュデータ |
| `_circle_material` | `StandardMaterial3D` | 円のマテリアル |
| `_icon_material` | `StandardMaterial3D` | アイコンのマテリアル |

## 公開メソッド

### get_action_marker_type() -> MarkerType

マーカータイプを取得。子クラスでオーバーライドする。

```gdscript
func get_action_marker_type() -> MarkerType:
    return MarkerType.VISION
```

### set_marker_position(pos: Vector3) -> void

マーカーの位置を設定。

```gdscript
marker.set_marker_position(Vector3(5, 0, 10))
```

### set_colors(bg_color: Color, fg_color: Color) -> void

背景円とアイコンの色を変更。

```gdscript
marker.set_colors(Color.BLUE, Color.WHITE)
```

## 保護メソッド（子クラスで使用）

### _setup_mesh() -> void

メッシュとマテリアルの初期化。`_ready()`から呼ばれる。
子クラスでオーバーライド時は`super._setup_mesh()`を呼ぶこと。

### _create_circle_material() -> StandardMaterial3D

円のマテリアルを作成。

### _create_icon_material() -> StandardMaterial3D

アイコンのマテリアルを作成（発光あり）。

### _build_mesh() -> void

メッシュを構築。デフォルトでは`_build_filled_circle()`と`_build_icon()`を呼ぶ。
子クラスでオーバーライド可能。

### _build_filled_circle() -> void

塗りつぶし円を構築。共通実装。

### _build_icon() -> void

アイコンを構築。子クラスでオーバーライドする。

## 新しいマーカーの追加方法

1. `ActionMarker`を継承したクラスを作成
2. `_init()`でデフォルト色を設定
3. `get_action_marker_type()`をオーバーライドして適切なタイプを返す
4. `_build_icon()`をオーバーライドしてアイコンを描画
5. 必要に応じて追加のマテリアルを`_setup_mesh()`で作成

```gdscript
class_name MyCustomMarker
extends ActionMarker

func _init() -> void:
    circle_color = Color(0.5, 0.5, 0.5, 0.95)
    icon_color = Color(1.0, 0.0, 0.0, 1.0)

func get_action_marker_type() -> MarkerType:
    return MarkerType.VISION  # 適切なタイプに変更

func _build_icon() -> void:
    # カスタムアイコンの描画処理
    pass
```

## 使用例

```gdscript
# VisionMarkerの作成
var vision_marker = VisionMarker.new()
add_child(vision_marker)
vision_marker.set_position_and_direction(anchor_pos, direction)
vision_marker.set_colors(Color.BLACK, Color.WHITE)

# マーカータイプの確認
match marker.get_action_marker_type():
    ActionMarker.MarkerType.VISION:
        print("Vision marker")
    ActionMarker.MarkerType.GRENADE:
        print("Grenade marker")
```

## 関連クラス

- `VisionMarker` - 視線マーカー
- `ClearMarker` - クリアマーカー
- `RunMarker` - ダッシュマーカー
- `DoorMarker` - ドアマーカー
- `GrenadeMarker` - グレネードマーカー
- `WaitMarker` - 待機マーカー
- `PathDrawer` - マーカーを配置するパス描画システム
