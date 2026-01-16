# ContextMenuComponent API

`extends Control`

キャラクタータップ/クリック時にコンテキストメニューを表示するUIコンポーネント。モバイル（タッチ）とPC（マウス）両対応。

## ファイル

`scripts/ui/context_menu_component.gd`

---

## Signals

| Signal | Parameters | Description |
|--------|------------|-------------|
| `menu_opened` | `character: CharacterBody3D` | メニューが開いた時 |
| `menu_closed` | - | メニューが閉じた時 |
| `item_selected` | `action_id: String, character: CharacterBody3D` | メニュー項目が選択された時 |

---

## Constants

### DEFAULT_MENU_ITEMS

```gdscript
const DEFAULT_MENU_ITEMS: Array[Dictionary] = [
    {"id": "move", "name": "Move", "order": 0},
    {"id": "rotate", "name": "Rotate", "order": 1},
    {"id": "control", "name": "Control", "order": 2},
]
```

標準メニュー項目の定義。`setup_default_items()`で使用される。

---

## Properties

### Export Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `button_size` | `Vector2` | `Vector2(120, 50)` | ボタンサイズ（モバイル向け大きめ） |
| `button_margin` | `float` | `4.0` | ボタン間のマージン |
| `panel_padding` | `float` | `8.0` | パネル内側のパディング |
| `font_size` | `int` | `16` | フォントサイズ |
| `animation_duration` | `float` | `0.15` | 表示/非表示アニメーション時間 |

---

## Methods

### メニュー操作

#### open

```gdscript
func open(screen_position: Vector2, character: CharacterBody3D) -> void
```

指定位置にメニューを開く。

| Parameter | Type | Description |
|-----------|------|-------------|
| `screen_position` | `Vector2` | 表示位置（スクリーン座標） |
| `character` | `CharacterBody3D` | 対象キャラクター |

**動作**:
1. 既に開いている場合は即座にリセット
2. ボタンを再構築
3. 画面端クリッピング対策（メニューが画面外にはみ出さない）
4. フェードイン・スケールアニメーション
5. `menu_opened`シグナル発火

---

#### close

```gdscript
func close() -> void
```

メニューを閉じる。

**動作**:
1. フェードアウト・スケールアニメーション
2. `menu_closed`シグナル発火

---

#### is_open

```gdscript
func is_open() -> bool
```

メニューが開いているかを取得。

**Returns**: メニューが開いている場合`true`

---

#### get_current_character

```gdscript
func get_current_character() -> CharacterBody3D
```

現在対象のキャラクターを取得。

**Returns**: メニューが開いているキャラクター、閉じている場合は`null`

---

### メニュー項目管理

#### add_item

```gdscript
func add_item(item: Resource) -> void
```

メニュー項目を追加。`order`プロパティで自動ソートされる。

| Parameter | Type | Description |
|-----------|------|-------------|
| `item` | `Resource` | ContextMenuItemリソース |

---

#### remove_item

```gdscript
func remove_item(action_id: String) -> void
```

メニュー項目を削除。

| Parameter | Type | Description |
|-----------|------|-------------|
| `action_id` | `String` | 削除する項目のaction_id |

---

#### set_item_enabled

```gdscript
func set_item_enabled(action_id: String, enabled: bool) -> void
```

メニュー項目の有効/無効を設定。

| Parameter | Type | Description |
|-----------|------|-------------|
| `action_id` | `String` | 対象項目のaction_id |
| `enabled` | `bool` | 有効/無効 |

---

#### clear_items

```gdscript
func clear_items() -> void
```

全メニュー項目をクリア。

---

#### setup_default_items

```gdscript
func setup_default_items() -> void
```

標準メニュー項目（Move, Rotate, Control）をセットアップ。既存項目はクリアされる。

---

## 使用例

### 基本的なセットアップ

```gdscript
extends Node3D

var context_menu: Control

func _ready() -> void:
    # コンテキストメニューを作成
    context_menu = Control.new()
    context_menu.set_script(preload("res://scripts/ui/context_menu_component.gd"))
    context_menu.name = "ContextMenu"
    $UI.add_child(context_menu)  # CanvasLayer配下に追加

    # 標準項目をセットアップ
    context_menu.setup_default_items()

    # シグナル接続
    context_menu.item_selected.connect(_on_context_menu_item_selected)

func _on_context_menu_item_selected(action_id: String, character: CharacterBody3D) -> void:
    match action_id:
        "move":
            print("Move mode for: ", character.name)
        "rotate":
            print("Rotate mode for: ", character.name)
        "control":
            print("Control mode for: ", character.name)
```

### カスタム項目の追加

```gdscript
const ContextMenuItemScript = preload("res://scripts/resources/context_menu_item.gd")

func _ready() -> void:
    context_menu.clear_items()

    # カスタム項目を追加
    var attack_item = ContextMenuItemScript.create("attack", "Attack", 0)
    var defend_item = ContextMenuItemScript.create("defend", "Defend", 1)
    var info_item = ContextMenuItemScript.create("info", "Info", 2)

    context_menu.add_item(attack_item)
    context_menu.add_item(defend_item)
    context_menu.add_item(info_item)
```

### マウスクリックでメニュー表示

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            var character = _raycast_character(event.position)
            if character:
                context_menu.open(event.position, character)
```

### 条件付き項目無効化

```gdscript
func _on_character_selected(character: GameCharacter) -> void:
    # 死亡キャラクターは操作不可
    context_menu.set_item_enabled("control", character.is_alive)
    context_menu.set_item_enabled("move", character.is_alive)
```

---

## 関連

- [ContextMenuItem](context-menu-item.md)
- [GameCharacter](game-character.md)
