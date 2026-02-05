# MovingPathVisionService

## 概要

移動中パスに追加されるVisionポイントの管理サービス。パス実行中のVisionポイントの追加・プレビュー・表示/非表示を担当する。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/systems/moving_path_vision_service.gd`

## 定数

| 定数 | 型 | 値 | 説明 |
|------|-----|-----|------|
| `POINT_REACHED_DISTANCE` | `float` | `1.0` | ポイント到達判定距離閾値（ユニット） |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `_mesh_parent` | `Node3D` | Visionポイントメッシュの親ノード |
| `_path_execution_manager` | `PathExecutionManager` | パス実行マネージャ参照 |
| `_preview` | `MeshInstance3D` | プレビュー用Visionポイント |
| `_vision_points` | `Dictionary` | キャラクターIDをキーとしたVisionポイント配列 |

## メソッド

### `setup(mesh_parent: Node3D, path_execution_manager) -> void`
サービスを初期化する。VisionPointスクリプトを遅延ロードする。

### `add_vision_point(character: Node, path_ratio: float, anchor: Vector3, target_point: Vector3) -> bool`
Visionポイントを移動中パスに追加する。プレビューがある場合は永続ポイントとして保持する。

### `update_preview(character: Node, anchor: Vector3, target_point: Vector3, path_ratio: float) -> void`
プレビュー用Visionポイントを更新する。無効な参照は自動的にクリアして再生成する。

### `clear_preview() -> void`
プレビューをクリアする。

### `clear_for_character(character: Node) -> void`
指定キャラクターのVisionポイントをすべてクリアする。

### `clear_all() -> void`
全キャラクターのVisionポイントをクリアする。

### `hide_passed_points(character: Node, current_ratio: float) -> void`
キャラクターの現在位置に基づいて通過済みポイントを非表示にする。

### `recalculate_ratios_on_scale(character: Node, full_path: Array[Vector3], ratio_calculator: Callable) -> void`
パス拡張時にVisionポイントの比率をアンカー位置から再計算する。

### `has_points_for_character(character: Node) -> bool`
キャラクターにVisionポイントがあるか確認する。

### `get_points_for_character(character: Node) -> Array`
キャラクターのVisionポイント配列を取得する。

## 関連クラス

- [GameManager](GameManager.md)
- [PathExecutionManager](PathExecutionManager.md)
- [VisionService](VisionService.md)
