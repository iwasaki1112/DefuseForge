# ゲームフロー

## 概要

RescueForgeのゲーム起動からプレイまでの画面遷移とシステムの流れを説明する。

## 画面遷移図

```
┌─────────────────┐
│   アプリ起動     │
└────────┬────────┘
         ▼
┌─────────────────┐
│  MainMenuScreen │  メインメニュー
│  - Training     │
│  - Option       │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐  ┌────────────┐
│ Option │  │ MapSelection│  マップ選択
│ Screen │  │   Screen    │
└────────┘  └──────┬─────┘
    │              │
    │         [Start Game]
    ▼              ▼
┌────────┐  ┌────────────┐
│  Back  │  │ GameScene  │  ゲームプレイ
└────────┘  │(test_char) │
            └────────────┘
```

## 画面詳細

### 1. MainMenuScreen

**シーン**: `scenes/screens/main_menu.tscn`
**スクリプト**: `scripts/screens/main_menu_screen.gd`

ゲーム起動時に最初に表示されるメニュー画面。

| ボタン | 遷移先 | 説明 |
|--------|--------|------|
| Training | MapSelectionScreen | マップ選択画面へ |
| Option | OptionScreen | 設定画面へ |

**表示内容**:
- ゲームタイトル「RescueForge」
- プレイヤー名（Welcome, {name}）

### 2. OptionScreen

**シーン**: `scenes/screens/option.tscn`
**スクリプト**: `scripts/screens/option_screen.gd`

プレイヤー設定を変更する画面。

**設定項目**:
- プレイヤー名（`SettingsManager`で永続化）

### 3. MapSelectionScreen

**シーン**: `scenes/screens/map_selection.tscn`
**スクリプト**: `scripts/screens/map_selection_screen.gd`

プレイするマップを選択する画面。

**機能**:
- `MapRegistry`から登録済みマップ一覧を取得
- マップをカード形式（サムネイル・名前・説明）で表示
- マップ選択でハイライト表示
- 「Start Game」でゲームシーンに遷移

| ボタン | 遷移先 | 説明 |
|--------|--------|------|
| Back | MainMenuScreen | メインメニューに戻る |
| Start Game | GameScene | 選択したマップでゲーム開始 |

### 4. GameScene (test_character)

**シーン**: `scenes/tests/test_character.tscn`

ゲームプレイ画面。選択したマップで戦闘を行う。

**主要システム**:
- `GameManager` - コアシステム初期化・更新
- `MapManager` - マップ読み込み・クリーンアップ
- `CharacterSelectionManager` - キャラクター選択
- `PathExecutionManager` - パス描画・実行
- `FogOfWarSystem` - 視界システム

## データフロー

### マップ選択からゲーム開始まで

```
1. MapSelectionScreen
   └─ MapRegistry.get_all() でマップ一覧取得

2. ユーザーがマップを選択
   └─ _select_map(map_id) でハイライト

3. Start Gameボタン押下
   └─ SettingsManager.set_selected_map(map_id) で選択マップを保存
   └─ change_scene_to_file(GAME_SCENE)

4. GameScene読み込み
   └─ GameManager._ready()
       └─ MapManager.load_map_from_settings()
           └─ SettingsManager.get_selected_map() でマップID取得
           └─ MapRegistry.instantiate_map(map_id) でマップ生成
```

## 登録済みマップ

マッププリセットは `data/maps/` ディレクトリに `.tres` ファイルとして配置。
`MapRegistry` が起動時に自動読み込み。

| ID | 表示名 | シーン | 説明 |
|----|--------|--------|------|
| `test` | Test Map | `scenes/maps/test.tscn` | 基本テストマップ |
| `iwasaki_test` | Iwasaki Test | `scenes/maps/iwasaki_test.tscn` | GridMap開発用マップ |

### マップの追加方法

1. マップシーンを `scenes/maps/` に作成
2. `data/maps/` にMapPresetリソース（.tres）を作成
3. プリセットに以下を設定:
   - `id`: 一意のID
   - `display_name`: 表示名
   - `description`: 説明文
   - `map_scene`: マップシーンへの参照
   - `map_size`: マップサイズ（FoW用）
   - `spawn_points_ct` / `spawn_points_t`: スポーン位置

## 関連クラス

| クラス | 役割 |
|--------|------|
| MainMenuScreen | メインメニューUI |
| MapSelectionScreen | マップ選択UI |
| OptionScreen | 設定UI |
| SettingsManager | 設定永続化・選択マップ保持 |
| MapRegistry | マッププリセット管理 |
| MapPreset | マップ定義リソース |
| MapManager | マップライフサイクル管理 |
| GameManager | ゲームシステム統括 |
