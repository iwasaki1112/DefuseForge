# InputController

## 概要

ゲーム画面での入力処理をまとめるコントローラー。左クリックの入力をモードに応じてカメラ移動またはPathDrawerに委譲する。

## クラス情報

- **継承**: `Node`
- **ファイル**: `scripts/screens/input_controller.gd`

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `game_manager` | `GameManager` | 操作対象のGameManager |
| `camera_pan_controller` | `CameraPanController` | カメラ平行移動コントローラー |

## 入力優先順位

左クリック処理は以下の優先順位で分岐する:

### パスモードOFF
- **ドラッグ（5px以上移動）** → カメラ移動
- **クリック（5px未満）** → キャラクター選択等

### パスモードON - MOVEMENTモード
- **すべて** → PathDrawer（パス描画）

### パスモードON - マーカーモード（Vision/Run/Clear）
- **パス上クリック（0.5m以内）** → PathDrawer（マーカー設定）
- **パス外ドラッグ** → カメラ移動を許可

## 入力フロー

```
左クリック押下:
  └ パスモードOFF?
      → YES → CameraPanControllerでドラッグ開始候補
  └ パスモードON + MOVEMENTモード?
      → YES → PathDrawerに委譲（パス描画開始）
  └ パスモードON + マーカーモード?
      → パス上(0.5m以内)? → YES → PathDrawerに委譲
                        → NO  → CameraPanControllerでドラッグ開始候補

左クリック移動:
  └ PathDrawer描画中?
      → YES → PathDrawerに委譲
  └ CameraPanControllerドラッグ候補中?
      → 閾値(5px)超過? → YES → カメラ移動開始
                       → NO  → 待機

左クリック解放:
  └ カメラドラッグ成立?
      → YES → カメラ移動終了
      → NO  → クリック処理（キャラクター選択等）
```

## メソッド

### `setup(manager: GameManager, pan_controller: CameraPanController) -> void`
必要な参照を設定する。

### `_unhandled_input(event: InputEvent) -> void`
左クリックによるカメラ移動/パス描画、パス/回転モードの入力処理を行う。

- ズーム入力（ホイール/ピンチ）は常に処理
- 左クリック押下/移動/解放は優先順位に従って分岐

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
- [PathDrawer](PathDrawer.md)
