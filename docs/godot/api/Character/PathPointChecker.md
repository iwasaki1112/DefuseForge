# PathPointChecker

**継承:** `RefCounted`

## 概要

パス上のポイント（VisionPoint, WaitPointなど）への到達判定ロジックを共通化・統一するためのユーティリティクラス。
距離ベースまたは比率（Ratio）ベースでの到達判定を行い、自動ソートやインデックス管理を提供します。

## ファイル

`godot/scripts/characters/path_point_checker.gd`

## 機能

*   **統一された到達判定:** パス上の移動距離に応じて、登録されたポイントに到達したかを順次チェックします。
*   **モード切替:** `DISTANCE` モード（メートル単位）と `RATIO` モード（0.0-1.0の割合）をサポートします。
*   **自動ソート:** ポイント追加時に自動的にパス上の位置順にソートされます。
*   **延長パス対応:** パスが延長された場合の状態引き継ぎや、既存ポイントの距離再計算をサポートします。

## 列挙型

### CheckMode

| 定数名 | 説明 |
| :--- | :--- |
| `RATIO` | `path_ratio` プロパティに基づく判定。ClearPointやGrenadePointなどで使用。 |
| `DISTANCE` | `path_distance` (またはアンカーからの計算距離) に基づく判定。VisionPointやWaitPointで使用。 |

## メソッド

### setup

```gdscript
func setup(mode: CheckMode, calc_distance: Callable, calc_anchor: Callable) -> void
```

チェッカーを初期化します。
*   `mode`: 判定モード
*   `calc_distance`: キャラクターの現在の移動距離を取得するコールバック
*   `calc_anchor`: アンカー位置からパス始点までの距離を計算するコールバック

### add_point

```gdscript
func add_point(point_data: Dictionary) -> void
```

ポイントデータを追加します。必要に応じて `path_distance` を計算し、リストをソートします。

### check_reached

```gdscript
func check_reached(current_position: float) -> Variant
```

現在位置に基づいて、次に到達したポイントを1つ取得します。到達していない場合は `null` を返します。
呼び出すたびに内部インデックスが進みます。

### check_all_reached

```gdscript
func check_all_reached(current_position: float, callback: Callable) -> int
```

現在位置までに到達した全ての未処理ポイントをチェックし、順次コールバックを実行します。

*   `callback`: `func(index: int, data: Dictionary)`

### set_points

```gdscript
func set_points(new_points: Array, recalc_from_current_pos: bool = true) -> void
```

ポイントリストを一括設定します。`recalc_from_current_pos` が `true` の場合、現在のキャラクター位置までインデックスを早送り（スキップ）します。

### create_extension_checker

```gdscript
func create_extension_checker() -> PathPointChecker
```

現在の設定を引き継いだ新しいチェッカーインスタンスを作成します（延長パス操作用）。

## 使用例

```gdscript
var checker := PathPointChecker.new()
checker.setup(
    PathPointChecker.CheckMode.DISTANCE,
    func(): return _current_distance,
    func(anchor): return _path.get_distance(anchor)
)

# ポイント登録
checker.add_point({"anchor": Vector3(10, 0, 5), "wait_time": 2.0})

# 毎フレーム更新
func _process(delta):
    checker.check_all_reached(_current_distance, func(idx, data):
        print("Point reached!", data)
    )
```
