# MarkerEditPanel

マルチキャラクター対応のマーカー編集パネルUIコンポーネント。

## 概要

`MarkerEditPanel`は、パス描画後にVisionMarker/RunMarkerを設定するためのUIパネルです。マルチセレクト時に各キャラクターに対して個別のマーカーを設定できます。

## 継承

`VBoxContainer` -> `MarkerEditPanel`

## UI構造

```
┌─────────────────────────────────────┐
│ Select character for markers:       │
│ ┌─────┐ ┌─────┐                    │
│ │  A  │ │  B  │  ← キャラクター選択  │
│ └─────┘ └─────┘                    │
├─────────────────────────────────────┤
│ Vision Points (A): 2               │
│ [Add Vision] [Undo]                │
├─────────────────────────────────────┤
│ Run Segments (A): 1                │
│ [Add Run] [Undo]                   │
├─────────────────────────────────────┤
│ [Confirm Path]                     │
│ [Cancel]                           │
└─────────────────────────────────────┘
```

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `character_selected` | `character: Node` | キャラクター選択時 |
| `vision_add_requested` | `character: Node` | Vision追加ボタン押下時 |
| `vision_undo_requested` | `character: Node` | Vision Undoボタン押下時 |
| `run_add_requested` | `character: Node` | Run追加ボタン押下時 |
| `run_undo_requested` | `character: Node` | Run Undoボタン押下時 |
| `confirm_requested` | なし | 確定ボタン押下時 |
| `cancel_requested` | なし | キャンセルボタン押下時 |

## メソッド

### setup

```gdscript
func setup(characters: Array[Node], path_drawer: Node) -> void
```

パネルをセットアップします。

**引数:**
- `characters`: 対象キャラクター配列
- `path_drawer`: PathDrawerへの参照

**動作:**
- キャラクターボタンを動的生成
- 最初のキャラクターをアクティブに設定
- PathDrawerのマルチキャラクターモードと連携

### set_active_character

```gdscript
func set_active_character(character: Node) -> void
```

編集対象のキャラクターを設定します。

**引数:**
- `character`: 編集対象キャラクター

**動作:**
- PathDrawerのアクティブキャラクターを更新
- ボタンのハイライト状態を更新
- ラベルを更新
- `character_selected`シグナルを発火

### get_active_character

```gdscript
func get_active_character() -> Node
```

現在のアクティブキャラクターを取得します。

### on_vision_point_added / on_run_segment_added

```gdscript
func on_vision_point_added() -> void
func on_run_segment_added() -> void
```

マーカーが追加された時にラベルを更新します。外部から呼び出します。

### clear

```gdscript
func clear() -> void
```

パネルをクリアします。

## 使用例

```gdscript
# セットアップ
var selected_characters: Array[Node] = [character_a, character_b]
marker_edit_panel.setup(selected_characters, path_drawer)

# シグナル接続
marker_edit_panel.character_selected.connect(_on_character_selected)
marker_edit_panel.vision_add_requested.connect(_on_vision_add)
marker_edit_panel.confirm_requested.connect(_on_confirm)

# コールバック
func _on_character_selected(character: Node) -> void:
    # キャラクター切り替え時の処理
    var color = CharacterColorManager.get_character_color(character)
    path_drawer.set_character_color(color)

func _on_vision_add(character: Node) -> void:
    path_drawer.start_vision_mode()

func _on_confirm() -> void:
    path_mode_controller.confirm()
```

## PathDrawerとの連携

`MarkerEditPanel`は`PathDrawer`のマルチキャラクターモードと連携します：

1. `setup()`呼び出し時に`PathDrawer.start_multi_character_mode()`が呼ばれていること
2. キャラクター切り替え時に`PathDrawer.set_active_edit_character()`を呼び出す
3. マーカー追加/削除は`PathDrawer`のAPIを通じて行う

## スタイル

- キャラクターボタンはキャラクター色で表示
- アクティブなキャラクターは明るい色＋白枠線
- 非アクティブなキャラクターは暗い色

## 関連クラス

- [PathDrawer](PathDrawer.md) - パス描画＋マーカー管理
- [PathExecutionManager](PathExecutionManager.md) - パス確定・実行管理
- [CharacterColorManager](CharacterColorManager.md) - キャラクター色管理
