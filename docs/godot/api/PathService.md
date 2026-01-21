# PathService

## 概要

パス描画・編集・実行をまとめて扱うサービス。PathDrawer、PathModeController、PathExecutionManager、MarkerEditPanelの調整を担う。

## クラス情報

- **継承**: `Node`
- **ファイル**: `scripts/systems/path_service.gd`

## シグナル

| シグナル | 説明 |
|---------|------|
| `mode_started` | パスモード開始 |
| `mode_ended` | パスモード終了 |
| `mode_cancelled` | パスモードキャンセル |
| `path_ready` | パス描画完了 |
| `path_confirmed` | パス確定 |
| `all_paths_completed` | 全パス実行完了 |
| `paths_cleared` | パスクリア |
| `mode_changed` | パス描画モード変更 |
| `vision_point_added` | 視線ポイント追加 |
| `run_segment_added` | Run区間追加 |

## 主なメソッド

### `setup(drawer, sel_manager, exec_manager, mode_controller, marker_panel) -> void`
依存コンポーネントを接続する。

### `start_move_mode() -> bool`
選択中キャラクターで移動パス描画を開始する。

### `confirm_path() -> void`
描画したパスを確定する。

### `cancel_path() -> void`
パス描画をキャンセルする。

### `execute_all_paths(run: bool) -> int`
全パスを実行する。

### `clear_all_pending_paths() -> void`
保留中のパスをクリアする。

### `is_marker_mode() -> bool`
視線/Runマーカー設定モードか判定する。

## 関連クラス

- [GameManager](GameManager.md)
- [PathDrawer](PathDrawer.md)
- [PathModeController](PathModeController.md)
- [PathExecutionManager](PathExecutionManager.md)
- [MarkerEditPanel](MarkerEditPanel.md)
