# PathFollowingController

パス追従を管理するコントローラークラス。キャラクターが描画されたパスに沿って移動し、視線ポイントで向きを変える。
Run区間では走行速度で移動し、敵認識・視線ポイントを無視する。Waitポイントでは指定時間アイドル待機する。
ソフト分離力ベースの協調的衝突回避ロジックを実装している。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/characters/path_following_controller.gd` |

## 依存関係

> **Note:** `CharacterAnimationController`が必須。速度設定は`CharacterAnimationController`で一元管理される。

## Export Properties

### スタック検出
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `stuck_threshold` | `float` | `0.01` | スタック検出の移動距離閾値 |
| `stuck_timeout` | `float` | `0.5` | スタック判定時間（秒）- この時間進めないと次のポイントへスキップ |
| `final_destination_radius` | `float` | `0.1` | 最終目的地への到達判定半径 |
| `ally_collision_radius` | `float` | `1.0` | 味方との衝突検出半径（最終地点での重なり防止） |

### 移動スムージング
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `direction_smoothing` | `float` | `8.0` | 移動方向のスムージング係数（大きいほど追従が速い） |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `path_started` | なし | パス追従開始時 |
| `path_completed` | なし | パス追従正常完了時 |
| `path_cancelled` | なし | パス追従キャンセル時 |
| `vision_point_reached` | `index: int, direction: Vector3` | 視線ポイント到達時 |
| `grenade_point_reached` | `index: int, point_data: Dictionary` | グレネードポイント到達時 |
| `smoke_grenade_point_reached` | `index: int, point_data: Dictionary` | スモークグレネードポイント到達時 |
| `door_point_reached` | `index: int, door: Node3D` | ドアポイント到達時（パス一時停止） |
| `wait_point_reached` | `index: int, point_data: Dictionary` | 待機ポイント到達時 |
| `path_progress_updated` | `index: int, character: Node` | パス進行状況更新時（通過したポイントのインデックス） |
| `extension_path_activated` | `character: Node` | 延長パスへの切り替え発生時 |
| `extension_points_scaled` | `scale: float` | 延長ポイントの比率がスケールされた時 |
| `sync_wait_started` | なし | 同期待機開始時 |
| `sync_wait_released` | なし | 同期待機解放時 |

## Public API

### Setup

#### `setup(character: CharacterBody3D) -> void`
コントローラーをセットアップする。

#### `set_combat_awareness(component: Node) -> void`
CombatAwarenessComponentを設定する（敵自動追跡用）。

### Path Execution

#### `start_path(...) -> bool`
パス追従を開始する。

#### `set_extension_path(path: Array, markers: Dictionary, append: bool) -> void`
移動中に延長パスを設定する。現在のパス完了後にシームレスに移行する。

#### `cancel_extension() -> void`
設定された延長パスをキャンセルする。

#### `add_vision_point_to_extension(...) -> void`
移動中のパス（または延長パス）にVisionポイントを追加する。

#### `get_remaining_path_data() -> Dictionary`
現在の位置からゴールまでの残りパスデータを取得する。

#### `cancel() -> void`
パス追従をキャンセルする。

#### `is_following_path() -> bool`
パス追従中か確認する。

#### `is_active() -> bool`
パス追従中かどうか（is_following_pathと同じ）。

#### `add_wait_point(point_data: Dictionary) -> void`
実行中のパスにWaitポイントを追加する。
引数: `{ path_ratio, anchor, wait_duration }`

#### `release_sync_wait() -> void`
同期待機を解除して移動を再開する。

#### `is_sync_waiting() -> bool`
同期待機中かどうかを確認する。

#### `append_path_point(point: Vector3) -> void`
現在のパスの末尾にポイントを追加する（移動中の延長用）。

#### `get_path_endpoint() -> Vector3`
現在のパスの終点を取得する。

#### `get_current_path_packed() -> PackedVector3Array`
現在の全パスをPackedVector3Arrayとして取得する（メッシュ更新用）。

### Extension Path Accessors

#### `get_full_remaining_path() -> PackedVector3Array`
現在位置からゴールまでの残りのパスポイント（延長パス含む）を取得する。

#### `get_remaining_path_data() -> Dictionary`
現在のメインパスの残りデータを取得する。

#### `get_extension_path_data() -> Dictionary`
設定されている延長パスのデータを取得する。

#### `get_extension_path_endpoint() -> Vector3`
延長パスの終点を取得する。

#### `has_extension_path() -> bool`
延長パスが設定されているか確認する。

### Avoidance Logic

#### `set_movement_priority(priority: int) -> void`
衝突回避用の移動優先度を設定する。値が低いほど高優先（先に移動開始したキャラが強い）。

#### `get_movement_priority() -> int`
現在の移動優先度を取得する。

### Update

#### `process(delta: float) -> void`
毎フレームの処理を実行する。`_physics_process`から呼び出す。

### State Query

#### `get_current_progress() -> float`
現在のパス進行率（0.0〜1.0）を取得する。衝突回避の優先度判定にも使用される。

#### `get_waiting_state() -> Dictionary`
現在の待機状態を取得する（Wait/Door/ClosedDoor）。
戻り値: `{"is_waiting": bool, "type": String, "remaining": float}`

## 内部動作

### 衝突回避（ソフト分離力方式）

複数キャラクターが近接した場合、距離に比例したソフトな横方向分離力を適用して自然にすれ違う。
キャラクターはパス追従を中断せず、常に移動を継続する。

1.  **近接味方スキャン**（100ms間隔）:
    *   `SEPARATION_RADIUS`（2.0m）内の生存している味方を全方向から検出。
    *   前方コーン限定ではなく全方位をスキャン。

2.  **分離力の計算**:
    *   各味方との距離に基づく線形減衰力（`MIN_SEPARATION_DISTANCE`で最大、`SEPARATION_RADIUS`でゼロ）。
    *   パス方向に対して垂直成分のみ抽出（lateral projection）。
    *   優先度に応じた非対称力: 低優先度キャラは`YIELD_FORCE_FACTOR`(0.8x)、高優先度キャラは`PRIORITY_FORCE_FACTOR`(0.3x)。
    *   複数味方からの力を合算し、最大速度の1.5倍でクランプ。

3.  **優先度判定**:
    *   先にパス実行を開始したキャラクターが高優先（`movement_priority`値が小さい）。
    *   開始時刻が同じ場合、パス進行率が高い方が高優先。
    *   それも同じならキャラクターIDで決定。

4.  **Head-on（対面）判定**:
    *   互いに向かい合って移動している場合（`dot < -0.5`）、決定論的横バイアスを追加。
    *   低優先度→右、高優先度→左に分かれて通過。

5.  **パス復帰**:
    *   味方が離れると分離力が自然にゼロに戻る。
    *   既存のスムージング処理でパスに自然に復帰。

### パス進行
- **目標点到達判定**: 現在の目標ポイントへの距離が **0.25m** 未満になると、次のポイントへ切り替わる。
- **最終目的地判定**: 最終目的地への距離が `final_destination_radius` (デフォルト0.1m) 未満になると完了。

### マーカー処理

*   **Grenade/Smoke**: 到達時にシグナルを発火し、移動を止めずに投擲アクションを行う。
*   **Door**: 到達時にパスを一時停止し、`door_point_reached`を発火。ドアキック等の完了を待つ。
*   **Wait**: 到達時にパスを一時停止し、指定時間（`wait_duration`）待機する。
*   **Clear**: 視線方向とRun状態をリセットし、進行方向を向く。

### 閉じたドア待機

移動方向に閉じたドアがあり、かつDoorポイントが設定されていない場合、キャラクターはドアの手前で自動的に停止し、ドアが開くのを待つ（`_is_waiting_for_closed_door`）。