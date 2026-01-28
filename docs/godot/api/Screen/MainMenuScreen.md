# MainMenuScreen

## 概要

ゲーム起動時に表示されるメインメニュー画面。Training、Multiplayer、Option画面への遷移を提供する。

## クラス情報

- **継承**: `Control`
- **ファイル**: `scripts/screens/main_menu_screen.gd`
- **シーン**: `scenes/screens/main_menu.tscn`

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `MAP_SELECTION_SCENE` | `res://scenes/screens/map_selection.tscn` | マップ選択画面（Training） |
| `OPTION_SCENE` | `res://scenes/screens/option.tscn` | オプション画面 |
| `LOBBY_SCENE` | `res://scenes/screens/lobby.tscn` | ロビー画面（Multiplayer） |

## UI構成

- **Logo**: 画面上部中央に表示されるゲームロゴ。
- **Button Container**: 画面中央に配置されるボタン群。
    - **Training Button**: ソロプレイ/トレーニングモードへ（マップ選択へ遷移）。
    - **Multiplayer Button**: マルチプレイモードへ（ロビーへ遷移）。
- **Option Button**: 画面右上に配置される設定ボタン（アイコン）。

## メソッド

### `_ready() -> void`
UIを構築する (`_setup_ui` を呼び出す)。

### `_setup_ui() -> void`
コードベースでUI要素（ロゴ、ボタンなど）を動的に生成・配置する。
`ScreenLayout` を使用せず、直接 `Control` ノードを生成してレイアウトしている。

### `_create_texture_button(texture: Texture2D) -> TextureButton`
画像ボタンを作成するヘルパーメソッド。

### `_on_training_pressed() -> void`
Trainingボタン押下時にマップ選択画面へ遷移。

### `_on_multiplayer_pressed() -> void`
Multiplayerボタン押下時にロビー画面へ遷移。

### `_on_option_pressed() -> void`
Optionボタン押下時にオプション画面へ遷移。

## 関連クラス

- [MapSelectionScreen](MapSelectionScreen.md)
- [LobbyScreen](LobbyScreen.md)
- [OptionScreen](OptionScreen.md)