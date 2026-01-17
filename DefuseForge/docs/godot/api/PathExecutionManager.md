# PathExecutionManager

パス実行管理。パス確定・実行・pending_paths管理を担当。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `PathExecutionManager` |
| ファイルパス | `scripts/systems/path_execution_manager.gd` |

## 機能

- パス確定（複数キャラクターへの同一パス適用）
- 接続線の自動生成（キャラクター位置 → パス開始点）
- 視線ポイント・Run区間の比率自動調整
- パスメッシュ・マーカーの管理
- 全キャラクター同時パス実行
- PathFollowingControllerの動的生成・管理

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `path_confirmed` | `character_count: int` | パス確定時 |
| `paths_execution_started` | `count: int` | 全パス実行開始時 |
| `all_paths_completed` | なし | 全パス完了時 |
| `paths_cleared` | なし | パスクリア時 |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `pending_paths` | `Dictionary` | 保留中のパス（キャラクターID → パスデータ） |

## メソッド

### セットアップ

```gdscript
# セットアップ（パスメッシュの親ノードを指定）
func setup(mesh_parent: Node3D) -> void
```

### パス確定

```gdscript
# パスを確定して保存
# target_characters: パス適用対象
# path_drawer: PathDrawerノード
# primary_character: プライマリキャラクター
func confirm_path(
    target_characters: Array[Node],
    path_drawer: Node,
    primary_character: Node
) -> bool
```

### パス実行

```gdscript
# 全キャラクターのパスを同時実行
# run: true=走り、false=歩き
# 戻り値: 実行したキャラクター数
func execute_all_paths(run: bool) -> int
```

### パスクリア

```gdscript
# 全ての保留パスをクリア
func clear_all_pending_paths() -> void

# 保留パス数を取得
func get_pending_path_count() -> int
```

### パス追従状態の確認

```gdscript
# パス追従中のコントローラーがあるか
func is_any_path_following_active() -> bool

# 指定キャラクターがパス追従中か
func is_character_following_path(character: Node) -> bool

# 全てのパス追従をキャンセル
func cancel_all_path_following() -> void
```

### フレーム処理

```gdscript
# 全パス追従コントローラーを処理（毎フレーム呼ぶ）
func process_controllers(delta: float) -> void

# パス追従完了時のコールバック
func on_path_following_completed(character: Node) -> void
```

## 使用例

```gdscript
var path_execution_manager = PathExecutionManager.new()
add_child(path_execution_manager)
path_execution_manager.setup(self)

# シグナル接続
path_execution_manager.path_confirmed.connect(_on_path_confirmed)
path_execution_manager.all_paths_completed.connect(_on_all_paths_completed)

# パス確定
var targets = selection_manager.get_path_targets()
if path_execution_manager.confirm_path(targets, path_drawer, primary):
    print("Path confirmed for %d characters" % targets.size())

# パス実行
var count = path_execution_manager.execute_all_paths(false)  # 歩き

# 毎フレーム処理
func _physics_process(delta: float) -> void:
    path_execution_manager.process_controllers(delta)
```

## パスデータ構造

`pending_paths` の各エントリ:

```gdscript
{
    "character": Node,           # キャラクターノード
    "path": Array[Vector3],      # パスポイント（接続線含む）
    "vision_points": Array[Dictionary],  # 視線ポイント
    "run_segments": Array[Dictionary],   # Run区間
    "path_mesh": MeshInstance3D, # パスメッシュ
    "vision_markers": Array[MeshInstance3D],  # 視線マーカー
    "run_markers": Array[MeshInstance3D]      # Runマーカー
}
```

## 接続線と比率調整

複数キャラクターに同一パスを適用する場合:

1. 各キャラクターの現在位置からパス開始点への接続線を追加
2. 視線ポイント・Run区間の比率を接続線の長さ分だけ調整
3. パス全体の長さが変わるため、比率を再計算

```
キャラクター位置 → [接続線] → パス開始点 → [描画パス] → パス終点

比率調整:
new_ratio = (connect_length + old_ratio * base_length) / new_length
```

## 関連クラス

- [CharacterSelectionManager](CharacterSelectionManager.md) - 選択管理
- [PathDrawer](PathDrawer.md) - パス描画
- [PathFollowingController](PathFollowingController.md) - パス追従
- [PathLineMesh](PathLineMesh.md) - パスメッシュ描画
