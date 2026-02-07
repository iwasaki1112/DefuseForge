# TouchInputHandler

**継承:** `InputDeviceHandler` < `RefCounted`

タッチスクリーン入力（タップ、ドラッグ、ピンチズーム）を処理するハンドラクラス。

## 概要

`InputController` から委譲され、タッチパネルからのマルチタッチイベントを解析します。モバイルデバイスでの操作を担当します。

## ファイル

`godot/scripts/input/handlers/touch_input_handler.gd`

## 機能

*   **マルチタッチ管理:** 複数の指（タッチポイント）を追跡します。
*   **シングルタッチ:** 1本指でのタップ、ドラッグ操作を処理します。
*   **ピンチズーム:** 2本指でのピンチイン・ピンチアウト操作を検出し、ズーム量に変換します。
*   **状態管理:** タッチ中、ピンチ中などの状態を管理します。

## 定数

| 定数名 | 値 | 説明 |
| :--- | :--- | :--- |
| `TOUCH_TAP_THRESHOLD` | `20.0` | タップ判定の移動許容距離（ピクセル）。指の操作精度を考慮して小さめに設定されています。 |

## メソッド

### is_touch_active

```gdscript
func is_touch_active() -> bool
```

現在画面にタッチされているかどうか（指が触れているか）を返します。

### is_pinching

```gdscript
func is_pinching() -> bool
```

現在ピンチ操作（2本指操作）中かどうかを返します。

### get_touch_count

```gdscript
func get_touch_count() -> int
```

現在検知しているタッチポイントの数を返します。

### handle_input

```gdscript
func handle_input(event: InputEvent) -> bool
```

入力イベントを処理します。`InputEventScreenTouch` と `InputEventScreenDrag` に対応しています。

**戻り値:** イベントを消費した場合は `true`。

### reset_state

```gdscript
func reset_state() -> void
```

内部状態（タッチポイント、ピンチフラグなど）をリセットします。

## 内部動作

1.  **タッチ管理 (`_handle_screen_touch`):**
    *   タッチ開始時、`_touch_points` にインデックスと位置を記録します。
    *   ポイント数が2になるとピンチモードを開始 (`_start_pinch`) します。
    *   ポイント数が1の場合は通常のプレス処理 (`_on_press`) を行います。
    *   タッチ終了時、ポイントを削除し、必要に応じてピンチ終了やリリース処理 (`_on_release`) を行います。

2.  **ドラッグ管理 (`_handle_screen_drag`):**
    *   タッチポイントの位置を更新します。
    *   ピンチ中であれば、重心の移動と分散（標準偏差）の変化からズーム量を計算します (`_update_pinch_zoom`)。
    *   1本指でピンチ中でなければ、ドラッグ処理 (`_on_drag`) を行います。

3.  **ピンチ計算:**
    *   複数のタッチポイントの重心 (`centroid`) と、重心からの距離の標準偏差 (`std_deviation`) を計算します。
    *   標準偏差の変化比率をスケール変化として扱います。
