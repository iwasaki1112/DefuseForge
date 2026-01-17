# CharacterColorManager

キャラクター個別色管理システム（Autoload）。味方キャラクターに固有色を割り当て、頭上ラベル・パス線・VisionMarker・RunMarkerで統一的に使用する。

## クラス情報

- **継承**: Node
- **Autoload名**: CharacterColorManager
- **ファイル**: `scripts/systems/character_color_manager.gd`

## 色パレット

6色の固定パレットを使用（モバイル最適化）：

| インデックス | ラベル | 色名 | RGB値 |
|-------------|--------|------|-------|
| 0 | A | 青 | (0.2, 0.6, 1.0) |
| 1 | B | 緑 | (0.2, 0.8, 0.2) |
| 2 | C | 黄 | (1.0, 0.8, 0.0) |
| 3 | D | 紫 | (0.8, 0.3, 0.8) |
| 4 | E | オレンジ | (1.0, 0.5, 0.0) |
| 5 | F | シアン | (0.0, 0.8, 0.8) |

## 定数

```gdscript
const COLOR_PALETTE: Array[Color]  # 6色のカラーパレット
const DEFAULT_COLOR: Color = Color(0.5, 0.5, 0.5)  # 未割り当て時のデフォルト色
```

## シグナル

### color_assigned
```gdscript
signal color_assigned(character: Node, color: Color, index: int)
```
キャラクターに色が割り当てられた時に発火。

### color_released
```gdscript
signal color_released(character: Node)
```
キャラクターの色が解放された時に発火。

## Public API

### assign_color
```gdscript
func assign_color(character: Node) -> int
```
キャラクターに色を割り当てる。

**パラメータ:**
- `character`: 色を割り当てるキャラクター

**戻り値:** 割り当てられた色インデックス（0-5）、失敗時は-1

### release_color
```gdscript
func release_color(character: Node) -> void
```
キャラクターの色割り当てを解放する。

**パラメータ:**
- `character`: 色を解放するキャラクター

### get_character_color
```gdscript
func get_character_color(character: Node) -> Color
```
キャラクターに割り当てられた色を取得する。

**パラメータ:**
- `character`: キャラクター

**戻り値:** 割り当てられた色（未割り当ての場合はDEFAULT_COLOR）

### get_character_color_index
```gdscript
func get_character_color_index(character: Node) -> int
```
キャラクターの色インデックスを取得する。

**パラメータ:**
- `character`: キャラクター

**戻り値:** 色インデックス（-1 = 未割り当て）

### get_color_by_index
```gdscript
func get_color_by_index(index: int) -> Color
```
インデックスから色を取得する。

**パラメータ:**
- `index`: 色インデックス（0-5）

**戻り値:** 色

### get_label_char
```gdscript
func get_label_char(index: int) -> String
```
インデックスからラベル文字を取得する。

**パラメータ:**
- `index`: 色インデックス（0-5）

**戻り値:** ラベル文字（A-F）

### get_character_label
```gdscript
func get_character_label(character: Node) -> String
```
キャラクターのラベル文字を取得する。

**パラメータ:**
- `character`: キャラクター

**戻り値:** ラベル文字（未割り当ての場合は"?"）

### has_color
```gdscript
func has_color(character: Node) -> bool
```
キャラクターに色が割り当てられているか確認する。

**パラメータ:**
- `character`: キャラクター

**戻り値:** 割り当て済みならtrue

### clear_all
```gdscript
func clear_all() -> void
```
全ての色割り当てをクリアする。

### get_assigned_count
```gdscript
func get_assigned_count() -> int
```
現在割り当てられている色の数を取得する。

### get_palette_size
```gdscript
func get_palette_size() -> int
```
パレットの色数を取得する（常に6）。

## 使用例

### 基本的な使用
```gdscript
# キャラクターに色を割り当て
var index = CharacterColorManager.assign_color(character)
if index >= 0:
    var color = CharacterColorManager.get_character_color(character)
    var label = CharacterColorManager.get_character_label(character)
    print("Assigned color %s (%s) to character" % [label, color])

# 色を解放
CharacterColorManager.release_color(character)
```

### UIコンポーネントとの連携
```gdscript
# ラベルに色を適用
var color = CharacterColorManager.get_character_color(character)
label_manager.set_label_color(character, color)

# パス描画に色を適用
path_drawer.set_character_color(color)
```

### チーム変更時の再割り当て
```gdscript
func _on_team_changed():
    CharacterColorManager.clear_all()
    for character in friendly_characters:
        CharacterColorManager.assign_color(character)
        # ラベル更新...
```

## 設計ノート

- **Autoload**: PlayerState、CharacterRegistryと同じパターンでグローバルアクセス可能
- **固定パレット**: 6色は視認性を保ちつつモバイル向けに最適化
- **最小インデックス優先**: 色解放後、最小の空きインデックスから再利用
- **敵キャラクターは対象外**: 味方キャラクターのみに色を割り当てる（呼び出し側で制御）

## 関連クラス

- **CharacterLabelManager**: 色を頭上ラベルに反映
- **PathDrawer**: 色をパス線・VisionMarker・RunMarkerに伝播
- **VisionMarker**: `set_colors()`で色を設定
- **RunMarker**: `set_colors()`で色を設定
