class_name ContextMenuItem
extends Resource

## コンテキストメニュー項目リソース
## メニューの各項目の設定を外部ファイルで管理

@export_group("基本情報")
@export var action_id: String = ""  ## アクションの一意識別子（例: "rotate", "move"）
@export var display_name: String = ""  ## 表示名（例: "回転"）
@export var icon: Texture2D  ## アイコン画像（オプション）

@export_group("状態")
@export var enabled: bool = true  ## 有効/無効
@export var order: int = 0  ## 表示順序（小さい順）


## 辞書形式に変換
func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"display_name": display_name,
		"enabled": enabled,
		"order": order
	}


## 辞書からResourceを作成
static func from_dict(data: Dictionary) -> ContextMenuItem:
	var res = ContextMenuItem.new()
	res.action_id = data.get("action_id", "")
	res.display_name = data.get("display_name", "")
	res.enabled = data.get("enabled", true)
	res.order = data.get("order", 0)
	return res


## 便利なファクトリーメソッド
static func create(p_action_id: String, p_display_name: String, p_order: int = 0) -> ContextMenuItem:
	var item = ContextMenuItem.new()
	item.action_id = p_action_id
	item.display_name = p_display_name
	item.order = p_order
	return item
