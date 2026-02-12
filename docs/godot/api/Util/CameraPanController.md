# CameraPanController

カメラを平行移動・ズームする簡易コントローラー。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `RefCounted` |
| クラス名 | `CameraPanController` |
| ファイルパス | `scripts/utils/camera_pan_controller.gd` |

## 概要

PC（マウスドラッグ・ホイール）とモバイル（1本指パン・2本指ピンチズーム）の両方に対応したカメラ制御コントローラー。地上ターゲット位置を基準にカメラを移動・ズームする。

## プロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `camera` | `Camera3D` | `null` | 制御対象カメラ |
| `pan_speed` | `float` | `0.05` | PCマウスドラッグ時のパン速度 |
| `mobile_pan_speed` | `float` | `0.02` | モバイルタッチパン速度 |
| `zoom_speed` | `float` | `1.0` | ズーム速度 |
| `zoom_min` | `float` | `12.0` | 最小ズーム（カメラ高さ） |
| `zoom_max` | `float` | `25.0` | 最大ズーム（カメラ高さ） |
| `zoom_smoothing` | `float` | `10.0` | ズームスムージング速度 |
| `pan_smoothing` | `float` | `8.0` | パンスムージング速度 |

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `DRAG_THRESHOLD` | `5.0` | ドラッグ判定の閾値（ピクセル） |

## メソッド

### setup(target_camera: Camera3D, speed: float) -> void
カメラとパン速度を設定する。

### handle_input(event: InputEvent) -> bool
PC向け入力処理（マウスホイール・マウスドラッグ）。入力を消費した場合`true`を返す。

### track_touch(event: InputEvent) -> void
タッチポイントを追跡する（2本指検出用）。

### handle_pinch(event: InputEvent) -> bool
2本指ピンチズーム処理。

### handle_magnify_gesture(factor: float) -> void
Macトラックパッドのピンチジェスチャー処理。

### start_potential_drag(pos: Vector2) -> void
ドラッグ候補を開始する（左クリック押下時）。

### check_and_start_drag(current_pos: Vector2) -> bool
ドラッグが成立したかチェックする。

### is_dragging() -> bool
ドラッグ中かどうかを返す。

### end_drag() -> void
ドラッグを終了する。

### start_potential_touch_pan(pos: Vector2) -> void
1本指タッチパン候補を開始する。

### check_and_start_touch_pan(current_pos: Vector2) -> bool
1本指タッチパンが成立したかチェックする。

### start_touch_pan(pos: Vector2) -> void
1本指タッチパンを即座に開始する（閾値チェックなし）。

### update_touch_pan(current_pos: Vector2) -> bool
1本指タッチパンを更新する。

### end_touch_pan() -> void
1本指タッチパンを終了する。

### is_touch_panning() -> bool
1本指パン中かどうかを返す。

### is_pinching() -> bool
ピンチ中かどうかを返す。

### get_touch_count() -> int
現在のタッチポイント数を取得する。

### set_ground_target(target: Vector3) -> void
ターゲット位置を設定する（アニメーション付き）。

### set_ground_target_immediate(target: Vector3) -> void
ターゲット位置を即座に設定する（アニメーションなし）。

### move_ground_target(delta_x: float, delta_z: float) -> void
ターゲット位置を移動する（パン用）。

### process(delta: float) -> void
毎フレーム呼び出してズームとパンを滑らかに適用する。

## 使用例

```gdscript
var camera_pan = CameraPanController.new()
camera_pan.setup(camera, 0.05)

# 入力処理
func _input(event: InputEvent) -> void:
    camera_pan.track_touch(event)
    camera_pan.handle_pinch(event)
    camera_pan.handle_input(event)

# 毎フレーム更新
func _process(delta: float) -> void:
    camera_pan.process(delta)

# カメラをターゲットに移動
camera_pan.set_ground_target(character.global_position)
```

## 関連クラス

- [TPSPlayerController](../Controllers/TPSPlayerController.md) - TPS操作制御（カメラ追従）

## APIリファレンス

### メソッド
- `setup(target_camera: Camera3D, speed: float = 0.05) -> void`
- `handle_input(event: InputEvent) -> bool`
- `track_touch(event: InputEvent) -> void`
- `handle_pinch(event: InputEvent) -> bool`
- `handle_magnify_gesture(factor: float) -> void`
- `start_potential_drag(pos: Vector2) -> void`
- `check_and_start_drag(current_pos: Vector2) -> bool`
- `is_dragging() -> bool`
- `end_drag() -> void`
- `start_potential_touch_pan(pos: Vector2) -> void`
- `check_and_start_touch_pan(current_pos: Vector2) -> bool`
- `start_touch_pan(pos: Vector2) -> void`
- `update_touch_pan(current_pos: Vector2) -> bool`
- `end_touch_pan() -> void`
- `is_touch_panning() -> bool`
- `is_pinching() -> bool`
- `get_touch_count() -> int`
- `set_ground_target(target: Vector3) -> void`
- `set_ground_target_immediate(target: Vector3) -> void`
- `move_ground_target(delta_x: float, delta_z: float) -> void`
- `process(delta: float) -> void`
