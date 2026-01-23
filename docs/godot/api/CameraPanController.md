# CameraPanController

## 概要

右ドラッグ操作でカメラを平行移動、スクロール/ピンチでズームする簡易コントローラー。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/utils/camera_pan_controller.gd`

## プロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|------------|------|
| `camera` | `Camera3D` | `null` | 操作対象のカメラ |
| `pan_speed` | `float` | `0.05` | パン移動速度 |
| `zoom_speed` | `float` | `2.0` | マウスホイールでのズーム速度 |
| `zoom_min` | `float` | `5.0` | 最小ズーム（カメラY座標の下限） |
| `zoom_max` | `float` | `50.0` | 最大ズーム（カメラY座標の上限） |
| `zoom_smoothing` | `float` | `10.0` | ズームの滑らかさ（補間係数） |

## メソッド

### `setup(target_camera: Camera3D, speed: float = 0.05) -> void`
対象カメラと速度を設定する。

### `handle_input(event: InputEvent) -> bool`
入力イベントを処理し、処理した場合は`true`を返す。

対応する入力:
- **右ドラッグ**: カメラのパン移動
- **マウスホイール**: ズームイン/アウト（PC）
- **ピンチジェスチャー**: ズームイン/アウト（モバイル）

### `process(delta: float) -> void`
毎フレーム呼び出してズームを滑らかに適用する。

## 使用例

```gdscript
_camera_pan_controller = CameraPanController.new()
_camera_pan_controller.setup(camera, 0.05)

func _unhandled_input(event: InputEvent) -> void:
    if _camera_pan_controller.handle_input(event):
        return

func _physics_process(delta: float) -> void:
    _camera_pan_controller.process(delta)
```

## ズーム操作

- **PC**: マウスホイールを上に回すとズームイン、下に回すとズームアウト
- **モバイル**: 2本指でピンチアウト（指を広げる）するとズームイン、ピンチイン（指を狭める）するとズームアウト

## 関連クラス

- [GameScreen](GameScreen.md)
- [InputController](InputController.md)
