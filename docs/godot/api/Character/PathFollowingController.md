# PathFollowingController

パス追従を管理するコントローラークラス。キャラクターが描画されたパスに沿って移動し、視線ポイントで向きを変える。
Run区間では走行速度で移動し、敵認識・視線ポイントを無視する。Waitマーカーでは指定時間アイドル待機する。
Door Kickers 2スタイルの協調的衝突回避（Sidestep）ロジックを実装している。

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

### 衝突回避 (Sidestep)
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `collision_check_radius` | `float` | `0.8` | 前方衝突検出の横方向半径 |
| `collision_check_distance` | `float` | `1.5` | 前方衝突検出の距離 |
| `avoidance_timeout` | `float` | `3.0` | 衝突回避タイムアウト（秒）- この時間経過で強制解除 |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `path_started` | なし | パス追従開始時 |
| `path_completed` | なし | パス追従正常完了時 |
| `path_cancelled` | なし | パス追従キャンセル時 |
| `vision_point_reached` | `index: int, direction: Vector3` | 視線ポイント到達時 |
| `grenade_marker_reached` | `index: int, marker_data: Dictionary` | グレネードマーカー到達時 |
| `smoke_grenade_marker_reached` | `index: int, marker_data: Dictionary` | スモークグレネードマーカー到達時 |
| `door_marker_reached` | `index: int, door: Node3D` | ドアマーカー到達時（パス一時停止） |

## Public API

### Setup

#### `setup(character: CharacterBody3D) -> void`
コントローラーをセットアップする。

#### `set_combat_awareness(component: Node) -> void`
CombatAwarenessComponentを設定する（敵自動追跡用）。

### Path Execution

#### `start_path(...) -> bool`
パス追従を開始する。

**引数:**
- `path`: `Array[Vector3]`
- `vision_points`: `Array[Dictionary]`
- `run_segments`: `Array[Dictionary]`
- `run`: `bool` (全体走行フラグ)
- `clear_points`: `Array[Dictionary]`
- `grenade_markers`: `Array[Dictionary]`
- `door_markers`: `Array[Dictionary]`
- `wait_markers`: `Array[Dictionary]`
- `smoke_grenade_markers`: `Array[Dictionary]`

#### `cancel() -> void`
パス追従をキャンセルする。

#### `is_following_path() -> bool`
パス追従中か確認する。

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

### 衝突回避（Door Kickers 2スタイル）

複数キャラクターがパス上で衝突した場合、以下のルールで協調的に回避する。

1.  **優先度判定**:
    *   先にパス実行を開始したキャラクターが高優先（`movement_priority`値が小さい）。
    *   開始時刻が同じ場合、パス進行率が高い方が高優先。
    *   それも同じならキャラクターIDで決定。

2.  **回避動作 (Sidestep)**:
    *   **高優先度キャラ**: そのまま直進する。
    *   **低優先度キャラ**: 右側（進行方向に対して時計回り90度）へサイドステップして道を譲る。
    *   右側が壁の場合は左側へ避ける。

3.  **Head-on（対面）判定**:
    *   互いに向かい合って移動している場合（`dot < -0.5`）、または相手が既に回避待機中の場合は、低優先度側が即座に回避行動をとる。

### マーカー処理

*   **Grenade/Smoke**: 到達時にシグナルを発火し、移動を止めずに投擲アクションを行う。
*   **Door**: 到達時にパスを一時停止し、`door_marker_reached`を発火。ドアキック等の完了を待つ。
*   **Wait**: 到達時にパスを一時停止し、指定時間（`wait_duration`）待機する。
*   **Clear**: 視線方向とRun状態をリセットし、進行方向を向く。

### 閉じたドア待機

移動方向に閉じたドアがあり、かつDoorマーカーが設定されていない場合、キャラクターはドアの手前で自動的に停止し、ドアが開くのを待つ（`_is_waiting_for_closed_door`）。