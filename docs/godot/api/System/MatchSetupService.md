# MatchSetupService

## 概要

マッチ開始時のセットアップ（チーム決定、マップロード、キャラクター生成、カメラ調整）を担当するクラス。
`GameManager`から委譲されて動作する。

## クラス情報

- **継承**: `RefCounted`
- **ファイル**: `scripts/screens/match_setup_service.gd`

## メソッド

### `setup(manager: GameManager, cam: Camera3D) -> void`
依存オブジェクト（GameManager, Camera3D）を設定する。

### `determine_player_team() -> void`
プレイヤーのチームをランダムに決定し、`PlayerState`に設定する。
（現在はCT/Tのどちらか）

### `load_selected_map(map_id: String) -> bool`
`MapRegistry`からマッププリセットを取得し、`GameManager.load_map()`を通じてマップをロードする。

### `spawn_characters() -> void`
ロードされたマップのプリセット情報（`spawn_points_ct`, `spawn_rotations_ct`など）に基づいて、両チームのキャラクターを生成する。

*   **CT側**: Alpha, Bravo
*   **T側**: Ares, Brim

生成時に初期位置、回転（向き）、およびHUD用のマーカー名（"alpha"等）を設定する。
生成されたキャラクターは`GameManager`のキャラクター親ノードに追加され、管理下に登録される。

### `setup_camera_for_player() -> void`
プレイヤーのチームに属するキャラクターの初期位置に合わせて、カメラを適切な位置に移動させる。

## 内部動作

### キャラクター生成プロセス
1.  現在のマッププリセットを取得。
2.  `CharacterRegistry`からキャラクタープリセットを取得。
3.  プリセットのスポーン位置・回転情報を使用してキャラクターインスタンス化。
4.  `character.marker_name`を設定（HUD連携用）。
5.  `GameManager.register_character()`で登録。
6.  `IdleCharacterManager`にリストを更新通知。

## 関連クラス

- [GameManager](GameManager.md)
- [MapManager](MapManager.md)
- [CharacterRegistry](../Registry/CharacterRegistry.md)
- [PlayerState](PlayerState.md)