# MouseInputHandler

**継承:** `InputDeviceHandler` < `RefCounted`

マウス入力（クリック、ドラッグ、ホイール、トラックパッドジェスチャー）を処理するハンドラクラス。

## 概要

`InputController` から委譲され、マウスやトラックパッドからの入力イベントを解析し、適切なシグナルや状態更新を行います。PC環境での操作を担当します。

## ファイル

`godot/scripts/input/handlers/mouse_input_handler.gd`

## 機能

*   **クリック判定:** `InputEventMouseButton` を監視し、タップ（クリック）とドラッグを区別します。
*   **ズーム操作:** マウスホイールおよびトラックパッドのピンチジェスチャー（`InputEventMagnifyGesture`）によるズーム操作を処理します。
*   **エミュレートイベント対策:** タッチパネル操作直後のマウスイベント（エミュレーション）を無視する機能を持っています。

## 定数

| 定数名 | 値 | 説明 |
| :--- | :--- | :--- |
| `MOUSE_TAP_THRESHOLD` | `50.0` | クリック判定の移動許容距離（ピクセル）。PCは精度が高いため比較的大きめに設定されています。 |
| `TOUCH_MOUSE_INTERVAL_MS` | `100` | タッチ操作からマウス操作までの無視期間（ミリ秒）。 |

## プロパティ

| プロパティ名 | 型 | 説明 |
| :--- | :--- | :--- |
| `zoom_speed` | `float` | ズーム操作の感度係数。デフォルト `1.0`。 |

## メソッド

### record_touch_time

```gdscript
func record_touch_time() -> void
```

タッチイベントが発生した時刻を記録します。これにより、直後に発生するエミュレートされたマウスイベントを無視判定に使用します。

### is_recent_touch

```gdscript
func is_recent_touch() -> bool
```

現在時刻が前回のタッチイベントから `TOUCH_MOUSE_INTERVAL_MS` 以内かどうかを判定します。

### handle_input

```gdscript
func handle_input(event: InputEvent) -> bool
```

入力イベントを処理します。マウスボタン、マウス移動、拡大ジェスチャーに対応しています。

**戻り値:** イベントを消費した場合は `true`。

## 内部動作

1.  **エミュレーション除外:** `_last_touch_time` を確認し、タッチ直後のマウスイベントであれば無視します。
2.  **ボタン処理 (`_handle_mouse_button`):** 左クリックのプレス/リリースを検知し、`_on_press` / `_on_release` を呼び出します。ホイール操作は `zoom_requested` シグナルを発火します。
3.  **移動処理 (`_handle_mouse_motion`):** ドラッグ中であれば `_on_drag` を呼び出します。
4.  **ジェスチャー処理 (`_handle_magnify_gesture`):** トラックパッドのピンチ操作を検知し、`zoom_requested` シグナルを発火します。
