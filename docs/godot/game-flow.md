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

マルチプレイヤー用のオートマッチング画面。

**機能**:
- 画面表示と同時にWebSocketリレーサーバーに接続しマッチング開始
- 「マッチング中...」テキスト表示（ドットアニメーション付き）
- 2人揃ったらサーバーがマッチ成立通知 → 即座にゲーム開始
- マップはサーバー側でランダム選択（home）

**フロー**:
```
MainMenu → [Multiplayer押下] → LobbyScreen
  → 自動でサーバーに接続 & FIND_MATCH送信
  → 「マッチング中...」表示 + キャンセルボタン
  → サーバーが2人揃ったらMATCH_FOUND通知
  → 即座にGameScreenへ遷移
```

**チーム割り当て**:
- 先にキューに入ったプレイヤー = Host (peer_id=1) = CT
- 後からキューに入ったプレイヤー = Client (peer_id=2) = T

| ボタン | 遷移先 | 説明 |
|--------|--------|------|
| キャンセル | MainMenuScreen | マッチングをキャンセルしてメインメニューに戻る |

### 5. GameScreen

**シーン**: `scenes/screens/game.tscn`
**スクリプト**: `scripts/screens/game_screen.gd`

ゲームプレイ画面。選択したマップでキャラクターをTPS操作する。

**初期化処理**:
1. プレイヤーチームを決定（Training: CT固定、Multiplayer: ネットワーク情報から決定）
2. GameManagerをセットアップ
3. 選択マップをロード
4. FogOfWarSystemのマップサイズを更新（`set_map_size()`を使用）
5. キャラクターをスポーン位置に配置
6. TPSPlayerControllerをセットアップ（プレイヤーキャラクター操作用）
7. チーム表示UIを更新
8. 視界システムを有効化

**注意**: マップロード後、`FogOfWarSystem.set_map_size()`でマップサイズを更新すること。プロパティ直接変更では反映されない。

**主要システム**:
- `GameManager` - コアシステム初期化・更新
- `TPSPlayerController` - TPS操作（移動/エイム/カメラ/ジョイスティック）
- `MapManager` - マップ読み込み・クリーンアップ
- `FogOfWarSystem` - 視界システム
- `EnemyVisibilitySystem` - 敵可視性制御

**シーン構造**:
```
GameScreen (Node3D)
├─ WorldEnvironment
├─ DirectionalLight3D
├─ Camera3D (TPS固定カメラ)
├─ MapContainer (Node3D) ← マップがロードされる
├─ TPSPlayerController (Node) ← プレイヤー操作
└─ UILayer (CanvasLayer)
    ├─ TeamDisplayLabel ← "You are CT/T" 表示
    ├─ MoveStickBase ← 左ジョイスティック（モバイル）
    └─ AimStickBase ← 右ジョイスティック（モバイル）
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
       ├─ _mode_provider.determine_player_team() でチーム決定（Training: CT固定 / Multiplayer: ネットワーク情報）
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

マップは自己記述型の `.tscn` シーンとして `scenes/maps/` に配置。
各マップは `MapBase` を継承し、`@export` でメタデータ（`map_id`, `display_name`, `map_description`）を埋め込む。
`MapRegistry` が起動時に `scenes/maps/` をスキャンし、`map_id` 付きシーンを自動検出・登録。

| ID | 表示名 | シーン | 説明 |
|----|--------|--------|------|
| `home` | Home | `scenes/maps/home.tscn` | GridMapタイルマップ |

### マップの追加方法

1. `godot --headless --script res://scripts/editor/new_gridmap_map.gd -- <map_id>` でテンプレート生成
2. Godotエディタでタイル配置
3. `scenes/maps/` に保存 → MapRegistryが自動検出

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
| MapPreset | マップ定義リソース（MapBase @exportから自動生成） |
| MapManager | マップライフサイクル管理 |
| GameManager | ゲームシステム統括 |
| PlayerState | プレイヤーチーム管理 |
| CharacterRegistry | キャラクター生成 |
