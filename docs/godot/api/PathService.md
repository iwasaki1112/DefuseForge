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
| `clear_point_added` | Clearポイント追加 |

## 主なメソッド

### `setup(drawer, sel_manager, exec_manager, mode_controller, marker_panel) -> void`
依存コンポーネントを接続する。

### `start_move_mode() -> bool`
選択中キャラクターで移動パス描画を開始する。

### `start_path_mode(primary: Node, char_color: Color = Color.WHITE) -> bool`
指定キャラクターでパス描画を開始する。

### `confirm_path() -> void`
描画したパスを確定する。

### `cancel_path() -> void`
パス描画をキャンセルする。

### `execute_all_paths(run: bool) -> int`
全パスを実行する。

### `clear_all_pending_paths() -> void`
保留中のパスをクリアする。

### `cancel_all_path_following() -> void`
全キャラクターのパス追従をキャンセルする。

### `cancel_path_following(character: Node, clear_pending: bool = true) -> void`
指定キャラクターのパス追従をキャンセルする。

### `process_controllers(delta: float) -> void`
パス関連コントローラーの更新処理を呼び出す。

### `is_path_mode() -> bool`
パスモード中か判定する。

### `has_pending_path() -> bool`
未確定パスがあるか判定する。

### `get_pending_path_count() -> int`
保留中パス数を取得する。

### `get_path_target_count() -> int`
パス対象キャラクター数を取得する。

### `is_any_path_following_active() -> bool`
いずれかのキャラクターがパス追従中か判定する。

### `is_character_following_path(character: Node) -> bool`
指定キャラクターがパス追従中か判定する。

### `handle_click_to_cancel(clicked_character: Node) -> bool`
パスモード時のクリックキャンセル処理を委譲する。

### `is_marker_mode() -> bool`
視線/Runマーカー設定モードか判定する。

### `start_vision_mode() -> bool`
視線ポイントの追加モードを開始する。

### `remove_last_vision_point() -> void`
最後の視線ポイントを削除する。

### `start_run_mode() -> void`
Run区間追加モードを開始する。

### `remove_last_run_segment() -> void`
最後のRun区間を削除する。

### `start_clear_mode() -> void`
Clearポイント追加モードを開始する。

### `remove_last_clear_point() -> void`
最後のClearポイントを削除する。

### `get_vision_point_count() -> int`
視線ポイント数を取得する。

### `get_run_segment_count() -> int`
Run区間数を取得する。

### `get_clear_point_count() -> int`
Clearポイント数を取得する。

### `has_incomplete_run_start() -> bool`
Run開始のみ設定された未完了区間があるか判定する。

### `is_multi_character_mode() -> bool`
マルチキャラクターモード中か判定する。

### `start_multi_character_mode(selected_chars: Array[Node]) -> void`
マルチキャラクターモードを開始する。

### `set_active_edit_character(character: Node) -> void`
編集中のキャラクターを設定する。

### `set_path_drawer_color(color: Color) -> void`
パス描画色を変更する。

## 関連クラス

- [GameManager](GameManager.md)
- [PathDrawer](PathDrawer.md)
- [PathModeController](PathModeController.md)
- [PathExecutionManager](PathExecutionManager.md)
- [MarkerEditPanel](MarkerEditPanel.md)

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `mode_started` | `character: Node` |
| `mode_ended` | なし |
| `mode_cancelled` | なし |
| `path_ready` | なし |
| `path_confirmed` | `count: int` |
| `all_paths_completed` | なし |
| `paths_cleared` | なし |
| `mode_changed` | `mode: int` |
| `vision_point_added` | `anchor: Vector3, direction: Vector3` |
| `run_segment_added` | `start_ratio: float, end_ratio: float` |
| `clear_point_added` | `path_ratio: float` |

### メソッド
- `setup(`
- `start_move_mode() -> bool`
- `start_path_mode(primary: Node, char_color: Color = Color.WHITE) -> bool`
- `confirm_path() -> void`
- `cancel_path() -> void`
- `execute_all_paths(run: bool) -> int`
- `clear_all_pending_paths() -> void`
- `cancel_all_path_following() -> void`
- `cancel_path_following(character: Node, clear_pending: bool = true) -> void`
- `process_controllers(delta: float) -> void`
- `is_path_mode() -> bool`
- `has_pending_path() -> bool`
- `get_pending_path_count() -> int`
- `get_path_target_count() -> int`
- `is_any_path_following_active() -> bool`
- `is_character_following_path(character: Node) -> bool`
- `handle_click_to_cancel(clicked_character: Node) -> bool`
- `is_marker_mode() -> bool`
- `start_vision_mode() -> bool`
- `remove_last_vision_point() -> void`
- `start_run_mode() -> void`
- `remove_last_run_segment() -> void`
- `start_clear_mode() -> void`
- `remove_last_clear_point() -> void`
- `get_vision_point_count() -> int`
- `get_run_segment_count() -> int`
- `get_clear_point_count() -> int`
- `has_incomplete_run_start() -> bool`
- `is_multi_character_mode() -> bool`
- `start_multi_character_mode(selected_chars: Array[Node]) -> void`
- `set_active_edit_character(character: Node) -> void`
- `set_path_drawer_color(color: Color) -> void`
