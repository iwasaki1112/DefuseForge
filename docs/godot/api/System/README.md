# System API

| クラス | 概要 |
|--------|------|
| [FogOfWarSystem](FogOfWarSystem.md) | SubViewport+シェーダーでFog of Warを描画 |
| [PlayerState](PlayerState.md) | プレイヤーチーム管理＋味方/敵分類＋お金管理（Autoload） |
| [EnemyVisibilitySystem](EnemyVisibilitySystem.md) | 味方視界に基づく敵キャラクター可視性制御 |
| [CharacterColorManager](CharacterColorManager.md) | キャラクター個別色管理（Autoload） |
| [CharacterSelectionManager](CharacterSelectionManager.md) | 複数キャラクター選択＋アウトライン表示管理 |
| [CharacterSetupService](CharacterSetupService.md) | キャラクター初期セットアップを担当 |
| [IdleCharacterManager](IdleCharacterManager.md) | アイドル中キャラクターの状態更新管理 |
| [VisionService](VisionService.md) | 視界関連の更新・同期サービス |
| [MapManager](MapManager.md) | マップライフサイクル管理・クリーンアップ |
| [OccluderManager](OccluderManager.md) | 3DマップからFoW用2Dオクルーダーを生成・管理 |
| [EnvironmentSetup](EnvironmentSetup.md) | 環境設定コンポーネント（ライティング・レンダリング品質・ポストプロセス） |
| [GameManager](GameManager.md) | コアゲームシステム初期化・更新の一元管理 |
| [GameSystemFactory](GameSystemFactory.md) | ゲームシステム生成ファクトリ |
| [SettingsManager](SettingsManager.md) | 設定管理（プレイヤー名保存・選択マップ保持）（Autoload） |
| [RoundManager](RoundManager.md) | ラウンド状態管理・タイマー・生存者数追跡・勝敗判定 |
| [SmokeAreaManager](SmokeAreaManager.md) | スモークエリアのグローバル管理・視線判定API |
| [SignalBus](SignalBus.md) | グローバルシグナルバス・イベント通知一元管理（Autoload） |
