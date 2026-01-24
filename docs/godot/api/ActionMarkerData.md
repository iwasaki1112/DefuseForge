# ActionMarkerData

マーカーデータの統一基底クラス。各マーカー種別のデータを統一的に扱うためのデータ構造。

## 継承

`RefCounted`

## 概要

`ActionMarkerData`は、パス上のマーカーデータを統一的に扱うための基底クラス。
各マーカー種別（Vision、Clear、Run、Door、Grenade、Wait）のデータサブクラスを提供する。

## Type列挙型

```gdscript
enum Type {
    VISION,   # 視線マーカー
    CLEAR,    # クリアマーカー
    RUN,      # ダッシュマーカー
    DOOR,     # ドアマーカー
    GRENADE,  # グレネードマーカー
    WAIT      # 待機マーカー
}
```

## 基底クラスプロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `type` | `Type` | マーカータイプ |
| `path_ratio` | `float` | パス上の位置比率 (0.0 ~ 1.0) |
| `anchor` | `Vector3` | アンカー位置 |

## 基底クラスメソッド

### adjust_ratio_for_connection(connect_length, base_length)

比率を接続線を考慮して調整。

### to_dict() -> Dictionary

Dictionaryに変換（シリアライズ用）。

### from_dict(data: Dictionary)

Dictionaryから復元（デシリアライズ用）。

### create_marker_node() -> Node3D

マーカーノードを作成（子クラスでオーバーライド）。

## 静的ファクトリメソッド

### ActionMarkerData.create(marker_type: Type) -> ActionMarkerData

タイプに応じたデータクラスを作成。

```gdscript
var vision_data = ActionMarkerData.create(ActionMarkerData.Type.VISION)
```

### ActionMarkerData.from_dictionary(data: Dictionary) -> ActionMarkerData

Dictionaryからデータクラスを作成。

## サブクラス

### VisionMarkerData

視線マーカーデータ。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `target_point` | `Vector3` | ターゲット地点 |
| `direction` | `Vector3` | 視線方向（後方互換用） |
| `has_target` | `bool` | ターゲットポイントモードかどうか |

### ClearMarkerData

クリアマーカーデータ。基底クラスのプロパティのみ。

### RunMarkerData

ダッシュマーカーデータ。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `start_ratio` | `float` | Run区間の開始比率 |
| `end_ratio` | `float` | Run区間の終了比率 |

### DoorMarkerData

ドアマーカーデータ。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `door_node` | `Node3D` | 対象ドアノード |

### GrenadeMarkerData

グレネードマーカーデータ。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `target_pos` | `Vector3` | 投擲目標位置 |
| `bounce_point` | `Vector3` | バウンスポイント |
| `bounce_normal` | `Vector3` | バウンス法線 |
| `has_bounce` | `bool` | バウンスがあるか |

### WaitMarkerData

待機マーカーデータ。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `wait_duration` | `float` | 待機時間（秒） |

## 使用例

```gdscript
# Visionマーカーデータを作成
var vision = ActionMarkerData.VisionMarkerData.new()
vision.path_ratio = 0.5
vision.anchor = Vector3(5, 0, 10)
vision.target_point = Vector3(10, 0, 10)
vision.has_target = true

# Dictionaryから復元
var dict = { "type": ActionMarkerData.Type.GRENADE, "path_ratio": 0.7, "target_pos": Vector3(8, 0, 5) }
var grenade = ActionMarkerData.from_dictionary(dict)

# マーカーノードを作成
var marker_node = vision.create_marker_node()
```

## 関連クラス

- `ActionMarker` - マーカー表示クラスの基底
- `MarkerCollection` - マーカーコレクション管理
- `PathDrawer` - マーカーを配置するパス描画システム
