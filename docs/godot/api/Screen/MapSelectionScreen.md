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
| `GAME_SCENE` | `res://scenes/screens/game.tscn` | ゲームシーンパス |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `_map_container` | `HBoxContainer` | マップカードのコンテナ |
| `_selected_map_id` | `String` | 現在選択中のマップID |
| `_map_cards` | `Dictionary` | マップID→カードTextureButtonのマッピング |
| `_start_btn` | `TextureButton` | 開始ボタン |

## メソッド

### UI構築

#### `_setup_ui() -> void`
UI要素を構築する。
- **背景**: `BACKGROUND_TEXTURE` を画面全体に表示。
- **マップ一覧**: 画面中央に横スクロール可能な `ScrollContainer` と `HBoxContainer` を配置。
- **Backボタン**: 左下に配置。
- **Startボタン**: 右下に配置（マップ未選択時は無効化）。

#### `_create_texture_button(texture: Texture2D) -> TextureButton`
共通設定（アスペクト比保持など）で画像ボタンを作成するヘルパー。

### マップ読み込み

#### `_load_maps() -> void`
`MapRegistry.get_all()`から全マッププリセットを取得し、`_create_map_card` でカードを生成してコンテナに追加する。

#### `_create_map_card(preset: MapPreset) -> TextureButton`
マッププリセットに対応するカードボタンを生成する。
現在は `MAP_CARD_TEXTURE` を使用した統一デザイン。

### 選択処理

#### `_on_map_card_pressed(map_id: String) -> void`
カード押下時のコールバック。`_select_map` を呼び出す。

#### `_select_map(map_id: String) -> void`
マップを選択状態にする。
- 前の選択カードのハイライトを解除。
- 新しい選択カードをハイライト（`modulate` 変更）。
- Startボタンを有効化。
- `map_selected` シグナルを発火。

#### `_on_start_pressed() -> void`
Startボタン押下時、選択中のマップでゲームを開始する（`_start_game_with_map` 呼び出し）。

#### `_start_game_with_map(map_id: String) -> void`
選択したマップIDを `SettingsManager` に保存し、ゲームシーンへ遷移する。

## 画面フロー

```
MainMenu → [Training] → MapSelectionScreen → [Start] → GameScene
                            ↓
                       [Back] → MainMenu
```

## 依存関係

- **MapRegistry**: マッププリセット一覧の取得
- **SettingsManager**: 選択マップIDの保持（Autoload）

## 関連クラス

- [MainMenuScreen](./MainMenuScreen.md)
- [MapRegistry](./Registry/MapRegistry.md)
- [MapPreset](./Resource/MapPreset.md)
- [SettingsManager](./System/SettingsManager.md)