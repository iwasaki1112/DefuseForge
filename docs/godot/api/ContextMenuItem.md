# ContextMenuItem

コンテキストメニュー項目リソース。メニュー項目の設定を外部ファイルで管理。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Resource` |
| ファイルパス | `scripts/resources/context_menu_item.gd` |

## Export Properties

### 基本情報
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `action_id` | `String` | `""` | アクションの一意識別子 |
| `display_name` | `String` | `""` | 表示名 |
| `icon` | `Texture2D` | - | アイコン画像（オプション） |

### 状態
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `enabled` | `bool` | `true` | 有効/無効 |
| `order` | `int` | `0` | 表示順序（小さい順） |

## Public API

### to_dict() -> Dictionary
辞書形式に変換する。

**戻り値:**
```gdscript
{
    "action_id": String,
    "display_name": String,
    "enabled": bool,
    "order": int
}
```

### static from_dict(data: Dictionary) -> ContextMenuItem
辞書からResourceを作成する。

**引数:**
- `data` - 辞書データ

**戻り値:** ContextMenuItemインスタンス

### static create(p_action_id: String, p_display_name: String, p_order: int = 0) -> ContextMenuItem
ファクトリーメソッド。

**引数:**
- `p_action_id` - アクションID
- `p_display_name` - 表示名
- `p_order` - 表示順序

**戻り値:** ContextMenuItemインスタンス

## 使用例

```gdscript
# ファクトリーメソッドで作成
var item = ContextMenuItem.create("move", "Move", 0)

# 直接作成
var item2 = ContextMenuItem.new()
item2.action_id = "rotate"
item2.display_name = "Rotate"
item2.order = 1

# 辞書から作成
var item3 = ContextMenuItem.from_dict({
    "action_id": "control",
    "display_name": "Control",
    "order": 2
})

# ContextMenuComponentに追加
context_menu.add_item(item)
```

## ContextMenuComponentとの連携

`ContextMenuComponent`の`add_item()`で追加し、`item_selected`シグナルで`action_id`を受け取る。
