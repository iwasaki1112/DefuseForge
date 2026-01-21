# CharacterSelectedMarker

キャラクター選択時に足元に表示される回転マーカー。

## 概要

- **継承**: `Sprite3D`
- **ファイル**: `scripts/effects/character_selected_marker.gd`
- **用途**: 選択中のキャラクターを視覚的に示す

## 機能

- 選択中のキャラクターの足元にマーカー画像を表示
- 360度連続回転ループ
- キャラクターの移動に自動追従

## エクスポート変数

| 変数名 | 型 | デフォルト | 説明 |
|--------|------|------------|------|
| `rotation_speed` | `float` | `90.0` | 回転速度（度/秒）|
| `height_offset` | `float` | `0.05` | 地面からの高さ |
| `marker_scale` | `float` | `1.0` | マーカーのスケール |

## 主要メソッド

### attach_to_character(character: Node) -> void

マーカーをキャラクターにアタッチし、位置追従を開始する。

```gdscript
var marker = CharacterSelectedMarker.new()
marker.attach_to_character(some_character)
parent_node.add_child(marker)
```

### show_marker() -> void

マーカーを表示する。

### hide_marker() -> void

マーカーを非表示にする。

## 使用例

`CharacterSelectionManager`が内部で自動管理するため、通常は直接使用する必要はない。

```gdscript
# CharacterSelectionManagerが自動的に管理
selection_manager.add_to_selection(character)  # マーカーが自動表示
selection_manager.remove_from_selection(character)  # マーカーが自動削除
```

## アセット

- **テクスチャ**: `assets/ui/character_selected_marker/character_selected_marker.png`

## 関連クラス

- `CharacterSelectionManager` - マーカーのライフサイクル管理
