# Network API

| クラス | 概要 |
|--------|------|
| [NetworkConstants](NetworkConstants.md) | ネットワーク定数定義（メッセージタイプ・同期設定・タイムアウト） |
| [NetworkMessages](NetworkMessages.md) | ネットワーク同期用メッセージ型（RoundState・CharacterState・GameEvent） |
| [LocalNetworkBus](LocalNetworkBus.md) | ローカルネットワークシミュレーター（遅延・パケットロス対応） |
| [NetworkBusAdapter](NetworkBusAdapter.md) | NetworkManagerをLocalNetworkBus互換にするアダプタ |
| [SyncState](SyncState.md) | ゲーム状態スナップショット・同期データ管理 |
| [MultiplayerSyncController](MultiplayerSyncController.md) | マルチプレイヤー同期コントローラー |
| [NetworkSerializer](NetworkSerializer.md) | ネットワークメッセージのシリアライズ・デシリアライズ |
| [NetworkManager](NetworkManager.md) | WebSocketリレーサーバー経由のマルチプレイ接続・ルーム管理 |
