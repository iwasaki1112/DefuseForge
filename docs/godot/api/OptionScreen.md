# OptionScreen

## 概要

プレイヤー名などの設定を変更するオプション画面。

## クラス情報

- **継承**: `Control`
- **ファイル**: `scripts/screens/option_screen.gd`
- **シーン**: `scenes/screens/option.tscn`

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `MAIN_MENU_SCENE` | `res://scenes/screens/main_menu.tscn` | メインメニュー画面 |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `_name_input` | `LineEdit` | プレイヤー名入力欄 |

## メソッド

### `_ready() -> void`
UIを生成する。

### `_setup_ui() -> void`
背景、入力フォーム、戻るボタンを構築する。

### `_on_name_submitted(_new_text: String) -> void`
入力確定時にプレイヤー名を保存する。

### `_on_back_pressed() -> void`
プレイヤー名を保存し、メインメニューへ戻る。

### `_save_name() -> void`
`SettingsManager`にプレイヤー名を保存する。

## 依存関係

- **SettingsManager**: プレイヤー名の取得/保存
- **ScreenLayout**: 背景/中央配置の共通レイアウト

## 関連クラス

- [MainMenuScreen](MainMenuScreen.md)
- [SettingsManager](SettingsManager.md)

## APIリファレンス

### シグナル
なし

### メソッド
なし
