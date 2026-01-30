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

### 2. パスモード (Path Mode & Immediate Mode)
`GameManager.is_path_mode()` が true、またはキャラクターのドラッグ操作時:

- **即時パスモード (Immediate Path Mode)**:
    - パス未設定のキャラクターをタップすると即座に選択状態になる。
    - そのままドラッグを開始すると、モード切替ボタンを押さなくても直感的にパス描画を開始できる。
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

#### パス上でのVisionマーカー操作
パス描画モード外でも、既存のパスに対してVisionマーカー（視線ポイント）を追加可能。

- **確認済みパス (Confirmed Path)**:
    - パス上を**0.5秒以上長押し**するとVisionモードが起動。
    - そのままドラッグして視線方向を決定し、リリースで確定。
    - 自動的にパス延長モードとして処理され、即座に反映される。

- **移動中のパス (Moving Path)**:
    - 移動中のパス上を**0.5秒以上長押し**するとVisionモードが起動。
    - ドラッグで視線方向を決定し、リリースで確定。
    - リアルタイムで実行中のパスにVisionポイントが挿入される。

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

## 内部ヘルパーメソッド

- `_is_touch_active() -> bool`: タッチ操作中かどうか判定。
- `_get_ground_position(screen_pos) -> Vector3`: スクリーン座標から地面座標（Y=0平面）へのレイキャストを行う。
- `_get_path_drawer() -> PathDrawer`: PathDrawerインスタンスを取得。
- `_try_start_immediate_path_mode(screen_pos) -> bool`: タップ位置のキャラクターで即時パスモードを開始できるか判定。
- `_try_start_path_extension_from_endpoint(screen_pos) -> bool`: パス終点からの延長モードを開始できるか判定。
- `_is_near_path_endpoint(screen_pos) -> bool`: タップ位置がパス終点付近か判定。
- `_try_start_confirmed_path_longpress(screen_pos) -> bool`: 確認済みパスまたは移動中パス上での長押し判定。
- `_start_rotation_mode() -> void`: 長押し回転モードを開始。
- `_process_rotation_drag(screen_pos) -> void`: 回転モード中のドラッグ処理。

## 関連クラス

- [GameScreen](GameScreen.md)
- [GameManager](GameManager.md)
- [CameraPanController](../Util/CameraPanController.md)
- [PathDrawer](../Effect/PathDrawer.md)