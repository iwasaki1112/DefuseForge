# PathFollowingController API

パス追従を管理するコントローラークラス。
キャラクターが描画されたパスに沿って移動し、視線ポイントで向きを変える。

## ファイル
- `scripts/characters/path_following_controller.gd`

---

## クイックスタート

```gdscript
const PathFollowCtrl = preload("res://scripts/characters/path_following_controller.gd")

var path_ctrl: Node

func _ready():
    path_ctrl = PathFollowCtrl.new()
    add_child(path_ctrl)
    path_ctrl.setup(self)

func _physics_process(delta):
    path_ctrl.process(delta)
```

---

## シグナル

### path_started()
パス追従開始時に発火。

### path_completed()
パス追従完了時に発火。

### path_cancelled()
パス追従がキャンセルされた時に発火。

### vision_point_reached(index: int, direction: Vector3)
視線ポイントに到達した時に発火。

| 引数 | 型 | 説明 |
|------|-----|------|
| index | int | 到達した視線ポイントのインデックス |
| direction | Vector3 | 視線方向ベクトル |

```gdscript
path_ctrl.path_completed.connect(_on_path_completed)
path_ctrl.vision_point_reached.connect(_on_vision_point)

func _on_path_completed():
    print("Path completed!")

func _on_vision_point(index: int, direction: Vector3):
    print("Vision point %d reached, looking at %s" % [index, direction])
```

---

## メソッド

### 初期化

#### setup(character: CharacterBody3D) -> void
コントローラーを初期化する。

| 引数 | 型 | 説明 |
|------|-----|------|
| character | CharacterBody3D | 追従するキャラクター |

```gdscript
path_ctrl.setup(self)
```

#### set_combat_awareness(component: Node) -> void
CombatAwarenessComponentを設定する。敵視認時の自動照準に使用。

| 引数 | 型 | 説明 |
|------|-----|------|
| component | Node | CombatAwarenessComponentインスタンス |

```gdscript
path_ctrl.set_combat_awareness($CombatAwarenessComponent)
```

---

### パス制御

#### start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [], run_segments: Array[Dictionary] = [], run: bool = false) -> bool
パス追従を開始する。

| 引数 | 型 | 説明 |
|------|-----|------|
| path | Array[Vector3] | 追従するパス（2点以上必要） |
| vision_points | Array[Dictionary] | 視線ポイント配列（path_ratio, directionを含む） |
| run_segments | Array[Dictionary] | Run区間配列（start_ratio, end_ratioを含む） |
| run | bool | 全体を走行モードにするか |

| 戻り値 | 説明 |
|--------|------|
| bool | 開始成功したらtrue |

```gdscript
var path: Array[Vector3] = [start_pos, mid_pos, end_pos]
var vision_points: Array[Dictionary] = [
    { "path_ratio": 0.5, "direction": Vector3.FORWARD }
]
var run_segments: Array[Dictionary] = [
    { "start_ratio": 0.0, "end_ratio": 0.3 }
]

if path_ctrl.start_path(path, vision_points, run_segments):
    print("Path started!")
```

#### cancel() -> void
パス追従をキャンセルする。

```gdscript
path_ctrl.cancel()
```

---

### 毎フレーム更新

#### process(delta: float) -> void
毎フレームの処理。`_physics_process`から呼び出す。

| 引数 | 型 | 説明 |
|------|-----|------|
| delta | float | デルタタイム |

**内部処理:**
1. 最終目的地への距離判定（到達判定）
2. 味方衝突検出（目的地付近に味方がいれば停止）
3. スタック検出（長時間停滞したら次のポイントへスキップ）
4. 視線ポイント処理
5. Run区間判定
6. アニメーション更新
7. 物理移動

```gdscript
func _physics_process(delta):
    path_ctrl.process(delta)
```

---

### 状態取得

#### is_following_path() -> bool
パス追従中かどうか。

```gdscript
if path_ctrl.is_following_path():
    print("Currently following path")
```

---

## Export設定

インスペクターから調整可能なパラメータ。

### スタック検出
| プロパティ | デフォルト | 説明 |
|-----------|-----------|------|
| stuck_threshold | 0.01 | この距離以下の移動をスタックとみなす |
| stuck_timeout | 0.5 | この時間スタックしたら次のポイントへスキップ |

### 到達判定
| プロパティ | デフォルト | 説明 |
|-----------|-----------|------|
| final_destination_radius | 0.5 | 最終目的地への到達判定半径（m） |

### 味方衝突回避
| プロパティ | デフォルト | 説明 |
|-----------|-----------|------|
| ally_collision_radius | 1.0 | 味方との衝突検出半径（m） |

---

## 味方衝突回避

マルチセレクト移動時に、複数キャラクターが同じ目的地に向かう際の衝突を回避する機能。

### 動作仕様
1. 最終目的地から `final_destination_radius + ally_collision_radius`（デフォルト1.5m）以内に接近
2. 目的地付近に味方キャラクターがいるかチェック
3. 味方がいれば現在位置で停止（`_finish()`を呼び出し）

### 味方判定ロジック
1. GameCharacterの場合: `team`プロパティで判定
2. それ以外: `PlayerState.is_friendly()`で判定

### 処理フロー
```
process()
    ↓
最終目的地への距離計算 (distance_to_final)
    ↓
distance_to_final < 0.5m → _finish() (通常の到達判定)
    ↓
distance_to_final < 1.5m (0.5 + 1.0)
    ↓ YES
_is_ally_at_destination() で味方チェック
    ↓ 味方がいる
_finish() → 現在位置で停止
```

---

## Run区間

パスの特定区間で走行モードに切り替える機能。

### Run区間中の動作
- 走行速度で移動
- 敵認識を無視（敵方向を向かない）
- 視線ポイントを無視（移動方向のみ見る）
- CombatAwarenessの処理をスキップ

```gdscript
var run_segments: Array[Dictionary] = [
    { "start_ratio": 0.0, "end_ratio": 0.3 },  # パスの0%〜30%を走る
    { "start_ratio": 0.7, "end_ratio": 1.0 }   # パスの70%〜100%を走る
]
path_ctrl.start_path(path, [], run_segments)
```

---

## 視線ポイント

パスの特定位置で視線方向を変更する機能。

### 視線ポイントの定義
```gdscript
var vision_points: Array[Dictionary] = [
    {
        "path_ratio": 0.3,  # パスの30%位置で発動
        "direction": Vector3(1, 0, 0)  # 右を向く
    },
    {
        "path_ratio": 0.7,
        "direction": Vector3(0, 0, -1)  # 後ろを向く
    }
]
```

### 視線優先順位
1. 敵視認（CombatAwareness経由） - 最優先
2. 視線ポイント
3. 移動方向

---

## 完全な使用例

```gdscript
extends CharacterBody3D

const PathFollowCtrl = preload("res://scripts/characters/path_following_controller.gd")

var path_ctrl: Node

func _ready():
    path_ctrl = PathFollowCtrl.new()
    add_child(path_ctrl)
    path_ctrl.setup(self)

    # シグナル接続
    path_ctrl.path_started.connect(_on_path_started)
    path_ctrl.path_completed.connect(_on_path_completed)
    path_ctrl.path_cancelled.connect(_on_path_cancelled)
    path_ctrl.vision_point_reached.connect(_on_vision_point)

    # CombatAwareness設定（オプション）
    if has_node("CombatAwarenessComponent"):
        path_ctrl.set_combat_awareness($CombatAwarenessComponent)

func _physics_process(delta):
    path_ctrl.process(delta)

func start_movement(path: Array[Vector3], vision_points: Array[Dictionary], run_segments: Array[Dictionary]):
    path_ctrl.start_path(path, vision_points, run_segments)

func _on_path_started():
    print("Started following path")

func _on_path_completed():
    print("Path completed!")

func _on_path_cancelled():
    print("Path cancelled")

func _on_vision_point(index: int, direction: Vector3):
    print("Vision point %d reached" % index)
```

---

## 依存関係

### 必須
- CharacterBody3D（setup()に渡す）
- CharacterAnimationController（`_character.get_anim_controller()`で取得）

### オプション
- CombatAwarenessComponent（敵視認・自動照準用）
- GameCharacter（味方判定用）
- PlayerState Autoload（味方判定フォールバック用）
- "characters"グループ（味方衝突回避用）
