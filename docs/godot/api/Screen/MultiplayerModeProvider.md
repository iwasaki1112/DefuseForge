# MultiplayerModeProvider

Multiplayerモード用のプロバイダー。ネットワーク関連の処理をすべて内包します。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | GameModeProvider |
| クラス名 | MultiplayerModeProvider |
| パス | `scripts/screens/multiplayer_mode_provider.gd` |

## 概要

MultiplayerModeProviderはネットワーク同期に必要なすべての処理を担当します：

- NetworkManagerとSyncControllerの保持
- ネットワークイベントのハンドリング（ドアキック/開け、グレネード、ダメージ）
- キャラクタースポーン（peer_idソートで確定的network_id割り当て）
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

### determine_player_team

```gdscript
func determine_player_team() -> void
```

ネットワーク情報からプレイヤーのチームを決定します。`network_manager.get_players()` から自身のpeer_idに対応するteam情報を取得し、`PlayerState.set_player_team()` で設定します。

### spawn_characters

```gdscript
func spawn_characters(game_screen: Node, game_manager: GameManager) -> bool
```

マルチプレイヤー用キャラクタースポーン。peer_idでソートして確定的な順序でスポーンし、ホストとクライアントで同じnetwork_idを割り当てます。CT側は`alpha`プリセット、T側は`ares`プリセットを使用。

### register_character

```gdscript
func register_character(game_manager: GameManager, character: GameCharacter, network_id: int) -> void
```

キャラクターをネットワーク対応で登録します。チームに対応するowner peer_idを自動取得して `register_character_with_network()` を呼び出します。

### send_animation_event

```gdscript
func send_animation_event(character_id: int, anim_event: int, extra_data: Dictionary = {}) -> void
```

アニメーションイベントをネットワークに送信します。SyncControllerに委譲。

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

### can_start_round

```gdscript
func can_start_round() -> bool
```

ホストのみ `true` を返します。

### on_round_ended

```gdscript
func on_round_ended(_winner: int, _reason: int) -> void
```

ラウンド終了時、ホストのみ `sync_controller.send_round_state()` を呼び出します。

### cleanup

```gdscript
func cleanup() -> void
```

シグナル切断とWebSocket切断を実行します。GameScreen終了時に呼ばれます。

## ネットワークイベント

### _on_peer_disconnected

```gdscript
func _on_peer_disconnected(peer_id: int) -> void
```

ピア切断時に呼ばれます。

### _on_network_message

```gdscript
func _on_network_message(_from_peer: int, _msg_type: int, _data: Dictionary) -> void
```

ネットワークメッセージ受信時に呼ばれます。sync_controllerが処理。

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

### _on_door_kick_network_event

```gdscript
func _on_door_kick_network_event(door_id: int, character_network_id: int) -> void
```

ドアキックイベントをネットワークに送信します。

### _on_door_open_network_event

```gdscript
func _on_door_open_network_event(door_id: int, character_network_id: int) -> void
```

ドア開けイベント（静か）をネットワークに送信します。

### _on_damage_network_event

```gdscript
func _on_damage_network_event(attacker_id: int, target_id: int, damage: float, is_headshot: bool) -> void
```

ダメージイベントをネットワークに送信します。

## 人質スポーン

人質のスポーンはMultiplayerModeProviderではなく、GameScreen側で共通処理として行われます。
`spawn_characters()`がCT/Tプレイヤーのスポーン後に`true`を返した後、
GameScreenの`_spawn_hostages()`がマッププリセットに基づいて人質を配置します。

人質はネットワーク同期の対象外で、各クライアントがローカルに同一の位置にスポーンします。

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
          ├── grenade_explode_network_event接続
          ├── door_kick_network_event接続
          ├── door_open_network_event接続
          └── damage_network_event接続
```

## 関連クラス

- [GameModeProvider](./GameModeProvider.md)
- [TrainingModeProvider](./TrainingModeProvider.md)
- [NetworkManager](../Network/NetworkManager.md)
- [MultiplayerSyncController](../Network/MultiplayerSyncController.md)
