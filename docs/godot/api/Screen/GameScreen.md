# GameScreen

統合されたゲーム画面（TPS版）。TrainingモードとMultiplayerモードの両方に対応。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | Node3D |
| パス | `scripts/screens/game_screen.gd` |
| シーン | `scenes/screens/game.tscn` |

## 概要

GameScreenはゲームのメイン画面を担当し、以下の機能を提供します：

- マップのロードとキャラクタースポーン
- TPS操作（TPSPlayerControllerによる移動/エイム/カメラ）
- HUD（HP、クロスヘア、RoundHUD）の管理
- GameManagerとの連携
- **UIコンポーネントの生成とGameManagerへの注入**（`CharacterLabelManager`）

モード固有の処理は`GameModeProvider`に委譲されます。

## プロパティ

| 名前 | 型 | 説明 |
|------|-----|------|
| game_manager | GameManager | ゲームコアシステム |
| camera | Camera3D | メインカメラ |
| map_container | Node3D | マップの親ノード |
| ui_layer | CanvasLayer | UI用レイヤー |
| _tps_controller | TPSPlayerController | TPS操作コントローラー |
| _player_character | GameCharacter | プレイヤーキャラクター |

## メソッド

### setup_multiplayer

```gdscript
func setup_multiplayer(net_manager: NetworkManager, map_id: String) -> void
```

MultiplayerモードのプロバイダーとマップIDを設定します。LobbyScreenから呼ばれます。

**重要:** `add_child()`でシーンツリーに追加する**前に**呼ぶこと。
`_ready()`で`_initialize_game()`が一度だけ正しいProviderで実行されます。

**パラメータ:**
- `net_manager`: NetworkManagerインスタンス
- `map_id`: ロードするマップのID

**使用例:**
```gdscript
# LobbyScreenから
var game_scene = load("res://scenes/screens/game.tscn").instantiate()
game_scene.setup_multiplayer(network_manager, "park")  # add_child前に呼ぶ
get_tree().root.add_child(game_scene)  # _ready() → _initialize_game()
game_scene.add_child(network_manager)
```

### cleanup

```gdscript
func cleanup() -> void
```

リソースのクリーンアップを行います。
- マップのアンロード（キャラクター含む）
- HUDの削除
- ネットワーク接続の切断（MultiplayerModeProvider経由）
- PlayerStateシグナルの切断

## 初期化フロー

```
_ready()  ※setup_multiplayer()はadd_child前に呼ばれ、Providerを設定するのみ
    │
    ├── _setup_environment()         # 環境設定
    ├── _setup_game_manager()        # GameManager初期化
    │     ├── _setup_label_manager() # CharacterLabelManager生成→注入
    │     └── game_manager.setup()   # サブシステム初期化（Factory使用）
    ├── _mode_provider.initialize()  # Provider初期化
    ├── PlayerState.set_player_team() # チーム決定（CT固定）
    ├── _load_map()                  # マップロード
    ├── _spawn_characters()          # キャラクタースポーン
    ├── _setup_tps_hud()             # TPS HUD設定（HP、クロスヘア）
    ├── _setup_round_hud()           # ラウンドHUD設定
    ├── _setup_tps_controller()      # TPSPlayerController初期化
    ├── await _play_intro_sequence() # カメライントロ演出（マップ俯瞰→プレイヤー上空）
    └── game_manager.set_vision_enabled(true) # 視界有効化
```

### UIコンポーネント注入

**※ 現在無効化中**（`_setup_label_manager()` がコメントアウト済み）

GameScreenはUIコンポーネントを生成し、GameManagerに注入する責務を持つ。
これはUI関連の責務をGameManagerから分離するためのパターン。

```gdscript
# GameScreen._setup_label_manager()
func _setup_label_manager() -> void:
    var lm := CharacterLabelManager.new()
    lm.name = GameConstants.NODE_LABEL_MANAGER
    game_manager.add_child(lm)
    game_manager.set_label_manager(lm)
```

## カメライントロシーケンス

ゲーム開始時にマップ全体の俯瞰ショットからプレイヤーキャラクター上空へカメラが移動する演出。

- `_play_intro_sequence()`: 初期化完了後（`_setup_tps_controller()`の後）にawaitで呼び出し
- **オーバービュー位置**: 全スポーン地点の平均位置上空（高さ = `max(map_size.x, map_size.y) * 1.5`、25〜60mにクランプ）
- **Tween**: `EASE_IN_OUT` + `TRANS_CUBIC` で2.5秒かけてプレイヤー上空（通常の14m高さ）へ移動
- **ガード**: イントロ中は `_is_intro_playing = true` → `_physics_process`でTPS操作停止、`_input`で入力無視、HUD非表示

## HP表示

画面左下にプレイヤーキャラクターのHPをバー＋数値で表示します。

- **位置**: 左下（ジョイスティックの上）
- **構成**: `HBoxContainer` > `ProgressBar`(160x20) + `Label`(数値)
- **色変化**: HP割合に応じて自動変更
  - 50%超: 緑 `(0.2, 0.8, 0.2)`
  - 25〜50%: 黄 `(0.9, 0.7, 0.1)`
  - 25%以下: 赤 `(0.9, 0.2, 0.2)`
- **更新**: `_update_tps_hud()` で毎フレーム `get_health_ratio()` と `current_health` を参照

## TPS操作

`_setup_tps_controller()`でTPSPlayerControllerを初期化し、プレイヤーキャラクターの操作を委譲。

```gdscript
func _setup_tps_controller() -> void:
    _tps_controller = TPSPlayerController.new()
    _tps_controller.name = "TPSPlayerController"
    add_child(_tps_controller)
    _tps_controller.setup(_player_character, camera, ui_layer)
```

`_physics_process`でTPSPlayerController.process()を呼び出し、`_input`でhandle_input()を呼び出す。

## モード判定

```gdscript
# モード名で判定
if _mode_provider.get_mode_name() == "multiplayer":
    # Multiplayer固有の処理

# 型で判定
if _mode_provider is MultiplayerModeProvider:
    var mp = _mode_provider as MultiplayerModeProvider
    var is_host = mp.is_host()
```

## スプリント

SprintBtnボタンを押している間、キャラクターがスプリントモードで移動します。

- **ボタン**: `action_buttons.tscn` の SprintBtn（常時表示）
- **操作**: ボタンを押し続けながら左スティック/WASDで移動
- **PC**: Shiftキーでもスプリント可能
- **スプリント中の制限**:
  - 右スティックエイム無効化（キャラクターは移動方向を向く）
  - 自動射撃無効化
  - 移動速度 6.0m/s（通常歩行 2.0m/s）
- **アニメーション**: `game_rifle_sprint` / `game_pistol_sprint`（SpeedBlendで切替）

## ドア開けインタラクション

プレイヤーがドアの近くにいるとき、DoorOpenBtnボタンが表示されます。

- `_update_door_proximity()`: 毎フレーム "doors" グループの未開ドアとの近接チェック（距離 `DOOR_OPEN_DISTANCE = 1.5m`、壁越しレイキャスト判定あり）
- `_on_door_open_pressed()`: ボタン押下 → ドアの方を向く → 向きロック → `play_door_open()` アニメーション再生
- `_on_door_open_impact()`: アニメーション途中（0.7秒後）で `DoorService.on_door_open_done()` を呼びドアを開く
- `_on_door_open_anim_finished()`: アニメーション完了 → 向きロック解除

**キックとの違い**: ドアキック（170°、0.4秒、バウンス）に対し、ドア開け（90°、0.8秒、イーズイン/アウト）は穏やか。

## 人質（Hostage）機能

人質はTraining/Multiplayer両モードで共通にスポーンされます。

- `_spawn_hostages()`: マッププリセットの`spawn_points_hostage`から人質をスポーン
- `_spawn_hostage_character()`: 個別の人質を構築（Team.NONE、無敵、Hostageアニメーションループ）
- `_update_hostage_proximity()`: 毎フレーム近接チェック（CT側のみ交渉可能）
- `_on_talking_btn_pressed()`: 交渉開始（10秒プログレスバー）
- `_complete_talking()`: 交渉完了 → CT勝利（HOSTAGE_RESCUED）
- **移動キャンセル**: Talk中に左スティックまたはWASDで移動入力するとTalkがキャンセルされる

**チーム制限**: T側プレイヤーは人質交渉ボタンが表示されません。

## グレネードエイミング

グレネードボタン押下でエイミングモードに入り、画面タップでターゲット位置を選択します。

- **移動キャンセル**: エイミング中に左スティック（ドラッグ）またはWASDで移動入力するとエイミングがキャンセルされる
- **タップ/ドラッグ判定**: 画面左側タッチはタップ（ターゲット選択）とドラッグ（移動意図→キャンセル）を判別する。20px以上ドラッグでキャンセル、それ以下でリリース時にターゲット選択。画面右側タッチは即座にターゲット選択。

## デバッグ機能

- **F3キー**: 視界デバッグ表示（Vision Debug Draw）の切り替え
- **Debug.enabled時**: Door Kick, Door Open, Debug Visionボタンが表示

## シグナル接続

GameScreenは以下のシグナルを購読します：

| シグナル | ソース | ハンドラ |
|---------|--------|---------|
| round_timer_updated | GameManager | _on_round_timer_updated |
| round_ended | GameManager | _on_round_ended |

## 関連クラス

- [GameModeProvider](./GameModeProvider.md)
- [TrainingModeProvider](./TrainingModeProvider.md)
- [MultiplayerModeProvider](./MultiplayerModeProvider.md)
- [GameManager](../System/GameManager.md)
- [TPSPlayerController](../Controllers/TPSPlayerController.md) - TPS操作制御
- [CharacterLabelManager](../UI/CharacterLabelManager.md) - GameScreenが生成しGameManagerに注入
