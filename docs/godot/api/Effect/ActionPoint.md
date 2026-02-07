# ActionPoint

アクションポイントの基底クラス。Vision, Waitポイントの共通機能を提供する。

## 継承

`MeshInstance3D`

## 概要

`ActionPoint`は、パス上に配置されるすべてのアクションポイントの共通ベースクラス。
円形の背景とアイコンを持つポイントの基本的な描画機能とインターフェースを提供する。

## 継承クラス

- `VisionPoint` - 視線方向ポイント
- `WaitPoint` - 待機ポイント

## PointType列挙型

```gdscript
enum PointType {
    VISION,   # 視線ポイント
    CLEAR,    # クリアポイント（未使用）
    RUN,      # ダッシュポイント（未使用）
    DOOR,     # ドアポイント（未使用）
    GRENADE,  # グレネードポイント（未使用）
    WAIT,     # 待機ポイント
    SMOKE_GRENADE # スモークグレネードポイント（未使用）
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

### get_action_point_type() -> PointType

ポイントタイプを取得。子クラスでオーバーライドする。

```gdscript
func get_action_point_type() -> PointType:
    return PointType.VISION
```

### set_point_position(pos: Vector3) -> void

ポイントの位置を設定。

```gdscript
point.set_point_position(Vector3(5, 0, 10))
```

### set_colors(bg_color: Color, fg_color: Color) -> void

背景円とアイコンの色を変更。

```gdscript
point.set_colors(Color.BLUE, Color.WHITE)
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

## 新しいポイントの追加方法

1. `ActionPoint`を継承したクラスを作成
2. `_init()`でデフォルト色を設定
3. `get_action_point_type()`をオーバーライドして適切なタイプを返す
4. `_build_icon()`をオーバーライドしてアイコンを描画
5. 必要に応じて追加のマテリアルを`_setup_mesh()`で作成

```gdscript
class_name MyCustomPoint
extends ActionPoint

func _init() -> void:
    circle_color = Color(0.5, 0.5, 0.5, 0.95)
    icon_color = Color(1.0, 0.0, 0.0, 1.0)

func get_action_point_type() -> PointType:
    return PointType.VISION  # 適切なタイプに変更

func _build_icon() -> void:
    # カスタムアイコンの描画処理
    pass
```

## 使用例

```gdscript
# VisionPointの作成
var vision_point = VisionPoint.new()
add_child(vision_point)
vision_point.set_position_and_direction(anchor_pos, direction)
vision_point.set_colors(Color.BLACK, Color.WHITE)

# ポイントタイプの確認
match point.get_action_point_type():
    ActionPoint.PointType.VISION:
        print("Vision point")
    ActionPoint.PointType.WAIT:
        print("Wait point")
```

## 関連クラス

- `VisionPoint` - 視線ポイント
- `WaitPoint` - 待機ポイント
- `PathDrawer` - ポイントを配置するパス描画システム