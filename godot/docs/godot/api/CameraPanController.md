# CameraPanController

## 概要

右ドラッグ操作でカメラを平行移動する簡易コントローラー。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/utils/camera_pan_controller.gd`

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `camera` | `Camera3D` | 操作対象のカメラ |
| `pan_speed` | `float` | 移動速度 |

## メソッド

### `setup(target_camera: Camera3D, speed: float = 0.05) -> void`
対象カメラと速度を設定する。

### `handle_input(event: InputEvent) -> bool`
入力イベントを処理し、処理した場合は`true`を返す。

## 使用例

```gdscript
_camera_pan_controller = CameraPanController.new()
_camera_pan_controller.setup(camera, 0.05)

func _unhandled_input(event: InputEvent) -> void:
    if _camera_pan_controller.handle_input(event):
        return
```

## 関連クラス

- [GameScreen](GameScreen.md)
