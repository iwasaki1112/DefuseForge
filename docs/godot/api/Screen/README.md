# Screen API

ゲーム画面とモードプロバイダーのAPIドキュメント。

## 概要

ゲーム画面はProviderパターンを採用し、TrainingモードとMultiplayerモードの共通処理を統合しています。

## アーキテクチャ

```
GameScreen (統合されたゲーム画面)
    │
    └── GameModeProvider (モード抽象化)
          ├── TrainingModeProvider (シングルプレイヤー)
          └── MultiplayerModeProvider (マルチプレイヤー)
```

## クラス一覧

| クラス | 説明 |
|--------|------|
| [GameScreen](./GameScreen.md) | 統合されたゲーム画面 |
| [GameHUD](./GameHUD.md) | ゲーム画面のUIパネル（タイマー、マーカー等） |
| [GameModeProvider](./GameModeProvider.md) | モードプロバイダー基底クラス |
| [TrainingModeProvider](./TrainingModeProvider.md) | Trainingモード用プロバイダー |
| [MultiplayerModeProvider](./MultiplayerModeProvider.md) | Multiplayerモード用プロバイダー |
| [LobbyScreen](./LobbyScreen.md) | ルームリスト表示・参加UI |

## 設計思想

### Providerパターンの採用理由

- **コード重複の排除**: 共通処理をGameScreenに集約
- **責務の分離**: モード固有処理をProviderに分離
- **拡張性**: 新モード追加時はProviderを追加するだけ

### モード切り替えの仕組み

```gdscript
# Trainingモード（デフォルト）
func _ready():
    _mode_provider = TrainingModeProvider.new()
    _initialize_game()

# Multiplayerモード
func setup_multiplayer(net_manager: NetworkManager, map_id: String):
    var mp_provider = MultiplayerModeProvider.new()
    mp_provider.setup_network(net_manager)
    _mode_provider = mp_provider
    _initialize_game()
```

## 関連ドキュメント

- [GameManager](../System/GameManager.md) - ゲームコアシステム
- [NetworkManager](../Network/NetworkManager.md) - ネットワーク管理
