# IdleCharacterManager

アイドル中キャラクターの状態更新を管理するクラス。

## 概要

パス追従していないキャラクターのアイドル状態を毎フレーム更新する。
CombatAwareness処理と向き更新を担当し、テストシーンからゲームロジックを分離する。

## パス

`res://scripts/systems/idle_character_manager.gd`

## クラス定義

```gdscript
extends Node
class_name IdleCharacterManager
```

## プロパティ

| 名前 | 型 | 説明 |
|------|-----|------|
| characters | Array[Node] | 管理対象キャラクターリスト |
| is_following_path_callback | Callable | パス追従中チェック用コールバック |
| get_primary_callback | Callable | プライマリキャラクター取得用コールバック |

## メソッド

### setup()

マネージャーをセットアップする。

```gdscript
func setup(
    char_list: Array[Node],
    following_check: Callable,
    primary_getter: Callable
) -> void
```

**引数:**
- `char_list`: 管理対象キャラクターリスト
- `following_check`: パス追従中かどうかをチェックするコールバック `func(character) -> bool`
- `primary_getter`: プライマリキャラクターを取得するコールバック `func() -> Node`

### add_character()

キャラクターを管理リストに追加。

```gdscript
func add_character(character: Node) -> void
```

### remove_character()

キャラクターを管理リストから削除。

```gdscript
func remove_character(character: Node) -> void
```

### set_characters()

キャラクターリストを一括更新。

```gdscript
func set_characters(char_list: Array[Node]) -> void
```

### process_idle_characters()

アイドル中の全キャラクターを更新（毎フレーム呼び出し）。

```gdscript
func process_idle_characters(delta: float) -> void
```

以下の条件のキャラクターはスキップ:
- パス追従中
- プライマリキャラクター（別処理）
- 死亡中

### process_primary_idle()

プライマリキャラクターのアイドル処理（手動操作無効時）。

```gdscript
func process_primary_idle(character: Node, delta: float) -> void
```

CombatAwareness処理、視線方向更新、重力適用を行う。

## 使用例

```gdscript
# セットアップ
idle_manager = IdleCharacterManager.new()
idle_manager.name = "IdleCharacterManager"
add_child(idle_manager)
idle_manager.setup(
    characters,
    func(c): return path_execution_manager.is_character_following_path(c),
    func(): return selection_manager.primary_character
)

# キャラクター追加/削除
idle_manager.add_character(new_character)
idle_manager.remove_character(old_character)

# 毎フレーム処理
func _physics_process(delta: float) -> void:
    idle_manager.process_idle_characters(delta)

    # プライマリキャラクターの処理（手動操作無効時）
    if not is_debug_control_enabled:
        idle_manager.process_primary_idle(primary, delta)
```

## 内部処理

### _update_idle_character()

単一キャラクターのアイドル状態を更新:

1. CombatAwareness処理（敵追跡）
2. 視線方向の決定
   - 敵追跡中: CombatAwarenessの視線方向
   - それ以外: 現在の向きを維持
3. アニメーション更新（移動なし）

## 関連クラス

- [CharacterSelectionManager](CharacterSelectionManager.md) - 選択状態管理
- [PathExecutionManager](PathExecutionManager.md) - パス実行管理
- [CombatAwarenessComponent](CombatAwarenessComponent.md) - 敵検出・自動照準
