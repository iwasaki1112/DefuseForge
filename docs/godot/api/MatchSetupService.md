# MatchSetupService

## 概要

マッチ開始時のセットアップ（チーム決定、マップロード、キャラクター生成、カメラ調整）を担当する。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/screens/match_setup_service.gd`

## メソッド

### `setup(manager: GameManager, cam: Camera3D) -> void`
使用するGameManagerとカメラ参照を設定する。

### `determine_player_team() -> void`
プレイヤーチームをランダムに決定する。

### `load_selected_map(map_id: String) -> bool`
選択されたマップをロードする。

### `spawn_characters() -> void`
マッププリセットに基づいてCT/Tのキャラクターを生成する。

内部で`GameManager.get_current_map_preset()`を使用し、キャラクターは`GameManager.get_character_parent()`配下に追加される。

### `setup_camera_for_player() -> void`
プレイヤーキャラクターに合わせてカメラ位置を調整する。

## 関連クラス

- [GameScreen](GameScreen.md)
- [GameManager](GameManager.md)
- [MapManager](MapManager.md)

## APIリファレンス

### シグナル
なし

### メソッド
- `setup(manager: GameManager, cam: Camera3D) -> void`
- `determine_player_team() -> void`
- `load_selected_map(map_id: String) -> bool`
- `spawn_characters() -> void`
- `setup_camera_for_player() -> void`
