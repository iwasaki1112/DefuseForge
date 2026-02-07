# InputController

## 概要

ゲーム画面での入力処理を統括するコントローラー。PC（マウス）とモバイル（タッチ）の両方の入力に対応し、カメラ操作、パス描画、キャラクター選択などの機能を適切に振り分ける。

## アーキテクチャ

Strategy + Compositionパターンを採用し、デバイス固有の入力処理をハンドラクラスに分離。

```
InputController (Node) - 共通ゲームロジック
├── _mouse_handler: MouseInputHandler  - マウス/トラックパッド入力
├── _touch_handler: TouchInputHandler  - タッチ入力
└── camera_pan_controller: CameraPanController - カメラ操作

InputDeviceHandler (RefCounted) - デバイスハンドラ基底クラス
├── シグナル: press_detected, release_detected, drag_detected, tap_detected, zoom_requested
└── 共通ヘルパー: _is_tap(), _exceeded_drag_threshold()

MouseInputHandler extends InputDeviceHandler
├── tap_threshold = 50.0 (PCは精度が高いため大きめ)
└── 対応: InputEventMouseButton, InputEventMouseMotion, InputEventMagnifyGesture

TouchInputHandler extends InputDeviceHandler
├── tap_threshold = 20.0 (タッチは精度が低いため小さめ)
├── ピンチズーム処理
└── 対応: InputEventScreenTouch, InputEventScreenDrag
```

## クラス情報

- **継承**: `Node`
- **ファイル**: `scripts/input/input_controller.gd`

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `scripts/input/input_controller.gd` | メインコントローラー |
| `scripts/input/input_device_handler.gd` | デバイスハンドラ基底クラス |
| `scripts/input/handlers/mouse_input_handler.gd` | マウス入力ハンドラ |
| `scripts/input/handlers/touch_input_handler.gd` | タッチ入力ハンドラ |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `game_manager` | `GameManager` | 操作対象のGameManager |
| `camera_pan_controller` | `CameraPanController` | カメラ平行移動・ズームコントローラー |
| `_mouse_handler` | `MouseInputHandler` | マウス入力ハンドラ |
| `_touch_handler` | `TouchInputHandler` | タッチ入力ハンドラ |

## 入力処理フロー

入力は以下の優先順位で処理される:

### 1. ピンチズーム / マルチタッチ (最優先)
- **2本指以上** または **ピンチ操作中** は、現在のモードに関わらず常にカメラズーム/パンとして処理される。
- これにより、パス描画中であってもいつでもカメラ操作が可能。

### 2. パスモード (Path Mode & Immediate Mode)
`GameManager.is_path_mode()` が true、またはキャラクターのドラッグ操作時:

- **即時パスモード (Immediate Path Mode)**:
    - パス未設定のキャラクターをタップすると即座に選択状態になる。
    - そのままドラッグを開始すると、モード切替ボタンを押さなくても直感的にパス描画を開始できる。
    - **誤操作防止**: 微小な指の動き（15px未満）はドラッグとして扱わず、長押し判定（回転モード）を維持する。一定距離以上ドラッグした場合のみパス描画が開始される。
    - パス設定済みのキャラクターをタップした場合は、まず既存パスが表示され（確認モード）、ドラッグで再描画や修正が可能。

- **パス延長 (Path Extension)**:
    - 既存パスの終点付近をタップまたはドラッグすると、自動的に「パス延長モード」になる。
    - 既存のパスを維持したまま、終点から新しいパスを描き足すことができる。
    - 移動中のキャラクターのパス終点からも延長が可能（Moving Path Extension）。

- **PathDrawer描画中**: 入力を `PathDrawer` に委譲。
- **新規パス描画**: `PathDrawer` に委譲。
- **マーカーモード (Vision/Run等)**:
    - **パス上タップ/ドラッグ**: `PathDrawer` に委譲（マーカー配置）。
    - **パス外**: カメラパンとして処理（1本指ドラッグ）。

### 4. 特殊操作モード

#### 長押し回転モード (Long Press Rotation Mode)
キャラクターを**1.0秒以上長押し**すると発動。
- **操作**: そのままドラッグすると、キャラクターの向き（Facing Direction）を変更できる。
- **挙動**: スクリーン上のキャラクター位置を中心とした円周上のドラッグ位置に応じて回転する。
- **目的**: 移動せずにその場での向き調整を行うため。

#### パス上でのVisionポイント操作
パス描画モード外でも、既存のパスに対してVisionポイント（視線ポイント）を追加可能。

- **確認済みパス (Confirmed Path)**:
    - パス上を**0.5秒以上長押し**するとVisionモードが起動。
    - そのままドラッグして視線方向を決定し、リリースで確定。
    - 自動的にパス延長モードとして処理され、即座に反映される。

- **移動中のパス (Moving Path)**:
    - 移動中のパス上を**0.5秒以上長押し**するとVisionモードが起動。
    - ドラッグで視線方向を決定し、リリースで確定。
    - リアルタイムで実行中のパスにVisionポイントが挿入される。

#### ダブルタップでWait Point追加
パス上を**300ms以内に2回タップ**するとWait Point（待機ポイント）が追加される。

## PC vs モバイルの挙動

### モバイル (Touch) - TouchInputHandler
- **タップ閾値**: 20px（指の精度が低いため小さめ）
- **タップ vs パン**: `CameraPanController` 内で閾値判定を行い、短いタップはクリック（選択）、移動量が大きい場合はパンとして扱う。
- **ピンチズーム**: 2本指のピンチ操作でカメラズーム。
- **Pathモード**: パス上かどうかの判定を行い、パス上なら編集、パス外ならカメラ操作となる。

### PC (Mouse) - MouseInputHandler
- **タップ閾値**: 50px（マウスは精度が高いため大きめ）
- **左クリック**: プレス/リリース検出。
- **マウスホイール**: カメラズーム。
- **トラックパッドジェスチャー**: `InputEventMagnifyGesture`でピンチズームをエミュレート。
- 基本的なロジックはモバイルと同様だが、マウスイベントベースで動作する。

## メソッド

### セットアップ
#### `setup(manager: GameManager, pan_controller: CameraPanController) -> void`
必要な参照を設定し、入力ハンドラを初期化する。

### 入力ハンドリング
#### `_unhandled_input(event: InputEvent) -> void`
メインの入力処理。タッチイベント、マウスイベントを受け取り、優先順位に従って処理を振り分ける。

## 内部ヘルパーメソッド

- `_get_path_drawer() -> PathDrawer`: PathDrawerインスタンスを取得。
- `_try_start_immediate_path_mode(screen_pos) -> bool`: タップ位置のキャラクターで即時パスモードを開始できるか判定。
- `_try_start_path_continuation_from_endpoint(screen_pos) -> bool`: パス終点からの延長モードを開始できるか判定。
- `_is_near_path_endpoint(screen_pos) -> bool`: タップ位置がパス終点付近か判定。
- `_try_start_confirmed_path_longpress(screen_pos) -> bool`: 確認済みパスまたは移動中パス上での長押し判定。
- `_start_rotation_mode() -> void`: 長押し回転モードを開始。
- `_process_rotation_drag(screen_pos) -> void`: 回転モード中のドラッグ処理。

## 拡張性

将来的なゲームパッド対応は、`GamepadInputHandler`クラスを追加することで実現可能。`InputDeviceHandler`を継承し、必要なシグナルを発火するだけでInputControllerとの統合が可能。

## 関連クラス

- [GameScreen](GameScreen.md)
- [GameManager](GameManager.md)
- [CameraPanController](../Util/CameraPanController.md)
- [PathDrawer](../Effect/PathDrawer.md)
- [InputDeviceHandler](InputDeviceHandler.md)
