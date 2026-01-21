# InputController

## 概要

ゲーム画面での入力処理をまとめるコントローラー。カメラ移動やパス/回転操作の入力をGameManagerに委譲する。

## クラス情報

- **継承**: `Node`
- **ファイル**: `scripts/screens/input_controller.gd`

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `game_manager` | `GameManager` | 操作対象のGameManager |
| `camera_pan_controller` | `CameraPanController` | カメラ平行移動コントローラー |

## メソッド

### `setup(manager: GameManager, pan_controller: CameraPanController) -> void`
必要な参照を設定する。

### `_unhandled_input(event: InputEvent) -> void`
右ドラッグによるカメラ移動、パス/回転モードのクリック処理を行う。

### `_input(event: InputEvent) -> void`
ESC入力のキャンセル処理を行う。

## 使用例

```gdscript
var input_controller := InputController.new()
add_child(input_controller)
input_controller.setup(game_manager, camera_pan_controller)
```

## 関連クラス

- [GameScreen](GameScreen.md)
- [GameManager](GameManager.md)
- [CameraPanController](CameraPanController.md)
