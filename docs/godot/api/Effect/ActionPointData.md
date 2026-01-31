# ActionPointData

ポイントデータの統一基底クラス。各ポイント種別のデータを統一的に扱うためのデータ構造。

## 継承

`RefCounted`

## 概要

`ActionPointData`は、パス上のポイントデータを統一的に扱うための基底クラス。
各ポイント種別（Vision、Wait）のデータサブクラスを提供する。

## Type列挙型

```gdscript
enum Type {
    VISION,   # 視線ポイント
    WAIT      # 待機ポイント
}
```

## 基底クラスプロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `type` | `Type` | ポイントタイプ |
| `path_ratio` | `float` | パス上の位置比率 (0.0 ~ 1.0) |
| `anchor` | `Vector3` | アンカー位置 |

## 基底クラスメソッド

### adjust_ratio_for_connection(connect_length, base_length)

比率を接続線を考慮して調整。

### to_dict() -> Dictionary

Dictionaryに変換（シリアライズ用）。

### from_dict(data: Dictionary)

Dictionaryから復元（デシリアライズ用）。

### create_point_node() -> Node3D

ポイントノードを作成（子クラスでオーバーライド）。

## 静的ファクトリメソッド

### ActionPointData.create(point_type: Type) -> ActionPointData

タイプに応じたデータクラスを作成。

```gdscript
var vision_data = ActionPointData.create(ActionPointData.Type.VISION)
```

### ActionPointData.from_dictionary(data: Dictionary) -> ActionPointData

Dictionaryからデータクラスを作成。

## サブクラス

### VisionPointData

視線ポイントデータ。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `target_point` | `Vector3` | ターゲット地点 |
| `direction` | `Vector3` | 視線方向（後方互換用） |
| `has_target` | `bool` | ターゲットポイントモードかどうか |

### WaitPointData

待機ポイントデータ。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `wait_duration` | `float` | 待機時間（秒） |

## 使用例

```gdscript
# Visionポイントデータを作成
var vision = ActionPointData.VisionPointData.new()
vision.path_ratio = 0.5
vision.anchor = Vector3(5, 0, 10)
vision.target_point = Vector3(10, 0, 10)
vision.has_target = true

# Dictionaryから復元
var dict = { "type": ActionPointData.Type.WAIT, "path_ratio": 0.7, "wait_duration": 2.0 }
var wait = ActionPointData.from_dictionary(dict)

# ポイントノードを作成
var point_node = vision.create_point_node()
```

## 関連クラス

- `ActionPoint` - ポイント表示クラスの基底
- `PointCollection` - ポイントコレクション管理
- `PathDrawer` - ポイントを配置するパス描画システム