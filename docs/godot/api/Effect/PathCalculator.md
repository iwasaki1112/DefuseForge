# PathCalculator

**継承:** `RefCounted`

パス（`PackedVector3Array`）に関する幾何計算を行う静的ユーティリティクラス。

## 静的メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `find_closest_point_on_path(path, pos)` | `Dictionary` | 指定位置に最も近いパス上の点を計算します。<br>戻り値: `{ "point": Vector3, "distance": float, "ratio": float }` |
| `find_offset_point_on_path(path, base_ratio, offset)` | `Dictionary` | パス上の基準比率から、指定距離だけ移動した点を計算します。<br>戻り値: `{ "point": Vector3, "ratio": float }` |
| `calculate_path_length(path)` | `float` | パスの総延長を計算します。 |
| `get_point_at_ratio(path, ratio)` | `Vector3` | パス上の指定比率（0.0〜1.0）に対応する座標を取得します。 |
| `get_path_endpoint(path)` | `Vector3` | パスの最後の点を取得します。 |
| `is_near_path_endpoint(path, pos, threshold)` | `bool` | 指定位置がパスの終点付近かどうかを判定します。 |

## 詳細

パスは直線のセグメントの集合として扱われます。`ratio` はパス全体に対する進行割合を表し、0.0が始点、1.0が終点に対応します。
