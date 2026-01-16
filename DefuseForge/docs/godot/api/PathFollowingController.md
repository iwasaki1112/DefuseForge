# PathFollowingController

パス追従を管理するコントローラークラス。キャラクターが描画されたパスに沿って移動し、視線ポイントで向きを変える。

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
| `stuck_threshold` | `float` | `0.05` | スタック検出の移動距離閾値 |
| `stuck_timeout` | `float` | `0.3` | スタック判定時間（秒）- この時間進めないと次のポイントへスキップ |
| `final_destination_radius` | `float` | `0.5` | 最終目的地への到達判定半径 |

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

### start_path(path: Array[Vector3], vision_points: Array[Dictionary] = [], run: bool = false) -> bool
パス追従を開始する。

**引数:**
- `path` - 追従するパス（Vector3の配列、最低2点必要）
- `vision_points` - 視線ポイント配列（`path_ratio`と`direction`を含むDictionary）
- `run` - 走行モードで移動するか

**戻り値:** 開始成功なら`true`

### cancel() -> void
パス追従をキャンセルする。

### is_following_path() -> bool
パス追従中か確認する。

**戻り値:** 追従中なら`true`

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
var vision_points = [
    {"path_ratio": 0.5, "direction": Vector3(1, 0, 0)}
]
path_controller.start_path(path, vision_points, false)

# 毎フレーム処理
func _physics_process(delta):
    if path_controller.is_following_path():
        path_controller.process(delta)
```

## 内部動作

- パス上の各ポイントに順番に移動
- 目標点への距離が0.15未満になると次のポイントへ
- 視線ポイントはパスの進行率（0.0〜1.0）で管理
- 完了時は最後の移動方向または視線方向を維持
- `CharacterAnimationController`と連携してアニメーションを更新

### スタック検出と回避

キャラクター同士の衝突などで進めなくなった場合の対策：

1. **最終目的地への到達判定**: 最終ポイントへの距離が`final_destination_radius`（0.5m）以内になれば即座に完了
2. **中間地点でのスタック回避**: `stuck_timeout`（0.3秒）以上進めない場合、その中間ポイントをスキップして次へ
3. **すれ違い衝突の許容**: 一時的な衝突は次のポイントへスキップで対応し、パス追従を継続
