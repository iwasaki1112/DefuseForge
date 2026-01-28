# MultiplayerModeProvider

Multiplayerモード用のプロバイダー。ネットワーク関連の処理をすべて内包します。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | GameModeProvider |
| パス | `scripts/screens/multiplayer_mode_provider.gd` |

## 概要

MultiplayerModeProviderはネットワーク同期に必要なすべての処理を担当します：

- NetworkManagerとSyncControllerの保持
- ネットワークイベントのハンドリング
- パス実行とグレネードの同期
- ピア切断の処理

## プロパティ

| 名前 | 型 | 説明 |
|------|-----|------|
| network_manager | NetworkManager | ネットワーク管理 |
| sync_controller | MultiplayerSyncController | 同期コントローラー |

## メソッド

### setup_network

```gdscript
func setup_network(net_manager: NetworkManager) -> void
```

NetworkManagerを設定します。LobbyScreenから`setup_multiplayer`が呼ばれる前に実行されます。

**パラメータ:**
- `net_manager`: LobbyScreenから渡されるNetworkManager

### initialize

```gdscript
func initialize(game_screen: Node, game_manager: GameManager) -> void
```

プロバイダーを初期化し、SyncControllerのセットアップとネットワークイベントの接続を行います。

### is_host

```gdscript
func is_host() -> bool
```

ホストかどうかを返します。

### get_player_count

```gdscript
func get_player_count() -> int
```

接続中のプレイヤー数を返します。

### get_character_owner_id

```gdscript
func get_character_owner_id(team: int) -> int
```

指定チームのキャラクターを所有するピアIDを返します。

## ネットワークイベント

### _on_peer_disconnected

```gdscript
func _on_peer_disconnected(peer_id: int) -> void
```

ピア切断時に呼ばれます。

### _on_grenade_network_event

```gdscript
func _on_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int) -> void
```

グレネード投擲をネットワークに送信します。

### _on_grenade_explode_network_event

```gdscript
func _on_grenade_explode_network_event(grenade_id: int, pos: Vector3, is_smoke: bool) -> void
```

グレネード爆発をネットワークに送信します。

## 同期処理

### on_path_confirmed

パス確定時に`sync_controller.send_state_sync()`を呼び出します。

### on_execute_paths

パス実行時に`sync_controller.send_path_execute(false)`を呼び出します。

### on_round_ended

ラウンド終了時、ホストのみ`sync_controller.send_round_state()`を呼び出します。

## 使用例

```gdscript
# GameScreen.setup_multiplayer()から呼ばれる
func setup_multiplayer(net_manager: NetworkManager, map_id: String) -> void:
    _map_id = map_id

    var mp_provider = MultiplayerModeProvider.new()
    mp_provider.setup_network(net_manager)
    _mode_provider = mp_provider

    _initialize_game()
```

## 初期化フロー

```
setup_network(net_manager)
    │
    └── NetworkManager保持、ピアID取得

initialize(game_screen, game_manager)
    │
    ├── _setup_sync_controller()
    │     ├── NetworkBusAdapter作成
    │     └── MultiplayerSyncController作成
    │
    └── _connect_network_events()
          ├── peer_disconnected接続
          ├── message_received接続
          ├── grenade_network_event接続
          └── grenade_explode_network_event接続
```

## 関連クラス

- [GameModeProvider](./GameModeProvider.md)
- [TrainingModeProvider](./TrainingModeProvider.md)
- [NetworkManager](../Network/NetworkManager.md)
- [MultiplayerSyncController](../Network/MultiplayerSyncController.md)
