# ContextMenuItem API

`extends Resource`

コンテキストメニューの各項目を定義するリソースクラス。メニュー項目の設定を外部ファイルで管理可能。

## ファイル

`scripts/resources/context_menu_item.gd`

---

## Properties

### Export Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `action_id` | `String` | `""` | アクションの一意識別子（例: "rotate", "move"） |
| `display_name` | `String` | `""` | 表示名（例: "回転"） |
| `icon` | `Texture2D` | `null` | アイコン画像（オプション） |
| `enabled` | `bool` | `true` | 有効/無効 |
| `order` | `int` | `0` | 表示順序（小さい順） |

---

## Methods

### to_dict

```gdscript
func to_dict() -> Dictionary
```

リソースを辞書形式に変換。

**Returns**: 以下のキーを持つ辞書

```gdscript
{
    "action_id": String,
    "display_name": String,
    "enabled": bool,
    "order": int
}
```

---

### from_dict (static)

```gdscript
static func from_dict(data: Dictionary) -> Resource
```

辞書からContextMenuItemリソースを作成。

| Parameter | Type | Description |
|-----------|------|-------------|
| `data` | `Dictionary` | 項目データ |

**Returns**: 新しいContextMenuItemリソース

---

### create (static)

```gdscript
static func create(p_action_id: String, p_display_name: String, p_order: int = 0) -> Resource
```

便利なファクトリーメソッド。

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_action_id` | `String` | - | アクションID |
| `p_display_name` | `String` | - | 表示名 |
| `p_order` | `int` | `0` | 表示順序 |

**Returns**: 新しいContextMenuItemリソース

---

## 使用例

### ファクトリーメソッドで作成

```gdscript
const ContextMenuItemScript = preload("res://scripts/resources/context_menu_item.gd")

# 基本的な作成
var move_item = ContextMenuItemScript.create("move", "Move", 0)
var rotate_item = ContextMenuItemScript.create("rotate", "Rotate", 1)
var control_item = ContextMenuItemScript.create("control", "Control", 2)

# メニューに追加
context_menu.add_item(move_item)
context_menu.add_item(rotate_item)
context_menu.add_item(control_item)
```

### 辞書から作成

```gdscript
var data = {
    "action_id": "attack",
    "display_name": "Attack",
    "enabled": true,
    "order": 0
}

var item = ContextMenuItemScript.from_dict(data)
context_menu.add_item(item)
```

### アイコン付き項目

```gdscript
var item = ContextMenuItemScript.create("heal", "Heal", 3)
item.icon = preload("res://icons/heal.png")
context_menu.add_item(item)
```

### 動的な有効/無効切り替え

```gdscript
# 項目の状態を直接変更
for item in menu_items:
    if item.action_id == "attack":
        item.enabled = has_ammo

# または ContextMenuComponent のメソッドを使用
context_menu.set_item_enabled("attack", has_ammo)
```

### シリアライズ/デシリアライズ

```gdscript
# 保存
var items_data: Array[Dictionary] = []
for item in menu_items:
    items_data.append(item.to_dict())

# JSON保存などに使用
var json_string = JSON.stringify(items_data)

# 復元
var loaded_data = JSON.parse_string(json_string)
for data in loaded_data:
    var item = ContextMenuItemScript.from_dict(data)
    context_menu.add_item(item)
```

---

## 関連

- [ContextMenuComponent](context-menu-component.md)
