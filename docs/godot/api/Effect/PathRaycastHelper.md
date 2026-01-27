# PathRaycastHelper

**継承:** `RefCounted`

パス描画やナビゲーションに関連する物理レイキャストを行う静的ユーティリティクラス。

## 静的メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `check_wall_between(space_state, from, to, mask)` | `Dictionary` | 2点間の視線を遮る壁があるか判定します。ドアオブジェクトは無視されます。 |
| `raycast_wall_or_floor(camera, space_state, screen_pos)` | `Dictionary` | マウス位置から壁または床へのレイキャストを行います。 |
| `raycast_door(camera, space_state, screen_pos)` | `Node3D` | マウス位置にあるドアオブジェクトを検出します。 |
| `get_ground_position(camera, plane, screen_pos)` | `Variant` | マウス位置と無限平面（地面）との交点を計算します（物理演算不使用）。 |
| `is_wall_hit(normal)` | `bool` | レイキャストの衝突法線から、壁かどうか（垂直に近いか）を判定します。 |

## 詳細

`check_wall_between` はパスのショートカット防止や視線判定に使用されます。ドアは通過可能（操作で開けられる）とみなすため、レイキャスト時に除外処理を行っています。
