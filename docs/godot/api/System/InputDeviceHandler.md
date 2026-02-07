# InputDeviceHandler

## 概要

入力デバイスハンドラの基底クラス。デバイス固有の入力イベントを抽象化されたシグナルに変換し、共通インターフェースを提供する。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/input/input_device_handler.gd`
- **子クラス**: `MouseInputHandler`, `TouchInputHandler`

## シグナル

| シグナル | パラメータ | 説明 |
|---------|-----------|------|
| `press_detected` | `position: Vector2` | プレス（クリック/タッチ開始）検出時 |
| `release_detected` | `position: Vector2, was_dragging: bool` | リリース検出時、ドラッグ中だったかを含む |
| `drag_detected` | `position: Vector2, distance_from_start: float` | ドラッグ検出時、開始位置からの距離を含む |
| `tap_detected` | `position: Vector2` | タップ（短いクリック/タッチ）検出時 |
| `zoom_requested` | `amount: float` | ズーム要求時（正=ズームアウト、負=ズームイン） |
| `pinch_state_changed` | `is_pinching: bool` | ピンチ状態変更時（TouchInputHandlerのみ） |

## プロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `tap_threshold` | `float` | 40.0 | タップ判定の最大移動距離（ピクセル） |
| `drag_threshold` | `float` | 5.0 | ドラッグ判定の最小移動距離（ピクセル） |

## 公開メソッド

### handle_input(event: InputEvent) -> bool
入力イベントを処理する。子クラスでオーバーライド。

### is_pressed() -> bool
押下中かどうかを取得。

### is_dragging() -> bool
ドラッグ中かどうかを取得。

### is_pending_drag() -> bool
ドラッグ待機中（閾値チェック前）かどうかを取得。

### get_press_start_position() -> Vector2
押下開始位置を取得。

### is_pinching() -> bool
ピンチ中かどうかを取得（子クラスでオーバーライド）。

### get_touch_count() -> int
タッチポイント数を取得（子クラスでオーバーライド）。

### reset_state() -> void
内部状態をリセット。

## 子クラス

### MouseInputHandler

マウス入力を処理するハンドラ。

- **ファイル**: `scripts/input/handlers/mouse_input_handler.gd`
- **tap_threshold**: 50.0（PCは精度が高いため）
- **対応イベント**:
  - `InputEventMouseButton` - 左クリック、マウスホイール
  - `InputEventMouseMotion` - マウス移動/ドラッグ
  - `InputEventMagnifyGesture` - トラックパッドピンチ

### TouchInputHandler

タッチ入力を処理するハンドラ。

- **ファイル**: `scripts/input/handlers/touch_input_handler.gd`
- **tap_threshold**: 20.0（指は精度が低いため）
- **対応イベント**:
  - `InputEventScreenTouch` - タッチ開始/終了
  - `InputEventScreenDrag` - タッチドラッグ
- **追加機能**:
  - ピンチズーム処理
  - マルチタッチ追跡

## 使用例

```gdscript
# InputController内での使用
func _setup_input_handlers() -> void:
    _mouse_handler = MouseInputHandler.new()
    _touch_handler = TouchInputHandler.new()

    # シグナル接続
    _mouse_handler.press_detected.connect(_on_press)
    _mouse_handler.tap_detected.connect(_on_tap)
    _mouse_handler.zoom_requested.connect(_on_zoom)

    _touch_handler.press_detected.connect(_on_press)
    _touch_handler.tap_detected.connect(_on_tap)
    _touch_handler.zoom_requested.connect(_on_zoom)
    _touch_handler.pinch_state_changed.connect(_on_pinch_state_changed)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventScreenDrag:
        _touch_handler.handle_input(event)
    elif event is InputEventMouseButton or event is InputEventMouseMotion:
        _mouse_handler.handle_input(event)
```

## 拡張

新しい入力デバイス（ゲームパッドなど）をサポートするには：

1. `InputDeviceHandler`を継承したクラスを作成
2. `handle_input()`をオーバーライドして対応イベントを処理
3. 適切なシグナルを発火

```gdscript
class_name GamepadInputHandler
extends InputDeviceHandler

func handle_input(event: InputEvent) -> bool:
    if event is InputEventJoypadButton:
        # ボタン処理
        pass
    elif event is InputEventJoypadMotion:
        # スティック処理
        pass
    return false
```

## 関連クラス

- [InputController](InputController.md)
- [CameraPanController](../Util/CameraPanController.md)
