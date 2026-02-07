# TimelineCalculator

## 概要

パスデータから時間情報を計算する静的ユーティリティクラス。タイムラインUIでの可視化に使用。

## ファイル

`godot/scripts/utils/timeline_calculator.gd`

## 定数

| 定数 | 型 | 値 | 説明 |
|------|-----|-----|------|
| `WALK_SPEED` | float | 2.0 | 歩行速度 (m/s) |
| `RUN_SPEED` | float | 5.0 | 走行速度 (m/s) |
| `DOOR_DURATION` | float | 1.0 | ドアキック固定時間 (秒) |

## 列挙型

### SegmentType

タイムラインセグメントの種類。

| 値 | 説明 |
|----|------|
| `WALK` | 歩行区間 |
| `RUN` | 走行区間 |
| `WAIT` | 待機区間（Waitポイント） |
| `DOOR` | ドア操作区間（Doorポイント） |

## 内部クラス

### TimelineSegment

タイムラインの1セグメントを表す。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `start_time` | float | セグメント開始時間 (秒) |
| `end_time` | float | セグメント終了時間 (秒) |
| `type` | int | セグメントタイプ (SegmentType) |
| `start_ratio` | float | パス上の開始比率 (0.0-1.0) |
| `end_ratio` | float | パス上の終了比率 (0.0-1.0) |

| メソッド | 戻り値 | 説明 |
|---------|--------|------|
| `get_duration()` | float | セグメントの継続時間を取得 |

### TimelineData

パス全体のタイムライン情報を保持。

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `total_duration` | float | 合計時間 (秒) |
| `segments` | Array[TimelineSegment] | セグメントリスト |
| `path_length` | float | パスの総距離 (m) |

| メソッド | 引数 | 戻り値 | 説明 |
|---------|------|--------|------|
| `add_segment(segment)` | TimelineSegment | void | セグメントを追加 |
| `get_time_at_ratio(ratio)` | float | float | パス比率から時間を取得 |
| `get_ratio_at_time(time)` | float | float | 時間からパス比率を取得 |

## 静的メソッド

### calculate_timeline

パスデータからタイムラインを計算。

```gdscript
static func calculate_timeline(
    path: Array[Vector3],
    run_segments: Array[Dictionary] = [],
    wait_points: Array[Dictionary] = [],
    door_points: Array[Dictionary] = []
) -> TimelineData
```

| 引数 | 型 | 説明 |
|------|-----|------|
| `path` | Array[Vector3] | パスポイント配列 |
| `run_segments` | Array[Dictionary] | Run区間配列 `[{ start_ratio, end_ratio }]` |
| `wait_points` | Array[Dictionary] | Waitポイント配列 `[{ path_ratio, wait_duration }]` |
| `door_points` | Array[Dictionary] | Doorポイント配列 `[{ path_ratio }]` |

### calculate_time_for_distance

距離から時間を計算（簡易版）。

```gdscript
static func calculate_time_for_distance(distance: float, is_running: bool = false) -> float
```

### calculate_simple_duration

パスの合計時間を計算（マーカーなし、簡易版）。

```gdscript
static func calculate_simple_duration(path: Array[Vector3], is_running: bool = false) -> float
```

## 使用例

```gdscript
# タイムラインを計算
var path: Array[Vector3] = [Vector3(0, 0, 0), Vector3(10, 0, 0)]
var run_segments: Array[Dictionary] = [{ "start_ratio": 0.3, "end_ratio": 0.6 }]
var wait_points: Array[Dictionary] = [{ "path_ratio": 0.8, "wait_duration": 2.0 }]

var timeline = TimelineCalculator.calculate_timeline(path, run_segments, wait_points)
print("Total duration: %s seconds" % timeline.total_duration)

# 比率から時間を取得
var time_at_halfway = timeline.get_time_at_ratio(0.5)
```
