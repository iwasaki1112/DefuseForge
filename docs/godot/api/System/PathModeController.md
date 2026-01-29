# PathModeController

パス描画モードの状態管理を行うコントローラー。

## 概要

パスモード（移動先パス描画）の開始・確定・キャンセルを制御する。
PathDrawer、CharacterSelectionManager、PathExecutionManagerと連携して動作。

## パス

`res://scripts/systems/path_mode_controller.gd`

## クラス定義

```gdscript
extends Node
class_name PathModeController
```

## シグナル

| 名前 | 引数 | 説明 |
|------|------|------|
| mode_started | character: Node | パスモード開始時 |
| mode_ended | なし | パスモード正常終了時 |
| mode_cancelled | なし | パスモードキャンセル時 |
| path_ready | なし | パス描画完了時（確定可能状態） |

## プロパティ

| 名前 | 型 | 説明 |
|------|-----|------|
| is_active | bool | パス描画モード中かどうか |
| editing_character | Node | 現在パスを編集中のキャラクター |
| path_drawer | Node3D | PathDrawerへの参照 |
| selection_manager | CharacterSelectionManager | 選択マネージャーへの参照 |
| path_execution_manager | PathExecutionManager | パス実行マネージャーへの参照 |

## メソッド

### setup()

コントローラーをセットアップする。

```gdscript
func setup(
    drawer: Node3D,
    sel_manager: CharacterSelectionManager,
    exec_manager: PathExecutionManager
) -> void
```

### start()

パスモードを開始する。

```gdscript
func start(character: Node, char_color: Color = Color.WHITE) -> bool
```

**引数:**
- `character`: パス描画の基準キャラクター
- `char_color`: パス描画色

**戻り値:** 成功した場合 `true`

**処理:**
1. 選択マネージャーでパス適用対象をスナップショット
2. PathDrawerを有効化
3. `mode_started`シグナルを発火

### confirm()

現在のパスを確定して終了。

```gdscript
func confirm() -> bool
```

**戻り値:** 成功した場合 `true`

**処理:**
1. PathExecutionManagerにパスを委譲
2. クリーンアップ処理
3. 選択を解除
4. `mode_ended`シグナルを発火

### cancel()

パスモードをキャンセル。

```gdscript
func cancel() -> void
```

クリーンアップ処理を行い`mode_cancelled`シグナルを発火。

### is_path_mode()

パスモード中かどうかを返す。

```gdscript
func is_path_mode() -> bool
```

### has_pending_path()

パス描画後かどうか（確定可能状態）を返す。

```gdscript
func has_pending_path() -> bool
```

### get_editing_character()

編集中キャラクターを取得。

```gdscript
func get_editing_character() -> Node
```

### get_target_count()

パス適用対象キャラクター数を取得。

```gdscript
func get_target_count() -> int
```

### handle_click_to_confirm()

クリック・トゥ・コンファーム処理。

```gdscript
func handle_click_to_confirm(clicked_character: Node) -> bool
```

パス描画後にキャラクター以外（パス外）をクリックした場合にパスを確定する。

**戻り値:** 確定した場合 `true`

### start_with_existing_path()

既存パスを読み込んで編集モードを開始する。

```gdscript
func start_with_existing_path(path_data: Dictionary, char_color: Color = Color.WHITE) -> bool
```

**引数:**
- `path_data`: PathExecutionManagerから取得したパスデータ
- `char_color`: パス描画色

**戻り値:** 成功した場合 `true`

**処理:**
1. 選択マネージャーでパス適用対象をスナップショット
2. 既存パスデータをPathDrawerに復元
3. 復元に失敗した場合は通常のenableにフォールバック
4. `mode_started`シグナルを発火

## 使用例

```gdscript
# セットアップ
path_mode_controller = PathModeController.new()
path_mode_controller.name = "PathModeController"
add_child(path_mode_controller)
path_mode_controller.setup(path_drawer, selection_manager, path_execution_manager)

# シグナル接続
path_mode_controller.mode_started.connect(_on_path_mode_started)
path_mode_controller.mode_ended.connect(_on_path_mode_ended)
path_mode_controller.mode_cancelled.connect(_on_path_mode_cancelled)
path_mode_controller.path_ready.connect(_on_path_ready)

# パスモード開始
func _start_move_mode(character: Node) -> void:
    var char_color = CharacterColorManager.get_character_color(character)
    path_mode_controller.start(character, char_color)

# コールバック
func _on_path_mode_started(character: Node) -> void:
    var count = path_mode_controller.get_target_count()
    _update_mode_info("Path Mode: Draw path for %d characters" % count)

func _on_path_mode_ended() -> void:
    path_panel.visible = false
    _update_mode_info("")

# 入力処理
func _unhandled_input(event: InputEvent) -> void:
    if path_mode_controller.is_path_mode() and event is InputEventMouseButton:
        if path_drawer.has_pending_path():
            var clicked = _raycast_character(event.position)
            path_mode_controller.handle_click_to_confirm(clicked)

# 既存パスの編集
func _edit_existing_path(path_data: Dictionary) -> void:
    var char_color = CharacterColorManager.get_character_color(selected_character)
    path_mode_controller.start_with_existing_path(path_data, char_color)
```

## 状態遷移

```
[Inactive] --start()--> [Drawing] --path_ready--> [Ready]
    ^          |            |                        |
    |          |            v                        v
    |          |     +--cancel()                     |
    |          |     |                               |
    +<---------+-----+                               |
    +<---cancel()--------------------------------+
    +<---confirm() / handle_click_to_confirm()---+

[Inactive] --start_with_existing_path()--> [Ready] (既存パス復元)
    ^                                         |
    +<---cancel() / confirm()----------------+
```

## 関連クラス

- [PathDrawer](PathDrawer.md) - パス描画UI
- [CharacterSelectionManager](CharacterSelectionManager.md) - 選択状態管理
- [PathExecutionManager](PathExecutionManager.md) - パス実行管理

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `mode_started` | `character: Node` |
| `mode_ended` | なし |
| `mode_cancelled` | なし |
| `path_ready` | なし |

### メソッド
- `setup(drawer: Node3D, sel_manager: CharacterSelectionManager, exec_manager: PathExecutionManager) -> void`
- `start(_character: Node, char_color: Color = Color.WHITE) -> bool`
- `start_with_existing_path(path_data: Dictionary, char_color: Color = Color.WHITE) -> bool`
- `confirm() -> bool`
- `cancel() -> void`
- `is_path_mode() -> bool`
- `has_pending_path() -> bool`
- `get_editing_character() -> Node`
- `get_target_count() -> int`
- `handle_click_to_confirm(clicked_character: Node) -> bool`
