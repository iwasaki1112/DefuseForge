# PlayerState

プレイヤー状態管理（Autoload）。プレイヤーが属するチームを管理し、味方/敵の分類機能を提供。
マルチプレイヤー同期のためのプレイヤー状態管理機能も含む。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/systems/player_state.gd` |
| Autoload名 | `PlayerState` |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `team_changed` | `new_team: GameCharacter.Team` | 自身のチーム変更時 |
| `player_state_changed` | `peer_id: int` | 任意のプレイヤーの状態（準備完了など）が変更された時 |

## Public API

### Team Management

#### `get_player_team() -> GameCharacter.Team`
ローカルプレイヤーの現在のチームを取得。

#### `set_player_team(team: GameCharacter.Team) -> void`
ローカルプレイヤーのチームを設定。変更があれば `team_changed` シグナルを発火。

#### `get_team_name(team: GameCharacter.Team = current) -> String`
チーム名を文字列で取得（"CT", "T", "NONE"）。

### Character Classification

#### `is_friendly(character: Node) -> bool`
キャラクターがプレイヤーの味方かどうか判定。

#### `is_enemy(character: Node) -> bool`
キャラクターがプレイヤーの敵かどうか判定。

#### `filter_friendlies(characters: Array) -> Array[Node]`
配列から味方キャラクターのみを抽出。

#### `filter_enemies(characters: Array) -> Array[Node]`
配列から敵キャラクターのみを抽出。

### Multiplayer State Management

#### `set_local_peer_id(peer_id: int) -> void`
ローカルプレイヤーのピアIDを設定。

#### `register_player(peer_id: int, player_name: String = "") -> SyncState.PlayerStateData`
プレイヤーをセッションに登録する。

#### `unregister_player(peer_id: int) -> void`
プレイヤーをセッションから削除する。

#### `get_player_state(peer_id: int) -> SyncState.PlayerStateData`
指定したピアIDのプレイヤー状態データを取得。

#### `get_all_player_states() -> Dictionary`
全プレイヤーの状態データを取得。

#### `are_all_players_ready() -> bool`
全プレイヤーが準備完了状態（`is_ready`）か確認。

#### `reset_all_players() -> void`
全プレイヤーの状態（勝敗数など）をリセット。

#### `clear_multiplayer_session() -> void`
マルチプレイヤーセッション情報をクリア（切断時など）。

### Serialization

#### `to_dict() -> Dictionary`
ローカルプレイヤー状態を辞書形式に変換。

#### `from_dict(data: Dictionary) -> void`
辞書形式からローカルプレイヤー状態を復元。

#### `to_player_state_data() -> SyncState.PlayerStateData`
ローカルプレイヤー状態をデータオブジェクトに変換。

#### `from_player_state_data(data: SyncState.PlayerStateData) -> void`
データオブジェクトからローカルプレイヤー状態を更新。