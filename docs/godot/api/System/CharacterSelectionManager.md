# CharacterSelectionManager

キャラクター選択管理。選択状態・アウトライン表示・パス適用対象の管理を担当。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `CharacterSelectionManager` |
| ファイルパス | `scripts/systems/character_selection_manager.gd` |

## 機能

- 複数キャラクターの同時選択（トグル選択）
- プライマリキャラクター（最後に選択したキャラクター）の追跡
- パス適用対象のスナップショット保存
- ステンシルベースのアウトライン表示

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `selection_changed` | `selected: Array[Node], primary: Node` | 選択状態変更時 |
| `primary_changed` | `character: Node` | プライマリキャラクター変更時 |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `selected_characters` | `Array[Node]` | 選択中の全キャラクター |
| `primary_character` | `Node` | 最後に選択したキャラクター |
| `path_target_characters` | `Array[Node]` | パス適用対象（MOVEモード開始時に確定） |
| `outline_color` | `Color` | アウトライン色（デフォルト: 水色） |
| `outline_thickness` | `float` | アウトライン太さ（デフォルト: 3.5） |

## メソッド

### 選択操作

```gdscript
# キャラクターを選択に追加
func add_to_selection(character: Node) -> void

# キャラクターを選択から削除
func remove_from_selection(character: Node) -> void

# 選択をトグル（選択中なら解除、未選択なら追加）
func toggle_selection(character: Node) -> void

# 全選択解除
func deselect_all() -> void
```

### 選択状態の確認

```gdscript
# 選択中のキャラクターがいるか
func has_selection() -> bool

# 選択数を取得
func get_selection_count() -> int
```

### パス適用対象管理

```gdscript
# パス適用対象を確定（MOVEモード開始時に呼ぶ）
func capture_path_targets() -> void

# パス適用対象をクリア
func clear_path_targets() -> void

# パス適用対象を取得
func get_path_targets() -> Array[Node]

# パス適用対象がいるか
func has_path_targets() -> bool
```

### アウトライン

```gdscript
# 全てのアウトラインを削除
func clear_all_outlines() -> void
```

## 使用例

```gdscript
var selection_manager = CharacterSelectionManager.new()
add_child(selection_manager)

# シグナル接続
selection_manager.selection_changed.connect(_on_selection_changed)
selection_manager.primary_changed.connect(_on_primary_changed)

# キャラクター選択
selection_manager.toggle_selection(character)

# MOVEモード開始時にパス適用対象を確定
selection_manager.capture_path_targets()
var targets = selection_manager.get_path_targets()

# パス確定後にクリア
selection_manager.clear_path_targets()
selection_manager.deselect_all()
```

## アウトライン仕様

- Godot 4.5のステンシルアウトライン機能を使用
- `BaseMaterial3D.STENCIL_MODE_OUTLINE` を設定
- キャラクター内の全MeshInstance3Dに自動適用
- 選択解除時にオーバーライドマテリアルをクリアして元に戻す

## Multiplayer API

### set_selection_for_player(player_id: int, selected: Array[Node], primary: Node) -> void
プレイヤーの選択状態を設定する（リモートプレイヤー用）。

### get_selection_for_player(player_id: int) -> Dictionary
プレイヤーの選択状態を取得する。

```gdscript
var selection = selection_manager.get_selection_for_player(peer_id)
# { "selected": Array[Node], "primary": Node }
```

### clear_selection_for_player(player_id: int) -> void
プレイヤーの選択状態をクリアする。

### clear_all_player_selections() -> void
全プレイヤーの選択状態をクリアする。

### to_selection_dict() -> Dictionary
現在の選択状態をDictionaryに変換する（ネットワーク同期用）。

```gdscript
var data = selection_manager.to_selection_dict()
# { "selected_ids": Array[int], "primary_id": int }
```

### from_selection_dict(data: Dictionary, character_resolver: Callable) -> void
Dictionaryから選択状態を復元する（ネットワーク同期用）。

```gdscript
selection_manager.from_selection_dict(data, func(id): return game_manager.find_character_by_network_id(id))
```

### add_to_selection_if_local(character: Node) -> bool
キャラクターがローカルプレイヤーのものか確認してから選択に追加する。

### toggle_selection_if_local(character: Node) -> bool
キャラクターがローカルプレイヤーのものか確認してからトグル選択する。

## 関連クラス

- [GameCharacter](../Character/GameCharacter.md) - キャラクター管理
- [NetworkMessages](NetworkMessages.md) - ネットワークメッセージ型

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `selection_changed` | `selected: Array[Node], primary: Node` |
| `primary_changed` | `character: Node` |

### メソッド
- `add_to_selection(character: Node) -> void`
- `remove_from_selection(character: Node) -> void`
- `toggle_selection(character: Node) -> void`
- `deselect_all() -> void`
- `has_selection() -> bool`
- `get_selection_count() -> int`
- `capture_path_targets() -> void`
- `clear_path_targets() -> void`
- `get_path_targets() -> Array[Node]`
- `has_path_targets() -> bool`
- `clear_all_outlines() -> void`
