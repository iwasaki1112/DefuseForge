# SmokeAreaManager

**継承:** `Node`

スモークエリア管理システム。
アクティブなスモークエリア（`SmokeArea`）をグローバルに管理し、視線判定（Line of Sight）のためのAPIを提供します。

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `smoke_area_added` | `area: Node3D` | 新しいスモークエリアが登録された時 |
| `smoke_area_removed` | `area: Node3D` | スモークエリアが削除された時 |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `register_area(area: Node3D)` | `void` | スモークエリアを管理対象に追加します。 |
| `unregister_area(area: Node3D)` | `void` | スモークエリアを管理対象から外します。 |
| `is_line_of_sight_blocked(origin, target)` | `bool` | 指定された2点間の視線がスモークによって遮られているか判定します。 |
| `is_position_in_smoke(pos: Vector3)` | `bool` | 指定された位置がスモークの中にあるか判定します。 |
| `get_active_count()` | `int` | 現在アクティブなスモークエリアの数を返します。 |
| `clear_all()` | `void` | すべてのスモークエリアを削除します。 |

## 詳細

視覚システム（`VisionSystem` や `VisionService`）から利用されることを想定しています。
各 `SmokeArea` は、自身が視線を遮るかどうかの判定ロジック（`intersects_line_segment`, `is_position_inside`）を持っている必要があります。
