# MultiplayerGameScreen

**継承:** `Node3D`

マルチプレイヤーゲームのメイン画面クラス。
`GameManager`, `NetworkManager`, `MultiplayerSyncController` などを統括し、ゲームループを実行します。

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `disconnected` | `void` | サーバーから切断された時 |

## プロパティ

| 名前 | 型 | 説明 |
| :--- | :--- | :--- |
| `game_manager` | `GameManager` | ゲームロジックの中核管理クラス |
| `network_manager` | `NetworkManager` | ネットワーク通信管理クラス |
| `sync_controller` | `MultiplayerSyncController` | ゲーム状態の同期コントローラー |
| `environment_setup` | `EnvironmentSetup` | 環境（照明など）設定 |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `setup_with_network(net_manager, map_id)` | `void` | 外部（ロビーなど）から渡されたNetworkManagerを使用してゲームを初期化します。 |
| `get_smoke_area_manager()` | `SmokeAreaManager` | スモーク管理システムを取得します。 |
| `cleanup()` | `void` | ゲーム終了時のクリーンアップ処理を行います。 |

## 機能詳細

### 初期化プロセス
1.  **環境設定:** `EnvironmentSetup` によりライティングなどを設定。
2.  **GameManager:** コアロジックの初期化。
3.  **SyncController:** ネットワーク同期システムの構築。
4.  **マップロード:** 指定されたIDのマップを読み込み。
5.  **UI:** HUD, ラウンドHUDなどのUIレイヤー構築。
6.  **キャラクター:** 参加プレイヤー数に応じてキャラクターを生成・配置。NetworkIDを割り当てて同期可能にします。

### ネットワークイベント処理
*   **グレネード:** 投擲と爆発イベントを `NetworkMessages` を介して同期します。
*   **パス実行:** 移動パスの計画と実行開始を同期します。
*   **ラウンド管理:** ラウンドの開始・終了を同期します。

### カメラ制御
プレイヤーの所属チーム（CT/T）に応じて初期カメラ位置を調整し、`CameraPanController` による操作を提供します。
