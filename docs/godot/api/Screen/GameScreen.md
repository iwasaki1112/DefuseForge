# GameScreen

統合されたゲーム画面。TrainingモードとMultiplayerモードの両方に対応。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | Node3D |
| パス | `scripts/screens/game_screen.gd` |
| シーン | `scenes/screens/game.tscn` |

## 概要

GameScreenはゲームのメイン画面を担当し、以下の機能を提供します：

- マップのロードとキャラクタースポーン
- HUD（GameHUD, RoundHUD）の管理
- カメラとインプットの制御
- GameManagerとの連携

モード固有の処理は`GameModeProvider`に委譲されます。

## プロパティ

| 名前 | 型 | 説明 |
|------|-----|------|
| game_manager | GameManager | ゲームコアシステム |
| camera | Camera3D | メインカメラ |
| map_container | Node3D | マップの親ノード |
| ui_layer | CanvasLayer | UI用レイヤー |

## メソッド

### setup_multiplayer

```gdscript
func setup_multiplayer(net_manager: NetworkManager, map_id: String) -> void
```

Multiplayerモードでゲームを初期化します。LobbyScreenから呼ばれます。

**パラメータ:**
- `net_manager`: NetworkManagerインスタンス
- `map_id`: ロードするマップのID

**使用例:**
```gdscript
# LobbyScreenから
var game_scene = load("res://scenes/screens/game.tscn").instantiate()
get_tree().root.add_child(game_scene)
game_scene.add_child(network_manager)
game_scene.setup_multiplayer(network_manager, "park")
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
_ready() または setup_multiplayer()
    │
    ├── _setup_environment()      # 環境設定
    ├── _setup_game_manager()     # GameManager初期化
    ├── _mode_provider.initialize() # Provider初期化
    ├── _mode_provider.determine_player_team() # チーム決定
    ├── _load_map()               # マップロード
    ├── _spawn_characters()       # キャラクタースポーン
    ├── _setup_hud()              # HUD設定
    ├── _setup_round_hud()        # ラウンドHUD設定
    ├── _register_character_markers() # マーカー登録
    ├── _setup_money()            # 所持金設定
    ├── _setup_camera_pan()       # カメラパン設定
    ├── _setup_input_controller() # 入力設定
    └── _setup_camera_for_player() # カメラ位置設定
```

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

- **F3キー**: 視界デバッグ表示（Vision Debug Draw）の切り替え。敵の視界範囲やレイキャストが表示されます。

## シグナル接続

GameScreenは以下のGameManagerシグナルを購読します：

| シグナル | ハンドラ |
|---------|---------|
| selection_changed | _on_selection_changed |
| path_confirmed | _on_path_confirmed |
| paths_execution_started | _on_paths_execution_started |
| all_paths_completed | _on_all_paths_completed |
| paths_cleared | _on_paths_cleared |
| path_ready | _on_path_ready |
| path_mode_ended | _on_path_mode_ended |
| round_timer_updated | _on_round_timer_updated |
| round_ended | _on_round_ended |

## 関連クラス

- [GameModeProvider](./GameModeProvider.md)
- [TrainingModeProvider](./TrainingModeProvider.md)
- [MultiplayerModeProvider](./MultiplayerModeProvider.md)
- [GameManager](../System/GameManager.md)
- [GameHUD](../UI/GameHUD.md)
