# PointFactory

**継承:** `RefCounted`

ポイントメッシュ作成を一元化するファクトリクラス。
`VisionPoint` および `WaitPoint` のメッシュ作成ロジックを集約し、重複コードを削減します。

## 定数

| 名前 | 説明 |
| :--- | :--- |
| `PointType` | `ActionPointData.Type` のエイリアス（VISION, WAIT） |

## 静的メソッド

### VisionPoint作成

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `create_vision_point(anchor, target_point, direction, char_color, parent)` | `MeshInstance3D` | VisionPointメッシュを作成します。 |
| `create_vision_point_from_dict(data, char_color, parent)` | `MeshInstance3D` | Dictionaryからメッシュを作成します。 |
| `create_vision_point_preview(anchor, target_point, char_color, parent)` | `MeshInstance3D` | プレビュー用の半透明メッシュを作成します。 |

### WaitPoint作成

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `create_wait_point(anchor, duration, char_color, parent)` | `MeshInstance3D` | WaitPointメッシュを作成します。 |
| `create_wait_point_from_dict(data, char_color, parent)` | `MeshInstance3D` | Dictionaryからメッシュを作成します。 |
| `create_wait_point_preview(anchor, duration, char_color, parent)` | `MeshInstance3D` | プレビュー用の半透明メッシュを作成します。 |

### 汎用

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `create_point_by_type(point_type, data, char_color, parent)` | `MeshInstance3D` | ポイントタイプに応じてメッシュを作成します。 |
| `free_point_meshes(meshes)` | `void` | ポイントメッシュの配列を解放します。 |

## パラメータ詳細

### create_vision_point

| パラメータ | 型 | 説明 |
| :--- | :--- | :--- |
| `anchor` | `Vector3` | パス上のアンカー位置 |
| `target_point` | `Variant` | ターゲット地点（null/ZEROの場合は`direction`を使用） |
| `direction` | `Vector3` | 視線方向（`target_point`がない場合に使用） |
| `char_color` | `Color` | キャラクター色 |
| `parent` | `Node` | 親ノード（nullの場合はadd_childしない） |

### create_wait_point

| パラメータ | 型 | 説明 |
| :--- | :--- | :--- |
| `anchor` | `Vector3` | パス上のアンカー位置 |
| `duration` | `float` | 待機時間（-1で同期ポイント） |
| `char_color` | `Color` | キャラクター色 |
| `parent` | `Node` | 親ノード（nullの場合はadd_childしない） |

## 使用例

```gdscript
# VisionPointを作成（親ノードに自動追加）
var vision_mesh = PointFactory.create_vision_point(
    anchor_pos,
    target_pos,
    Vector3.ZERO,
    Color.RED,
    path_drawer
)

# WaitPointを作成（親ノードに自動追加）
var wait_mesh = PointFactory.create_wait_point(
    anchor_pos,
    3.0,  # 3秒待機
    Color.BLUE,
    path_drawer
)

# Dictionaryからポイントタイプに応じて作成
var mesh = PointFactory.create_point_by_type(
    ActionPointData.Type.VISION,
    {"anchor": pos, "target_point": target},
    char_color,
    parent_node
)

# メッシュの解放
PointFactory.free_point_meshes(mesh_array)
```

## 注意事項

- `parent` パラメータを指定すると、メッシュはシーンツリーに追加された後に初期化されます
- これにより `global_position` などのプロパティへのアクセスが安全になります
- `parent` が `null` の場合は呼び出し側で `add_child()` を行う必要があります

## 関連クラス

- [VisionPoint](VisionPoint.md) - 視線方向を示すポイント
- [WaitPoint](WaitPoint.md) - 待機時間を示すポイント
- [PointHandlerBase](PointHandlerBase.md) - ポイントハンドラの基底クラス
- [ActionPointData](ActionPointData.md) - ポイントタイプの定義
