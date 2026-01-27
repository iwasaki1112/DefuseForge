# ConvenienceStore

**継承:** `Node3D`

コンビニエンスストアマップの初期化スクリプト。
視覚システムとパスブロッキングのための壁/ドアの衝突レイヤーを設定します。

## 説明

このスクリプトはマップシーンのルートにアタッチされ、`_ready()` 時に子ノードを走査して衝突設定を自動的に行います。

## 定数

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `WALL_COLLISION_LAYER` | `2` | 壁およびドアの衝突レイヤーID |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `_setup_collisions(node: Node)` | `void` | 指定されたノードとその子孫に対して衝突設定を再帰的に適用します。 |

## 詳細

### _setup_collisions

```gdscript
func _setup_collisions(node: Node) -> void
```

ノード名に基づいて衝突レイヤーとグループを設定します。

*   **Wall:** 名前が `wall_` で始まるノードは `WALL_COLLISION_LAYER` に設定されます。
*   **Door:** 名前が `door_` で始まるノードは `WALL_COLLISION_LAYER` に設定され、`GameConstants.GROUP_DOORS` グループに追加されます。
