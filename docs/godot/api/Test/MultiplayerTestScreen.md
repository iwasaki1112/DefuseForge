# MultiplayerTestScreen

**継承:** `Node3D`

マルチプレイヤー同期システムのローカルテスト用シーン。
単一のプロセス内でHostとClientの視点を切り替えながら、同期ロジック（`MultiplayerSyncController`, `LocalNetworkBus`）の動作確認を行うために使用されます。

## 機能

### 視点切り替え
`ViewMode` (HOST / CLIENT) を切り替えることで、操作対象のチームとカメラ位置を変更できます。
*   **HOST:** Counter-Terrorist (CT) チームを操作。
*   **CLIENT:** Terrorist (T) チームを操作。

### 同期テスト
`LocalNetworkBus` を使用して、ネットワーク遅延やパケットロスをシミュレートしつつ、Host-Client間のメッセージ送受信を確認できます。
手動同期ボタン（`Send Sync`）により、任意の状態同期パケットを送信可能です。

## 操作

*   **TABキー:** Host/Client視点の切り替え
*   **Sキー:** 手動同期パケット送信

## 主要コンポーネント

| 名前 | 型 | 説明 |
| :--- | :--- | :--- |
| `network_bus` | `LocalNetworkBus` | ネットワーク通信のシミュレーター |
| `sync_controller` | `MultiplayerSyncController` | 同期ロジック制御 |
| `game_manager` | `GameManager` | ゲームループ管理 |
| `_debug_panel` | `VBoxContainer` | デバッグ情報の表示と操作ボタン |

## 使用方法

1.  `godot/scenes/tests/multiplayer_test.tscn` を実行。
2.  画面左上のボタンまたはTABキーで視点を切り替え。
3.  キャラクターを選択し、パスを描画・実行して同期を確認。
4.  ログパネルで送信されたメッセージタイプを確認。
