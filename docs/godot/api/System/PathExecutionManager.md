# PathExecutionManager

## 概要

パスの確定・保存・実行を一元管理するクラス。`GameManager`の下で動作し、各キャラクターのパス追従コントローラー（`PathFollowingController`）の生成とライフサイクル管理、およびネットワーク同期のためのデータ管理を行う。

## クラス情報

- **継承**: `Node`
- **ファイル**: `scripts/systems/path_execution_manager.gd`
- **クラス名**: `PathExecutionManager`

## 機能

- **パス確定**: PathDrawerで描画されたパスをキャラクターごとの実行用データに変換して保存。
- **接続線自動生成**: キャラクターの現在位置からパス開始点までの移動経路を自動補完。
- **マーカー再計算**: 接続線の長さに応じて、視線やアクションマーカーのパス上の位置（比率）を再計算。
- **パス実行**: 保存されたパスデータに基づき、`PathFollowingController`を生成して移動を開始。
- **衝突回避優先度**: 実行順序に基づいて各キャラクターに移動優先度を割り当て。
- **マルチプレイヤー同期**: ネットワーク経由で受信したパスデータの登録・管理。

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `path_confirmed` | `character_count: int` | パスが確定された時 |
| `paths_execution_started` | `count: int` | 全パスの実行が開始された時 |
| `all_paths_completed` | なし | 全キャラクターの移動が完了した時 |
| `paths_cleared` | なし | 全ての保留パスがクリアされた時 |
| `character_path_completed` | `character: Node` | 個別のキャラクターが移動完了した時 |
| `grenade_marker_reached` | `character: Node, marker_data: Dictionary` | グレネードマーカー到達時 |
| `smoke_grenade_marker_reached` | `character: Node, marker_data: Dictionary` | スモークマーカー到達時 |
| `door_marker_reached` | `character: Node, door: Node3D` | ドアマーカー到達時 |

## Public API

### Setup

#### `setup(mesh_parent: Node3D) -> void`
パスメッシュやコントローラーを追加する親ノードを設定する。

### Path Confirmation

#### `confirm_path(target_characters: Array[Node], path_drawer: Node, _primary_character: Node) -> bool`
PathDrawerの描画データを取得し、対象キャラクター（現在はシングルのみサポート）の保留パスとして確定する。
元のマーカーメッシュは削除され、キャラクターごとの新しいマーカーが生成される。

### Execution

#### `execute_all_paths(run: bool) -> int`
保留中の全てのパスを実行開始する。
各キャラクターに`PathFollowingController`を割り当て、実行順序に基づく優先度を設定する。

#### `execute_direct_path(character: CharacterBody3D, target_pos: Vector3, run: bool = false) -> bool`
UI操作を経ずに、直接指定座標への移動を実行する（ドアキック時の自動移動など）。

### Management

#### `clear_all_pending_paths() -> void`
全ての保留パスデータとメッシュを削除する。

#### `cancel_all_path_following() -> void`
実行中の全ての移動をキャンセルする。

#### `cancel_path_following(character: Node, clear_pending: bool = true) -> void`
指定キャラクターの移動をキャンセルする。

#### `process_controllers(delta: float) -> void`
毎フレーム呼び出し、各コントローラーの更新処理を行う。

### Moving Path Operations

#### `find_moving_path_point_at_position(ground_pos: Vector3, threshold: float = 0.5) -> Dictionary`
移動中のパス上で、指定座標に近い点を検索する（Visionマーカー追加用）。

#### `find_moving_path_endpoint_at_position(ground_pos: Vector3, threshold: float = 0.5) -> Dictionary`
移動中のパスの終点を検索する（パス延長用）。

#### `find_path_point_at_position(ground_pos: Vector3, threshold: float = 0.5) -> Dictionary`
確定済みパス上で、指定座標に近い点を検索する（Visionマーカー追加用）。

#### `add_vision_marker_to_moving_path(character: Node, path_ratio: float, anchor: Vector3, target_point: Vector3) -> bool`
移動中のパスにVisionマーカーを動的に追加する。

#### `get_remaining_path_for_character(character: Node, get_extension: bool = false) -> Dictionary`
移動中のキャラクターの残りパスデータを取得する。

#### `set_extension_path_for_character(character: Node, extension_path: Array[Vector3], markers: Dictionary, append_to_existing: bool = false) -> bool`
移動中のキャラクターに延長パスを設定する。

#### `cancel_extension_for_character(character: Node) -> void`
設定された延長パスをキャンセルする。

#### `take_pending_path_for_editing(character: Node) -> Dictionary`
指定キャラクターの保留パスを編集用に取り出す（pending_pathsからは削除される）。

### Query

#### `get_pending_path_count() -> int`
保留中のパス数を取得。

#### `has_pending_path_for_character(character: Node) -> bool`
指定キャラクターに保留パスが存在するか確認。

#### `is_any_path_following_active() -> bool`
いずれかのキャラクターが移動中か確認。

#### `is_character_following_path(character: Node) -> bool`
指定キャラクターが移動中か確認。

#### `get_character_progress(character: Node) -> float`
指定キャラクターの現在のパス進行率（0.0〜1.0）を取得。

#### `get_character_waiting_state(character: Node) -> Dictionary`
指定キャラクターの待機状態（Wait/Door/ClosedDoor）を取得。

#### `get_all_progress() -> Dictionary`
全アクティブキャラクターの進行状況と待機状態を取得。

### Multiplayer API

#### `confirm_path_for_player(player_id: int, path_msg: NetworkMessages.PathConfirmMessage, character: Node) -> bool`
ネットワークメッセージからパスを確定する（他プレイヤーのパス受信時）。

#### `get_pending_paths_for_player(player_id: int) -> Dictionary`
指定プレイヤーIDに関連付けられた保留パスを取得。

#### `to_path_confirm_message(character: Node, player_id: int) -> NetworkMessages.PathConfirmMessage`
キャラクターの保留パスをネットワーク送信用のメッセージ形式に変換。

#### `get_path_snapshot(character: Node) -> SyncState.PathSnapshot`
キャラクターの現在の移動状態（実行中か、進行率はいくつか）をスナップショットとして取得。

## データ構造

### Pending Path Dictionary
`pending_paths` には以下の構造でデータが保持される:

```gdscript
{
    character_id: {
        "character": Node,
        "path": Array[Vector3],
        "vision_points": Array[Dictionary],
        "run_segments": Array[Dictionary],
        "clear_points": Array[Dictionary],
        "grenade_markers_data": Array[Dictionary],
        # ... 他マーカーデータ
        "path_mesh": MeshInstance3D,
        "vision_markers": Array[MeshInstance3D],
        # ... 他マーカーメッシュ
    }
}
```

## 関連クラス

- [PathFollowingController](../Character/PathFollowingController.md)
- [PathDrawer](../Effect/PathDrawer.md)
- [NetworkMessages](../Network/NetworkMessages.md)