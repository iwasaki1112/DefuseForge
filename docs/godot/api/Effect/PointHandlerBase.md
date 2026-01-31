# PointHandlerBase

**継承:** `RefCounted`

すべてのポイントハンドラの基底クラス。
`VisionPointHandler`, `WaitPointHandler` などの具体的なハンドラがこのクラスを継承します。
`PathDrawer` と連携し、入力処理やマーカーの生成、管理のための共通インターフェースとヘルパーメソッドを提供します。

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `point_added` | `point_data: Dictionary` | ポイントが追加された時 |
| `point_removed` | `point_data: Dictionary` | ポイントが削除された時 |

## プロパティ（共通状態）

| 名前 | 型 | 説明 |
| :--- | :--- | :--- |
| `_path_drawer` | `Node3D` | PathDrawerへの参照 |
| `_camera` | `Camera3D` | カメラ参照 |
| `_character_color` | `Color` | キャラクター色 |
| `_points` | `Array[Dictionary]` | ポイントデータ配列 |
| `_meshes` | `Array[MeshInstance3D]` | ポイントメッシュ配列 |
| `_current_anchor` | `Vector3` | 現在のアンカー位置 |
| `_current_ratio` | `float` | 現在のパス上比率 |
| `_is_active` | `bool` | 操作中フラグ（描画中、長押し中など） |
| `_drag_start_pos` | `Vector2` | ドラッグ開始位置（スクリーン座標） |

## メソッド

### ライフサイクル

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `setup(path_drawer, camera)` | `void` | 依存関係を注入します。 |
| `set_character_color(color)` | `void` | マーカーの色設定を更新します。 |

### 入力処理テンプレート

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `handle_input(event)` | `bool` | 入力イベントを処理します。タッチ/マウス両対応。 |
| `_handle_press(screen_pos)` | `bool` | 押下処理（サブクラスでオーバーライド） |
| `_handle_release(screen_pos)` | `bool` | 解放処理（サブクラスでオーバーライド） |
| `_handle_motion(screen_pos)` | `void` | 移動処理（サブクラスでオーバーライド） |

### ポイント管理

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `has_points()` | `bool` | ポイントが存在するかどうかを返します。 |
| `get_point_count()` | `int` | ポイント数を返します。 |
| `get_points()` | `Array[Dictionary]` | 現在のポイントデータ一覧を取得します。 |
| `take_points()` | `Array[MeshInstance3D]` | メッシュの所有権を移動させます。 |
| `undo_last()` | `Dictionary` | 最後に追加したポイントを取り消します。 |
| `clear_all()` | `void` | すべてのポイントを削除します。 |
| `reset_state()` | `void` | 一時的な編集状態をリセットします。 |
| `restore_points(data, meshes)` | `void` | ポイントを復元します。 |
| `_add_point(point_data, mesh)` | `void` | ポイントを追加（path_ratio順に挿入）。 |
| `create_point(data)` | `MeshInstance3D` | ポイント作成（サブクラスでオーバーライド） |

### ヘルパーメソッド（protected）

`PathDrawer` の機能へのアクセスを提供します。

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `_get_ground_position(screen_pos)` | `Variant` | マウス位置に対応する地面上の座標を取得します。 |
| `_find_closest_point_on_path(pos)` | `Dictionary` | 指定位置に最も近いパス上の点を検索します。 |
| `_find_offset_point_on_path(base_ratio, offset)` | `Dictionary` | パス上の基準点から距離オフセットした点を計算します。 |
| `_get_path_click_threshold()` | `float` | パスクリック判定距離を取得します。 |
| `_has_path()` | `bool` | パスが存在するかを返します。 |
| `_add_child_to_drawer(node)` | `void` | PathDrawerに子ノードを追加します。 |
| `_raycast_wall_or_floor(screen_pos)` | `Dictionary` | 壁または床へのレイキャストを実行します。 |
| `_raycast_door(screen_pos)` | `Node3D` | ドアへのレイキャストを実行します。 |
| `_is_tap(current_pos, threshold)` | `bool` | タップかドラッグかを判定します。 |
| `_check_path_click(screen_pos)` | `Dictionary` | パス上クリック判定（共通処理）。 |

## 使用例

```gdscript
# 子クラスでの実装例
class_name MyPointHandler
extends PointHandlerBase

func _handle_press(screen_pos: Vector2) -> bool:
    if _is_active:
        return true  # 重複イベント対策

    var click_result = _check_path_click(screen_pos)
    if not click_result.success:
        return false

    _current_anchor = click_result.anchor
    _current_ratio = click_result.ratio
    _drag_start_pos = screen_pos
    _is_active = true
    return true

func _handle_release(screen_pos: Vector2) -> bool:
    if not _is_active:
        return false

    _is_active = false

    # ポイントを作成
    var mesh = PointFactory.create_my_point(
        _current_anchor,
        _character_color,
        _path_drawer
    )

    var point_data = {
        "path_ratio": _current_ratio,
        "anchor": _current_anchor
    }

    _add_point(point_data, mesh)
    return true
```

## 関連クラス

- [PointFactory](PointFactory.md) - ポイントメッシュ作成ファクトリ
- [PathDrawer](PathDrawer.md) - パス描画・編集
- [VisionPoint](VisionPoint.md) - 視線方向を示すポイント
- [WaitPoint](WaitPoint.md) - 待機時間を示すポイント
