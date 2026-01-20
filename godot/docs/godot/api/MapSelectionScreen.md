# MapSelectionScreen

## 概要

マップ選択画面。Training画面からの遷移先として、登録済みマップ一覧を表示し、選択してゲームを開始する。

## クラス情報

- **継承**: `Control`
- **ファイル**: `scripts/screens/map_selection_screen.gd`
- **シーン**: `scenes/screens/map_selection.tscn`

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `map_selected` | `preset_id: String` | マップが選択されたとき |

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `MAIN_MENU_SCENE` | `res://scenes/screens/main_menu.tscn` | メインメニューシーンパス |
| `GAME_SCENE` | `res://scenes/tests/test_character.tscn` | ゲームシーンパス |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `_map_container` | `GridContainer` | マップカードのコンテナ |
| `_selected_map_id` | `String` | 現在選択中のマップID |
| `_map_cards` | `Dictionary` | マップID→カードControlのマッピング |

## メソッド

### UI構築

#### `_setup_ui() -> void`
UI要素を構築する。背景、ヘッダー、マップ一覧（スクロール）、フッター（開始ボタン）を配置。

#### `_create_header() -> Control`
ヘッダー（戻るボタン、タイトル）を作成。

#### `_create_footer() -> Control`
フッター（開始ボタン）を作成。

### マップ読み込み

#### `_load_maps() -> void`
`MapRegistry.get_all()`から全マッププリセットを取得し、カードを生成。

#### `_create_map_card(preset: MapPreset) -> Control`
マッププリセットからカードUIを生成。サムネイル、マップ名、説明を表示。

### 選択処理

#### `_select_map(map_id: String) -> void`
マップを選択状態にする。前の選択を解除し、新しい選択をハイライト。開始ボタンを有効化。

#### `_start_game_with_map(map_id: String) -> void`
選択したマップIDを`SettingsManager`に保存し、ゲームシーンに遷移。

## 使用例

### シーン遷移

```gdscript
# MainMenuScreenから遷移
get_tree().change_scene_to_file("res://scenes/screens/map_selection.tscn")
```

### マップ選択の検知

```gdscript
var selection_screen = $MapSelectionScreen
selection_screen.map_selected.connect(_on_map_selected)

func _on_map_selected(preset_id: String) -> void:
    print("Selected map: ", preset_id)
```

## 画面フロー

```
MainMenu → [Training] → MapSelectionScreen → [Start Game] → GameScene
                            ↓
                       [Back] → MainMenu
```

## 依存関係

- **MapRegistry**: マッププリセット一覧の取得
- **MapPreset**: マップ情報の参照
- **SettingsManager**: 選択マップIDの保持

## 関連クラス

- [MainMenuScreen](./MainMenuScreen.md)
- [MapRegistry](./MapRegistry.md)
- [MapPreset](./MapPreset.md)
- [SettingsManager](./SettingsManager.md)
