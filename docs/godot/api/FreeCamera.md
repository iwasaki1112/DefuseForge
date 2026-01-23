# FreeCamera

## 概要

テスト用のオービットカメラ。マウスドラッグで回転、ホイールでズームを行う。

## クラス情報

- **継承**: `Camera3D`
- **ファイル**: `scripts/tests/free_camera.gd`

## エクスポート変数

| 変数 | 型 | 説明 |
|------|----|------|
| `target` | `Vector3` | オービット中心 |
| `mouse_sensitivity` | `float` | ドラッグ感度 |
| `zoom_speed` | `float` | ズーム速度 |
| `min_distance` | `float` | 最小距離 |
| `max_distance` | `float` | 最大距離 |

## メソッド

### `set_yaw(yaw: float) -> void`
ヨー角を設定してカメラ位置を更新する。

### `set_distance(dist: float) -> void`
距離を設定してカメラ位置を更新する。

## APIリファレンス

### シグナル
なし

### メソッド
- `set_yaw(yaw: float) -> void`
- `set_distance(dist: float) -> void`
