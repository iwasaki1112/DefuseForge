# LobbyScreen

**継承:** `Control`

マルチプレイヤーのオートマッチング画面クラス。
画面表示と同時にマッチング開始、2人揃ったら即座にゲーム開始します。

## 定数

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `GAME_SCENE` | `"res://scenes/screens/game.tscn"` | ゲーム画面シーンのパス |
| `MAIN_MENU_SCENE` | `"res://scenes/screens/main_menu.tscn"` | メインメニューシーンのパス |

## 状態列挙体 (LobbyState)

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `MATCHING` | `0` | マッチング中 |
| `IDLE` | `1` | 初期状態/キャンセル後/エラー後 |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `get_network_manager()` | `NetworkManager` | この画面で管理しているNetworkManagerインスタンスを取得します。 |

## 機能詳細

### オートマッチング
`_ready()`で自動的にマッチング開始。`NetworkManager.find_match()`でサーバーのマッチングキューに参加し、2人揃うとサーバーが`MATCH_FOUND`を送信。即座にゲーム画面へ遷移します。

### ネットワーク管理
内部で `NetworkManager` インスタンスを生成・管理します。ゲーム開始時には、このインスタンスを親ノードから切り離して次のシーンに引き渡します。

### UIパネル
- **マッチング中表示:** 「マッチング中...」テキスト（ドットアニメーション付き）
- **キャンセルボタン:** マッチングをキャンセルしてメインメニューに戻る
- **ステータスラベル:** エラーメッセージ表示用

### チーム割り当て
- 先にキューに入ったプレイヤー = Host (peer_id=1) = CT
- 後からキューに入ったプレイヤー = Client (peer_id=2) = T

### フロー
```
MainMenu → [Multiplayer押下] → LobbyScreen._ready()
  → 自動でサーバーに接続 & FIND_MATCH送信
  → 「マッチング中...」表示 + キャンセルボタン
  → サーバーが2人揃ったらMATCH_FOUND通知
  → _on_match_found() → _start_game(map_id) → GameScreen
```
