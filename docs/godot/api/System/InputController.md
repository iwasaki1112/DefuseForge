# InputController

## 概要

ゲーム画面での入力処理を統括するコントローラー。PC（マウス）とモバイル（タッチ）の両方の入力に対応し、カメラ操作、パス描画、キャラクター選択などの機能を適切に振り分ける。

## クラス情報

- **継承**: `Node`
- **ファイル**: `scripts/screens/input_controller.gd`

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `game_manager` | `GameManager` | 操作対象のGameManager |
| `camera_pan_controller` | `CameraPanController` | カメラ平行移動・ズームコントローラー |

## 入力処理フロー

入力は以下の優先順位で処理される:

### 1. ピンチズーム / マルチタッチ (最優先)
- **2本指以上** または **ピンチ操作中** は、現在のモードに関わらず常にカメラズーム/パンとして処理される。
- これにより、パス描画中であってもいつでもカメラ操作が可能。

### 2. パスモード (Path Mode)
`GameManager.is_path_mode()` が true の場合:

- **PathDrawer描画中**: 入力を `PathDrawer` に委譲。
- **新規パス描画**: `PathDrawer` に委譲。
- **マーカーモード (Vision/Run等)**:
    - **パス上タップ/ドラッグ**: `PathDrawer` に委譲（マーカー配置）。
    - **パス外**: カメラパンとして処理（1本指ドラッグ）。

### 3. 通常モード (Default)
- **1本指タップ**: キャラクター選択 (`game_manager.handle_click`)。
- **1本指ドラッグ**: カメラパン (`CameraPanController`)。

### 4. 回転モード (Rotation Mode)
- `game_manager.handle_rotation_input` に委譲。

## PC vs モバイルの挙動

### モバイル (Touch)
- **タップ vs パン**: `CameraPanController` 内で閾値判定を行い、短いタップはクリック（選択）、移動量が大きい場合はパンとして扱う。
- **Pathモード**: パス上かどうかの判定 (`_get_ground_position`) を行い、パス上なら編集、パス外ならカメラ操作となる。

### PC (Mouse)
- **左クリック**: `_handle_left_click` で処理。
- **ドラッグ**: `_handle_left_drag` で処理。
- 基本的なロジックはモバイルと同様だが、マウスイベントベースで動作する。

## メソッド

### セットアップ
#### `setup(manager: GameManager, pan_controller: CameraPanController) -> void`
必要な参照を設定する。

### 入力ハンドリング
#### `_unhandled_input(event: InputEvent) -> void`
メインの入力処理。タッチイベント、マウスイベントを受け取り、優先順位に従って処理を振り分ける。

#### `_input(event: InputEvent) -> void`
ESCキーなどのグローバルショートカット処理。
- パスフォロー中のキャンセル
- 回転モードのキャンセル
- パスモードのキャンセル

## 内部ヘルパーメソッド

- `_is_touch_active() -> bool`: タッチ操作中かどうか判定。
- `_get_ground_position(screen_pos) -> Vector3`: スクリーン座標から地面座標（Y=0平面）へのレイキャストを行う。
- `_get_path_drawer() -> PathDrawer`: PathDrawerインスタンスを取得。

## 関連クラス

- [GameScreen](GameScreen.md)
- [GameManager](GameManager.md)
- [CameraPanController](../Util/CameraPanController.md)
- [PathDrawer](../Effect/PathDrawer.md)