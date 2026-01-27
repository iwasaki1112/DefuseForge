# ScreenLayout

## 概要

画面UIの共通レイアウト生成ヘルパー。背景の作成や中央配置コンテナ生成を提供する。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/ui/screen_layout.gd`

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `DEFAULT_BG_COLOR` | `Color(0.1, 0.1, 0.15, 1.0)` | 背景のデフォルト色 |

## メソッド

### `add_solid_background(root: Control, color: Color = DEFAULT_BG_COLOR) -> ColorRect`
背景用の`ColorRect`を生成して追加する。

### `create_centered_vbox(root: Control, separation: int = 30) -> VBoxContainer`
中央配置の`VBoxContainer`を生成して返す。

## 使用例

```gdscript
ScreenLayout.add_solid_background(self)
var vbox := ScreenLayout.create_centered_vbox(self, 30)
```

## 関連クラス

- [MainMenuScreen](MainMenuScreen.md)
- [OptionScreen](OptionScreen.md)

## APIリファレンス

### シグナル
なし

### メソッド
なし
