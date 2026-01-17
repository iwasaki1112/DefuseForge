# CharacterLabelManager

味方キャラクターの頭上にA, B, C...のラベルを表示するコンポーネント。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `CharacterLabelManager` |
| ファイルパス | `scripts/ui/character_label_manager.gd` |

## 機能

- 味方キャラクターのみにラベルを表示（敵は除外）
- 生成順にA→B→C...のアルファベット順でラベル割り当て
- チーム変更時のラベル再評価
- VisionMarker風の円形デザイン（暗い背景 + 白文字）
- ビルボードモードで常にカメラ方向を向く
- 深度テスト無効で壁越しでも視認可能

## Export設定

### Label Appearance
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `background_color` | `Color` | `(0.1, 0.1, 0.1, 0.9)` | 背景円の色 |
| `text_color` | `Color` | `(1.0, 1.0, 1.0, 1.0)` | 文字の色 |
| `height_offset` | `float` | `2.0` | 頭上からの高さ（メートル） |

### Label Size
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `background_font_size` | `int` | `128` | 背景円のフォントサイズ |
| `text_font_size` | `int` | `64` | 文字のフォントサイズ |
| `pixel_size` | `float` | `0.006` | Label3Dのピクセルサイズ |

## Public API

### add_label(character: Node) -> bool

キャラクターにラベルを追加（味方のみ）。

```gdscript
var added = label_manager.add_label(character)
if added:
    print("ラベルを追加しました")
```

**戻り値**: ラベルが追加された場合は`true`、敵または既にラベルがある場合は`false`

### remove_label(character: Node) -> void

キャラクターからラベルを削除。

```gdscript
label_manager.remove_label(character)
```

### clear_all() -> void

全ラベルをクリアし、ラベルインデックスをリセット。

```gdscript
label_manager.clear_all()
```

### refresh_labels(characters: Array) -> void

キャラクターリストに基づいてラベルを再評価。チーム変更時などに使用。

```gdscript
# チーム変更時
PlayerState.set_player_team(new_team)
label_manager.refresh_labels(characters)
```

### has_label(character: Node) -> bool

特定のキャラクターがラベルを持っているか確認。

```gdscript
if label_manager.has_label(character):
    print("ラベルあり")
```

### get_label_count() -> int

現在のラベル数を取得。

```gdscript
var count = label_manager.get_label_count()
print("味方: %d体" % count)
```

### set_label_color(character: Node, color: Color) -> void

キャラクターのラベル背景色を変更する。CharacterColorManagerと連携してキャラクター固有色を適用する際に使用。

```gdscript
var char_color = CharacterColorManager.get_character_color(character)
label_manager.set_label_color(character, char_color)
```

**引数:**
- `character` - 対象キャラクター
- `color` - 背景色（アルファは0.9に設定される）

### set_label_text(character: Node, label_char: String) -> void

キャラクターのラベルテキストを更新する。CharacterColorManagerと連携してラベル文字を設定する際に使用。

```gdscript
var label_char = CharacterColorManager.get_character_label(character)
label_manager.set_label_text(character, label_char)
```

**引数:**
- `character` - 対象キャラクター
- `label_char` - 新しいラベル文字（A-F）

## 使用例

```gdscript
# セットアップ
var label_manager: CharacterLabelManager

func _ready() -> void:
    label_manager = CharacterLabelManager.new()
    label_manager.name = "CharacterLabelManager"
    add_child(label_manager)

# キャラクター生成時
func spawn_character() -> void:
    var character = CharacterRegistry.create_character(preset_id, position)
    add_child(character)
    characters.append(character)
    label_manager.add_label(character)  # 味方ならラベル追加

# チーム変更時
func on_team_changed(new_team: int) -> void:
    PlayerState.set_player_team(new_team)
    label_manager.refresh_labels(characters)  # ラベル再評価

# キャラクター削除時
func remove_character(character: Node) -> void:
    label_manager.remove_label(character)
    character.queue_free()
```

## デザイン

```
     ┌─────┐
     │  A  │  ← 白文字（前面、Z+0.01）
     │  ●  │  ← 暗い円（背景）
     └─────┘
```

- 背景: 暗いグレー（●）、90%不透明
- 文字: 白い文字（A, B, C...）
- ビルボードモードで常にカメラを向く

## 依存クラス

- `PlayerState` - 敵味方判定（`is_enemy()`）
- `CharacterColorManager` - キャラクター個別色取得（オプション連携）
