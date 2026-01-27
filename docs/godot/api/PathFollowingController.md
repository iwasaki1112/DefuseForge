# PathFollowingController

パス追従を管理するコントローラークラス。キャラクターが描画されたパスに沿って移動し、視線ポイントで向きを変える。Run区間では走行速度で移動し、敵認識・視線ポイントを無視する。Waitマーカーでは指定時間アイドル待機する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/characters/path_following_controller.gd` |

## 依存関係

> **Note:** `CharacterAnimationController`が必須。速度設定は`CharacterAnimationController`で一元管理される。

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `stuck_threshold` | `float` | `0.01` | スタック検出の移動距離閾値 |
| `stuck_timeout` | `float` | `0.5` | スタック判定時間（秒）- この時間進めないと次のポイントへスキップ |
| `final_destination_radius` | `float` | `0.1` | 最終目的地への到達判定半径 |
| `ally_collision_radius` | `float` | `1.0` | 味方との衝突検出半径 |
| `collision_check_radius` | `float` | `0.8` | 前方衝突検出の横方向半径 |
| `collision_check_distance` | `float` | `1.5` | 前方衝突検出の距離 |
| `avoidance_timeout` | `float` | `3.0` | 衝突回避タイムアウト（秒）- この時間経過で強制解除 |

## Signals

### path_started()
パス追従が開始された時に発火。

### path_completed()
パス追従が正常に完了した時に発火。

### path_cancelled()
パス追従がキャンセルされた時に発火。

### vision_point_reached(index: int, direction: Vector3)
視線ポイントに到達した時に発火。

**引数:**
- `index` - 到達した視線ポイントのインデックス
- `direction` - 設定された視線方向

## Public API

### setup(character: CharacterBody3D) -> void
コントローラーをセットアップする。

**引数:**
- `character` - 制御対象のキャラクター

### set_combat_awareness(component: Node) -> void
CombatAwarenessComponentを設定する。

**引数:**
- `component` - 敵自動追跡用のコンポーネント

### start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [], run_segments: Array[Dictionary] = [], run: bool = false, clear_points: Array[Dictionary] = [], grenade_markers: Array[Dictionary] = [], door_markers: Array[Dictionary] = [], wait_markers: Array[Dictionary] = []) -> bool
パス追従を開始する。

**引数:**
- `path` - 追従するパス（Vector3の配列、最低2点必要）
- `vision_points` - 視線ポイント配列（`path_ratio`と`target_point`を含むDictionary、後方互換で`direction`も対応）
- `run_segments` - Run区間配列（`start_ratio`と`end_ratio`を含むDictionary）
- `run` - 全体を走行モードで移動するか
- `clear_points` - Clearポイント配列（`path_ratio`を含むDictionary）
- `grenade_markers` - グレネードマーカー配列
- `door_markers` - ドアマーカー配列
- `wait_markers` - Waitマーカー配列（`path_ratio`と`wait_duration`を含むDictionary）

**戻り値:** 開始成功なら`true`

### cancel() -> void
パス追従をキャンセルする。

### is_following_path() -> bool
パス追従中か確認する。

**戻り値:** 追従中なら`true`

### set_movement_priority(priority: int) -> void
衝突回避用の移動優先度を設定する。`PathExecutionManager`から自動的に呼ばれる。

**引数:**
- `priority` - 優先度（低い値ほど高優先）

### get_movement_priority() -> int
現在の移動優先度を取得する。

**戻り値:** 優先度の値

### process(delta: float) -> void
毎フレームの処理を実行する。`_physics_process`から呼び出す。

**引数:**
- `delta` - デルタタイム

## 使用例

```gdscript
# セットアップ
var path_controller = PathFollowingController.new()
add_child(path_controller)
path_controller.path_completed.connect(_on_path_completed)

# パス追従開始
path_controller.setup(character)
var path: Array[Vector3] = [Vector3(0,0,0), Vector3(5,0,0), Vector3(5,0,5)]
# ターゲットポイントモード: キャラクターはこの地点を見続ける
var vision_points = [
    {"path_ratio": 0.5, "target_point": Vector3(10, 0, 5)}
]
var run_segments = [
    {"start_ratio": 0.3, "end_ratio": 0.6}  # 30%〜60%の区間を走る
]
var clear_points = [
    {"path_ratio": 0.8}  # 80%の位置で視線・Run効果をリセット
]
var wait_markers = [
    {"path_ratio": 0.4, "wait_duration": 2.0}  # 40%の位置で2秒待機
]
path_controller.start_path(path, vision_points, run_segments, false, clear_points, [], [], wait_markers)

# 毎フレーム処理
func _physics_process(delta):
    if path_controller.is_following_path():
        path_controller.process(delta)
```

## データ形式

### 視線ポイント（ターゲットポイントモード）
```gdscript
{
    "path_ratio": 0.5,       # パス上の位置（0.0〜1.0）
    "target_point": Vector3(...)  # ターゲット地点（キャラクターが見続ける位置）
}
```

キャラクターはマーカー到達後、`target_point`を動的に見続ける。移動中も毎フレーム方向を再計算する。

### 視線ポイント（後方互換: 固定方向モード）
```gdscript
{
    "path_ratio": 0.5,       # パス上の位置（0.0〜1.0）
    "direction": Vector3(...)  # 視線方向（正規化済み）
}
```

### Run区間
```gdscript
{
    "start_ratio": 0.3,  # 開始位置（0.0〜1.0）
    "end_ratio": 0.6     # 終了位置（0.0〜1.0）
}
```

### Clearポイント
```gdscript
{
    "path_ratio": 0.8    # パス上の位置（0.0〜1.0）
}
```

このポイントに到達すると、現在の視線方向とRun状態がリセットされ、キャラクターは進行方向を向く。

### Waitポイント
```gdscript
{
    "path_ratio": 0.6,      # パス上の位置（0.0〜1.0）
    "wait_duration": 3.0    # 待機時間（秒）
}
```

このポイントに到達すると、キャラクターは指定時間アイドル待機する。待機完了後、パス追従を再開する。

## 内部動作

- パス上の各ポイントに順番に移動
- 目標点への距離が0.15未満になると次のポイントへ
- 視線ポイントはパスの進行率（0.0〜1.0）で管理
- `CharacterAnimationController`と連携してアニメーションを更新

### facing_directionの同期

PathFollowingControllerは移動中に`GameCharacter._facing_direction`を更新する。これは`VisionComponent`が視界の向きを決定するために参照する。

```gdscript
# PathFollowingController内部
anim_ctrl.update_animation(move_dir, look_dir, is_running_now, delta)

# VisionComponent用にGameCharacterの向きを同期
if look_dir.length_squared() > 0.001:
    _character._facing_direction = look_dir.normalized()
```

**重要**: この同期がないと、移動中に視界の向きが更新されず、初期向きのままになる。

### パス完了時の向き（優先順位）

パス追従完了時のキャラクターの向きは、以下の優先順位で決定される：

1. **敵視認**（最優先）- CombatAwarenessが敵を追跡中の場合
2. **視線ポイント**（target_point）- 最後に有効だった視線方向
3. **最後の移動方向** - パス追従中の最後の移動方向

### ターゲットポイントモード

視線ポイントに`target_point`が設定されている場合、キャラクターは移動しながらその地点を見続ける:

1. 視線ポイントに到達すると`_active_target_point`にターゲット位置を保存
2. 毎フレーム、キャラクターの現在位置からターゲットへの方向を再計算
3. 次の視線ポイントが有効になるまで、または移動完了まで追従を継続

これにより、固定方向ではなく「特定の地点を見続ける」自然な動きが実現される。

### パス進行率の計算

視線ポイント・Run区間の発動タイミングを決定するパス進行率は、**キャラクターの実際の位置**に基づいて計算される：

1. パス全体の距離を計算
2. 各セグメントを調べ、キャラクターに最も近い点を特定
3. パス開始点からその最近点までの累積距離を算出
4. 累積距離 / 全体距離 = 進行率（0.0〜1.0）

この方式により、接続線（キャラクター現在位置→パス開始点）がある場合でも、視線ポイントやRun区間が正確なタイミングで発動する。

### Run区間の動作

Run区間内では以下の特殊処理が適用される：

1. **走行速度**: `CharacterAnimationController.run_speed`を使用
2. **敵認識無効**: `CombatAwarenessComponent.process()`をスキップ（敵をスルー）
3. **視線ポイント無視**: 視線方向は常に移動方向と一致（振り向かない）

これにより、Run区間内ではキャラクターは前方を向いたまま全力で走り抜ける。

### Clearポイントの動作

Clearポイントに到達すると、以下の処理が行われる：

1. **視線方向リセット**: `_forced_look_direction`をクリア（進行方向を向く）
2. **ターゲットポイントリセット**: `_active_target_point`をクリア

これにより、Clearポイント以降はVision/Runの効果がリセットされ、キャラクターは単純に進行方向を向いて歩く状態に戻る。

### Waitマーカーの動作

Waitマーカーに到達すると、以下の処理が行われる：

1. **待機開始**: `_is_waiting_for_wait`フラグを立て、移動を一時停止
2. **待機時間カウント**: `_wait_timer`で経過時間を計測
3. **アイドルアニメーション**: 待機中は`_update_idle_animation_while_waiting()`でアイドル状態を維持
4. **待機完了**: `wait_duration`が経過したら、フラグをクリアしてパス追従を再開

これにより、キャラクターは指定時間その場で待機し、待機完了後に自動的にパス追従を再開する。

### スタック検出と回避

キャラクター同士の衝突などで進めなくなった場合の対策：

1. **最終目的地への到達判定**: 最終ポイントへの距離が`final_destination_radius`（0.1m）以内になれば即座に完了
2. **中間地点でのスタック回避**: `stuck_timeout`（1.0秒）以上進めない場合、その中間ポイントをスキップして次へ
3. **すれ違い衝突の許容**: 一時的な衝突は次のポイントへスキップで対応し、パス追従を継続

### 閉じたドア待機

パスがドアを通過する場合、キャラクターはドアが開いていなければドアの前で待機する：

1. **ドア検出**: 移動方向に対してレイキャスト（壁レイヤー=2）を行い、閉じたドアを検出
2. **ドア判定**: `doors`グループに属し、かつ`open_doors`グループに属していないドアは「閉じている」と判定
3. **待機**: 閉じたドアが見つかった場合、`_is_waiting_for_closed_door`フラグを立てて移動を停止
4. **再開**: ドアが`open_doors`グループに追加されると（ドアキック等で開いたら）、移動を再開

これにより、DoorMarkerがなくても閉じたドアを貫通することはなく、ドアが開くまで待機する。

### 衝突回避（Door Kickers 2スタイル）

複数キャラクターがパス上で衝突した場合のデッドロックを防ぐため、協調的移動を実装。

#### 検出フロー

```
100ms間隔で前方をスキャン
    ↓
前方60度・1.5m以内に味方を検出？
    ↓ Yes
距離 < 0.96m（近距離）？ ─Yes→ 即座に側方回避
    ↓ No
Head-on（対面移動）検出？ ─Yes→ 即座に側方回避
    ↓ No
優先度比較 → 低優先度なら待機
```

#### Head-on（対面移動）の検出

以下のいずれかでHead-onと判定:
1. 相手も衝突回避で待機中
2. 相手のパス目標が自分の方向（dot < -0.3）

```
    A ───→ ←─── B    Head-on: 両者が向かい合って移動
```

#### 側方回避（Sidestep）

**発動条件:**
- 近距離での衝突（距離 < `collision_check_radius` × 1.2）
- Head-on検出時
- 待機中に0.15秒経過してもHead-on状態

**方向決定アルゴリズム:**
```
1. 両者を結ぶ線の垂直方向を計算
2. 常に「小さいID → 大きいID」の向きで基準を統一
3. 小さいIDのキャラクター → +垂直方向
4. 大きいIDのキャラクター → -垂直方向
```

これにより両者は必ず**反対方向**に側方移動する。

```
         +perpendicular
              ↑
    A(小ID) ──┼── B(大ID)
              ↓
         -perpendicular

A → +方向へ移動
B → -方向へ移動
```

**壁チェック:**
- 移動前にレイキャスト（壁レイヤー=2）で壁を検出
- 第一候補が壁なら反対方向を試行
- 両方向に壁がある場合は移動せず待機継続

**パラメータ:**
| 定数 | 値 | 説明 |
|------|-----|------|
| `SIDESTEP_DURATION` | 0.5秒 | 側方移動の継続時間 |
| `SIDESTEP_DISTANCE` | 0.8m | 壁チェックの距離 |
| `HEAD_ON_THRESHOLD` | -0.3 | Head-on判定の閾値 |

#### 優先度ルール（待機判定用）

| 優先度 | 条件 |
|--------|------|
| 最高 | 先に移動開始したキャラクター（低い`priority`値） |
| 高 | パス進行率が高いキャラクター |
| 低 | 上記が同等な場合、キャラクターIDが小さい方 |

#### 待機終了条件

- 相手が離れた（距離 > 2.25m）
- 相手がパス追従を完了
- 相手が死亡
- タイムアウト（3秒）

#### シナリオ別の動作

| シナリオ | 動作 |
|---------|------|
| 対面移動 `A→ ←B` | 両者が即座に側方回避（反対方向） |
| 追いつき `A→ B→` | 後方(A)が待機、前方(B)が進行 |
| 交差パス | 低優先度が待機または側方回避 |
| 狭い廊下 | 壁チェック後、可能な方向へ側方回避 |

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `path_started` | なし |
| `path_completed` | なし |
| `path_cancelled` | なし |
| `vision_point_reached` | `index: int, direction: Vector3` |

### メソッド
- `setup(character: CharacterBody3D) -> void`
- `set_combat_awareness(component: Node) -> void`
- `start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [], ...) -> bool`
- `cancel() -> void`
- `is_following_path() -> bool`
- `process(delta: float) -> void`
- `set_movement_priority(priority: int) -> void`
- `get_movement_priority() -> int`
- `get_current_progress() -> float`
