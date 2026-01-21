# ContextMenuComponent

コンテキストメニューUIコンポーネント。キャラクタータップ時にメニューを表示し、操作を選択させる。モバイル/PC両対応。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Control` |
| ファイルパス | `scripts/ui/context_menu_component.gd` |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `item_selected` | `action_id: String, character: CharacterBody3D` | メニュー項目選択時 |

## 定数

### DEFAULT_MENU_ITEMS
標準メニュー項目の定義（単一選択時用）。

```gdscript
const DEFAULT_MENU_ITEMS: Array[Dictionary] = [
    {"id": "move", "name": "Move", "order": 0},
    {"id": "rotate", "name": "Rotate", "order": 1},
    {"id": "crouch", "name": "Crouch", "order": 2},
]
```

**複数選択時:**
`setup_multi_select_items()`によりMOVEのみ表示される。

## Export Properties

### 外観設定
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `button_size` | `Vector2` | `(120, 50)` | ボタンサイズ |
| `button_margin` | `float` | `4.0` | ボタン間のマージン |
| `panel_padding` | `float` | `8.0` | パネル内側のパディング |
| `font_size` | `int` | `16` | フォントサイズ |

### アニメーション
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `animation_duration` | `float` | `0.15` | 表示/非表示アニメーション時間 |

## Public API

### Menu Control

#### open(screen_position: Vector2, character: CharacterBody3D, is_multi_select: bool = false) -> void
メニューを開く。

**引数:**
- `screen_position` - 画面上の表示位置
- `character` - 対象キャラクター
- `is_multi_select` - 複数キャラクター選択時はtrue（MOVEのみ表示）

#### close() -> void
メニューを閉じる。

#### is_open() -> bool
メニューが開いているか確認する。

#### get_current_character() -> CharacterBody3D
現在のキャラクターを取得する。

### Item Management

#### add_item(item: ContextMenuItem) -> void
メニュー項目を追加する（order順にソートされる）。

**引数:**
- `item` - ContextMenuItemリソース

#### remove_item(action_id: String) -> void
メニュー項目を削除する。

#### set_item_enabled(action_id: String, enabled: bool) -> void
メニュー項目の有効/無効を設定する。

#### clear_items() -> void
全メニュー項目をクリアする。

#### setup_default_items() -> void
標準メニュー項目をセットアップする（Move, Rotate, Crouch）。

#### setup_multi_select_items() -> void
複数選択時用のメニュー項目をセットアップする（MOVEのみ）。

## 使用例

```gdscript
# CanvasLayerの子として追加
var context_menu = Control.new()
context_menu.set_script(preload("res://scripts/ui/context_menu_component.gd"))
ui_layer.add_child(context_menu)

# 標準項目をセットアップ
context_menu.setup_default_items()

# シグナル接続
context_menu.item_selected.connect(_on_menu_item_selected)

# メニューを開く（単一選択時）
context_menu.open(screen_position, character)

# 複数選択時はis_multi_select=trueでMOVEのみ表示
var is_multi = selection_manager.get_selection_count() > 1
context_menu.open(screen_position, character, is_multi)

# カスタム項目追加
var item = ContextMenuItem.create("fire", "Fire", 3)
context_menu.add_item(item)

# シグナルハンドラ
func _on_menu_item_selected(action_id: String, character: CharacterBody3D):
    match action_id:
        "move":
            start_move_mode(character)
        "rotate":
            start_rotate_mode(character)
```

## 内部動作

### UI構成
- `PanelContainer` > `MarginContainer` > `VBoxContainer` > `Button[]`

### 表示アニメーション
- フェードイン + スケールアップ（0.9 → 1.0）
- Tweenで制御（`animation_duration`秒）

### 画面端クリッピング対策
- 右端/下端を超える場合は位置を調整
- 左端/上端は10pxのマージンを確保

### メニュー外クリック検出
- `_gui_input`でパネル外クリックを検出して自動で閉じる
