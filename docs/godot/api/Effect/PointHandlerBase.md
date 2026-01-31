# PointHandlerBase

**継承:** `RefCounted`

すべてのポイントハンドラの基底クラス。
`VisionPointHandler`, `RunPointHandler` などの具体的なハンドラがこのクラスを継承します。
`PathDrawer` と連携し、入力処理やマーカーの生成、管理のための共通インターフェースとヘルパーメソッドを提供します。

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `marker_added` | `point_data: Dictionary` | マーカーが追加された時（サブクラスで使用） |
| `marker_removed` | `point_data: Dictionary` | マーカーが削除された時（サブクラスで使用） |
| `timeline_changed` | `void` | タイムラインに影響する変更があった時 |

## メソッド

### ライフサイクル
| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `setup(path_drawer, camera)` | `void` | 依存関係を注入します。 |
| `set_character_color(color)` | `void` | マーカーの色設定を更新します。 |

### インターフェース（サブクラスでオーバーライド）
| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `handle_input(event)` | `bool` | 入力イベントを処理します。処理した場合はtrueを返します。 |
| `create_marker(data)` | `MeshInstance3D` | マーカーの3D表示を作成します。 |
| `undo_last()` | `Dictionary` | 最後に追加したポイントを取り消します。 |
| `clear_all()` | `void` | すべてのマーカーを削除します。 |
| `has_markers()` | `bool` | マーカーが存在するかどうかを返します。 |
| `get_markers()` | `Array[Dictionary]` | 現在のポイントデータ一覧を取得します。 |
| `take_markers()` | `Array[MeshInstance3D]` | マーカーのMeshInstance3Dの所有権を移動させます（PathDrawerでの確定処理用）。 |
| `reset_state()` | `void` | 一時的な編集状態をリセットします。 |

### ヘルパーメソッド（protected）
`PathDrawer` の機能へのアクセスを提供します。

| 名前 | 説明 |
| :--- | :--- |
| `_get_ground_position(screen_pos)` | マウス位置に対応する地面上の座標を取得します。 |
| `_find_closest_point_on_path(pos)` | 指定位置に最も近いパス上の点を検索します。 |
| `_find_offset_point_on_path(base_ratio, offset)` | パス上の基準点から距離オフセットした点を計算します。 |
| `_raycast_wall_or_floor(screen_pos)` | 壁または床へのレイキャストを実行します。 |
| `_raycast_door(screen_pos)` | ドアへのレイキャストを実行します。 |
