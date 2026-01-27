# Network API

| クラス | 概要 |
|--------|------|
| [NetworkConstants](NetworkConstants.md) | ネットワーク定数定義（メッセージタイプ・同期設定・タイムアウト） |
| [NetworkMessages](NetworkMessages.md) | ネットワーク同期用メッセージ型（PathConfirm・RoundState・CharacterState・GameEvent） |
| [SyncState](SyncState.md) | 同期状態クラス（GameStateSnapshot・PlayerStateData・CharacterSnapshot） |
| [NetworkSerializer](NetworkSerializer.md) | シリアライズユーティリティ（Vector3圧縮・パスメッセージ・差分圧縮） |
| [LocalNetworkBus](LocalNetworkBus.md) | ローカルネットワークシミュレーター（遅延・パケットロス対応） |
| [MultiplayerSyncController](MultiplayerSyncController.md) | GameManagerとNetworkBus間の同期処理管理 |
| [NetworkBusAdapter](NetworkBusAdapter.md) | NetworkManagerをLocalNetworkBus互換にするアダプタ |
| [NetworkManager](NetworkManager.md) | ENetによるマルチプレイヤー接続・プレイヤー管理 |
