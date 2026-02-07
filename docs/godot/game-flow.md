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
│  - Multiplayer  │
│  - Option       │
└────────┬────────┘
         │
    ┌────┼──────────────┐
    ▼    │              ▼
┌────────┐  │  ┌────────────┐
│ Option │  │  │ MapSelection│  Training
│ Screen │  │  │   Screen    │
└────────┘  │  └──────┬─────┘
    │       │         │
    │       │    [Start Game]
    ▼       ▼         ▼
┌────────┐  ┌────────────┐  ┌────────────┐
│  Back  │  │ LobbyScreen│  │ GameScreen │
└────────┘  └──────┬─────┘  └────────────┘
                   │
              [Start Game]
                   ▼
            ┌────────────┐
            │ GameScreen │  Multiplayer
            └────────────┘
```

## 画面詳細

### 1. MainMenuScreen

**シーン**: `scenes/screens/main_menu.tscn`
**スクリプト**: `scripts/screens/main_menu_screen.gd`

ゲーム起動時に最初に表示されるメニュー画面。

| ボタン | 遷移先 | 説明 |
|--------|--------|------|
| Training | MapSelectionScreen | シングルプレイヤー（トレーニング）へ |
| Multiplayer | LobbyScreen | マルチプレイヤーロビーへ |
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

プレイするマップを選択する画面（Trainingモード用）。

**機能**:
- `MapRegistry`から登録済みマップ一覧を取得
- マップをカード形式（サムネイル・名前・説明）で表示
- マップ選択でハイライト表示
- 「Start Game」でゲームシーンに遷移

| ボタン | 遷移先 | 説明 |
|--------|--------|------|
| Back | MainMenuScreen | メインメニューに戻る |
| Start Game | GameScreen | 選択したマップでゲーム開始 |

### 4. LobbyScreen

**シーン**: `scenes/screens/lobby.tscn`
**スクリプト**: `scripts/screens/lobby_screen.gd`

マルチプレイヤー用のロビー画面。

**機能**:
- WebSocketリレーサーバーへの接続
- ルーム作成・参加
- プレイヤー一覧表示・準備完了状態の切り替え
- ホストによるゲーム開始

| ボタン | 遷移先 | 説明 |
|--------|--------|------|
| Back | MainMenuScreen | メインメニューに戻る |
| Start Game | GameScreen | 全員準備完了時にホストが開始 |

### 5. GameScreen

**シーン**: `scenes/screens/game.tscn`
**スクリプト**: `scripts/screens/game_screen.gd`

ゲームプレイ画面。選択したマップでキャラクターを操作する。

**初期化処理**:
1. プレイヤーチームをランダムに決定（CT/T）
2. GameManagerをセットアップ
3. 選択マップをロード
4. FogOfWarSystemのマップサイズを更新（`set_map_size()`を使用）
5. キャラクターをスポーン位置に配置
6. チーム表示UIを更新
7. 視界システムを有効化

**注意**: マップロード後、`FogOfWarSystem.set_map_size()`でマップサイズを更新すること。プロパティ直接変更では反映されない。

**主要システム**:
- `GameManager` - コアシステム初期化・更新
- `MapManager` - マップ読み込み・クリーンアップ
- `CharacterSelectionManager` - キャラクター選択
- `PathExecutionManager` - パス描画・実行
- `FogOfWarSystem` - 視界システム
- `EnemyVisibilitySystem` - 敵可視性制御

**シーン構造**:
```
GameScreen (Node3D)
├─ WorldEnvironment
├─ DirectionalLight3D
├─ Camera3D (俯瞰視点)
├─ MapContainer (Node3D) ← マップがロードされる
└─ UILayer (CanvasLayer)
    └─ TeamDisplayLabel ← "You are CT/T" 表示
```

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

4. GameScreen読み込み
   └─ GameScreen._ready()
       ├─ PlayerState.set_player_team() でランダムチーム決定
       ├─ GameManager.setup() でシステム初期化
       ├─ GameManager.load_map() でマップロード
       │   └─ SettingsManager.get_selected_map() でマップID取得
       │   └─ MapRegistry.get_preset(map_id) でプリセット取得
       └─ キャラクタースポーン
           └─ CharacterRegistry.create_character() でキャラクター生成
           └─ GameManager.register_character() で登録
```

### キャラクタースポーン詳細

```
GameScreen._spawn_characters()
├─ game_manager.map_manager.current_preset からスポーン位置取得
├─ CT側スポーン
│   ├─ CharacterRegistry.get_counter_terrorists() でCTプリセット取得
│   └─ spawn_points_ct の位置にキャラクター配置
└─ T側スポーン
    ├─ CharacterRegistry.get_terrorists() でTプリセット取得
    └─ spawn_points_t の位置にキャラクター配置
```

## 登録済みマップ

マッププリセットは `data/maps/` ディレクトリに `.tres` ファイルとして配置。
`MapRegistry` が起動時に自動読み込み。

| ID | 表示名 | シーン | 説明 |
|----|--------|--------|------|
| `iwasaki_test` | Iwasaki Test | `scenes/maps/iwasaki_test.tscn` | 開発用マップ |

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
| LobbyScreen | マルチプレイヤーロビーUI |
| GameScreen | ゲームプレイ画面 |
| SettingsManager | 設定永続化・選択マップ保持 |
| MapRegistry | マッププリセット管理 |
| MapPreset | マップ定義リソース |
| MapManager | マップライフサイクル管理 |
| GameManager | ゲームシステム統括 |
| PlayerState | プレイヤーチーム管理 |
| CharacterRegistry | キャラクター生成 |
