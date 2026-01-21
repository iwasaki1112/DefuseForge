# MainMenuScreen

## 概要

ゲーム起動時に表示されるメインメニュー画面。TrainingとOptionへ遷移する。

## クラス情報

- **継承**: `Control`
- **ファイル**: `scripts/screens/main_menu_screen.gd`
- **シーン**: `scenes/screens/main_menu.tscn`

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `MAP_SELECTION_SCENE` | `res://scenes/screens/map_selection.tscn` | マップ選択画面 |
| `OPTION_SCENE` | `res://scenes/screens/option.tscn` | オプション画面 |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `_welcome_label` | `Label` | プレイヤー名のウェルカム表示 |

## メソッド

### `_ready() -> void`
UI構築後、プレイヤー名表示を更新し、設定変更シグナルを購読する。

### `_setup_ui() -> void`
背景・タイトル・ボタンを含むメニューUIを生成する。

### `_update_welcome_message() -> void`
`SettingsManager`からプレイヤー名を取得して表示する。

### `_on_training_pressed() -> void`
Trainingボタン押下時にマップ選択画面へ遷移。

### `_on_option_pressed() -> void`
Optionボタン押下時にオプション画面へ遷移。

## 依存関係

- **SettingsManager**: プレイヤー名の取得
- **ScreenLayout**: 背景/中央配置の共通レイアウト

## 関連クラス

- [MapSelectionScreen](MapSelectionScreen.md)
- [OptionScreen](OptionScreen.md)
- [SettingsManager](SettingsManager.md)
