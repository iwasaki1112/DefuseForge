# System API

| クラス | 概要 |
|--------|------|
| [FogOfWarSystem](FogOfWarSystem.md) | SubViewport+シェーダーでFog of Warを描画 |
| [PlayerState](PlayerState.md) | プレイヤーチーム管理＋味方/敵分類＋お金管理（Autoload） |
| [EnemyVisibilitySystem](EnemyVisibilitySystem.md) | 味方視界に基づく敵キャラクター可視性制御 |
| [CharacterColorManager](CharacterColorManager.md) | キャラクター個別色管理（Autoload） |
| [CharacterSelectionManager](CharacterSelectionManager.md) | 複数キャラクター選択＋アウトライン表示管理 |
| [CharacterSetupService](CharacterSetupService.md) | キャラクター初期セットアップを担当 |
| [PathExecutionManager](PathExecutionManager.md) | パス確定・実行・pending_paths管理 |
| [IdleCharacterManager](IdleCharacterManager.md) | アイドル中キャラクターの状態更新管理 |
| [PathModeController](PathModeController.md) | パスモード状態管理（開始・確定・キャンセル） |
| [PathService](PathService.md) | パス描画・編集・実行の調整サービス |
| [VisionService](VisionService.md) | 視界関連の更新・同期サービス |
| [MapManager](MapManager.md) | マップライフサイクル管理・クリーンアップ |
| [EnvironmentSetup](EnvironmentSetup.md) | 環境設定コンポーネント（ライティング・レンダリング品質・ポストプロセス） |
| [GameManager](GameManager.md) | コアゲームシステム初期化・更新の一元管理 |
| [MatchSetupService](MatchSetupService.md) | マッチ開始時のセットアップを担当 |
| [SettingsManager](SettingsManager.md) | 設定管理（プレイヤー名保存・選択マップ保持）（Autoload） |
| [InputController](InputController.md) | ゲーム画面の入力処理コントローラー |
| [RoundManager](RoundManager.md) | ラウンド状態管理・タイマー・生存者数追跡・勝敗判定 |
| [TimelineManager](TimelineManager.md) | タイムライン更新の遅延・統合管理 |
| [SmokeAreaManager](SmokeAreaManager.md) | スモークエリアのグローバル管理・視線判定API |
