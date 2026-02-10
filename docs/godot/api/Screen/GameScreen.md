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
    └── game_manager.set_vision_enabled(true) # 視界有効化
```

### UIコンポーネント注入

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
