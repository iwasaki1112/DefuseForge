# CameraPanController

## 概要

左ドラッグ操作でカメラを平行移動、スクロール/ピンチでズームする簡易コントローラー。
ドラッグ判定には閾値（5px）があり、閾値未満の移動はクリックとして扱われる。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/utils/camera_pan_controller.gd`

## 定数

| 定数 | 型 | 値 | 説明 |
|-----|-----|-----|------|
| `DRAG_THRESHOLD` | `float` | `5.0` | ドラッグ判定の閾値（ピクセル） |

## プロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|------------|------|
| `camera` | `Camera3D` | `null` | 操作対象のカメラ |
| `pan_speed` | `float` | `0.05` | パン移動速度 |
| `zoom_speed` | `float` | `1.0` | マウスホイールでのズーム速度 |
| `zoom_min` | `float` | `12.0` | 最小ズーム（カメラY座標の下限） |
| `zoom_max` | `float` | `20.0` | 最大ズーム（カメラY座標の上限） |
| `zoom_smoothing` | `float` | `10.0` | ズームの滑らかさ（補間係数） |

## メソッド

### `setup(target_camera: Camera3D, speed: float = 0.05) -> void`
対象カメラと速度を設定する。

### `handle_input(event: InputEvent) -> bool`
入力イベントを処理し、処理した場合は`true`を返す。

対応する入力:
- **マウスドラッグ中の移動**: カメラのパン移動（ドラッグ成立後）
- **マウスホイール**: ズームイン/アウト（PC）
- **ピンチジェスチャー**: ズームイン/アウト（モバイル）

### ドラッグ制御API

左クリックドラッグの判定とカメラ移動はInputControllerから以下のAPIを使用して制御される。

### `start_potential_drag(pos: Vector2) -> void`
ドラッグ候補を開始する。左クリック押下時に呼び出す。

### `check_and_start_drag(current_pos: Vector2) -> bool`
ドラッグが成立したかチェックし、成立したらドラッグモードに移行する。

**戻り値:** ドラッグが成立した場合`true`

### `is_dragging() -> bool`
ドラッグ中かどうかを返す。

### `is_pending_drag() -> bool`
ドラッグ候補中（閾値判定前）かどうかを返す。

### `end_drag() -> void`
ドラッグを終了する。

### `cancel_potential_drag() -> void`
ドラッグ候補をキャンセルする（閾値未達でクリックとして処理する場合）。

### `process(delta: float) -> void`
毎フレーム呼び出してズームを滑らかに適用する。

## ドラッグ状態遷移

```
IDLE → PENDING（左ボタン押下 → start_potential_drag）
PENDING → DRAGGING（閾値超過 → check_and_start_drag returns true）
PENDING → IDLE（閾値未満で離す → cancel_potential_drag）
DRAGGING → IDLE（左ボタン解放 → end_drag）
```

## 使用例

```gdscript
# InputControllerから呼び出される使用パターン
_camera_pan_controller = CameraPanController.new()
_camera_pan_controller.setup(camera, 0.05)

# 左クリック押下時
_camera_pan_controller.start_potential_drag(event.position)

# マウス移動時
if _camera_pan_controller.is_pending_drag():
    if _camera_pan_controller.check_and_start_drag(event.position):
        # ドラッグ成立
        pass
elif _camera_pan_controller.is_dragging():
    _camera_pan_controller.handle_input(event)

# 左クリック解放時
if _camera_pan_controller.is_dragging():
    _camera_pan_controller.end_drag()
elif _camera_pan_controller.is_pending_drag():
    _camera_pan_controller.cancel_potential_drag()
    # クリック処理

func _physics_process(delta: float) -> void:
    _camera_pan_controller.process(delta)
```

## ズーム操作

- **PC**: マウスホイールを上に回すとズームイン、下に回すとズームアウト
- **モバイル**: 2本指でピンチアウト（指を広げる）するとズームイン、ピンチイン（指を狭める）するとズームアウト

## 関連クラス

- [GameScreen](GameScreen.md)
- [InputController](InputController.md)

## APIリファレンス

### シグナル
なし

### メソッド
- `setup(target_camera: Camera3D, speed: float = 0.05) -> void`
- `handle_input(event: InputEvent) -> bool`
- `start_potential_drag(pos: Vector2) -> void`
- `check_and_start_drag(current_pos: Vector2) -> bool`
- `is_dragging() -> bool`
- `is_pending_drag() -> bool`
- `end_drag() -> void`
- `cancel_potential_drag() -> void`
- `process(delta: float) -> void`
