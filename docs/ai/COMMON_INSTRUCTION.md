# Rules (Godot開発)

## 設定
- **言語**: 日本語で応答すること

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `godot/`
- **言語**: GDScript

## プロジェクト概要
タクティカルシューター（モバイルゲーム）。キャラクターにパスを描いて移動・戦闘させる。

- **入力**: タップ/クリックのみ（モバイル前提）
- **パフォーマンス優先**: モバイル向けに最適化すること

## リポジトリ構成（概要）
- **`godot/`**: ゲーム本体（Godotプロジェクト）
- **`docs/`**: ドキュメント群（Godot仕様・API・AI向け指示）
- **`blender/`**: マップ/アセット制作関連
- **`tools/`**: 開発支援ツール類
- **`scripts/`**: 自動化・補助スクリプト
- **`docker-compose.yml`**: 開発/検証用の構成
- **`agents.md` / `CLAUDE.md` / `GEMINI.md`**: AIエージェント向けの指示

## 主要エントリポイント（最初に見る場所）
- **画面フローの全体像**: `docs/godot/game-flow.md`
- **最初に表示される画面**: `scenes/screens/main_menu.tscn` / `scripts/screens/main_menu_screen.gd`
- **マップ選択画面**: `scenes/screens/map_selection.tscn` / `scripts/screens/map_selection_screen.gd`
- **設定画面**: `scenes/screens/option.tscn` / `scripts/screens/option_screen.gd`
- **ゲーム本編画面**: `scenes/screens/game.tscn` / `scripts/screens/game_screen.gd`

## game-flowの読み方（最短導線）
1. **画面遷移図**: 起動からゲーム開始までの流れを把握
2. **GameScreen**: 初期化処理と主要システムの関係を把握
3. **データフロー**: MapSelection→GameScreenのデータ伝播を確認
4. **登録済みマップ**: マップ追加・構成の流れを確認

## 現在の状態
開発途中。Mixamo専用のキャラクターシステム。マップはBlenderで作成しGLTFインポート。

## ドキュメント

### ゲームフロー
**`docs/godot/game-flow.md`** - 画面遷移とシステムの流れを記載。

### 実装時の参照（必須）
**実装前に必ず `docs/godot/api/` 配下のAPIドキュメントを確認すること。**

既存クラスの仕様・使用例・内部動作が記載されており、実装の整合性を保つために重要。

### クラス別APIドキュメント
| カテゴリ | クラス | 概要 |
|---------|--------|------|
| Animation | CharacterAnimationController | 8方向ストレイフ・リコイル・デスを統合制御 |
| Animation | RecoilModifier | SkeletonModifier3Dで発射時の反動を適用 |
| Animation | LeanModifier | SkeletonModifier3Dで上半身リーンを適用 |
| Character | GameCharacter | HP・チーム・死亡処理を管理するCharacterBody3D |
| Character | VisionComponent | シャドウキャスト法でFoW用の可視ポリゴンを計算 |
| Character | CombatAwarenessComponent | 敵検出・自動照準を管理するコンポーネント |
| Character | PathFollowingController | パス追従＋視線ポイント＋Run区間＋スタック検出を行う再利用可能コントローラー |
| Character | CharacterRotationController | 視線方向変更のスムーズな回転制御 |
| Effect | PathDrawer | マウスドラッグでパス描画＋視線ポイント＋Runマーカー設定 |
| Effect | PathLineMesh | 破線＋終点ドーナツ円のパスメッシュ描画 |
| Effect | RunMarker | Run区間の開始/終点を示すマーカー |
| Effect | VisionMarker | 円＋矢印で視線方向を示すマーカー |
| Effect | ClearMarker | Clearポイント（視線・Runリセット）を示すマーカー |
| Effect | CharacterSelectedMarker | 選択中キャラクター足元の回転マーカー |
| Util | PathSmoother | RDP間引き＋Catmull-Rom補間でパススムージング |
| Registry | CharacterRegistry | プリセット管理＋キャラクター生成（Autoload） |
| Registry | WeaponRegistry | 武器プリセット管理（Autoload） |
| Registry | MapRegistry | マッププリセット管理＋マップインスタンス化（Autoload） |
| Resource | CharacterPreset | キャラクター定義（ID・チーム・モデル・ステータス） |
| Resource | WeaponPreset | 武器定義（ID・カテゴリー・ダメージ・リコイル） |
| Resource | MapPreset | マップ定義（ID・シーン・サイズ・スポーン位置） |
| Resource | EnvironmentPreset | 環境プリセット定義（ライティング・影・レンダリング品質・ポストプロセス） |
| Resource | ContextMenuItem | コンテキストメニュー項目定義 |
| System | FogOfWarSystem | SubViewport+シェーダーでFog of Warを描画 |
| System | PlayerState | プレイヤーチーム管理＋味方/敵分類＋お金管理（Autoload） |
| System | EnemyVisibilitySystem | 味方視界に基づく敵キャラクター可視性制御 |
| System | CharacterColorManager | キャラクター個別色管理（Autoload） |
| System | CharacterSelectionManager | 複数キャラクター選択＋アウトライン表示管理 |
| System | PathExecutionManager | パス確定・実行・pending_paths管理 |
| System | IdleCharacterManager | アイドル中キャラクターの状態更新管理 |
| System | PathModeController | パスモード状態管理（開始・確定・キャンセル） |
| System | MapManager | マップライフサイクル管理・クリーンアップ |
| System | EnvironmentSetup | 環境設定コンポーネント（ライティング・レンダリング品質・ポストプロセス） |
| System | GameManager | コアゲームシステム初期化・更新の一元管理 |
| System | SettingsManager | 設定管理（プレイヤー名保存・選択マップ保持）（Autoload） |
| Screen | MainMenuScreen | メインメニュー画面 |
| Screen | MapSelectionScreen | マップ選択画面 |
| Screen | OptionScreen | オプション設定画面 |
| Screen | GameScreen | ゲームプレイ画面（マップロード・キャラクタースポーン） |
| UI | ContextMenuComponent | タップ時のコンテキストメニューUI |
| UI | CharacterLabelManager | 味方キャラクターの頭上ラベル（A, B, C...）管理 |
| UI | MarkerEditPanel | マルチキャラクター対応マーカー編集パネル |
| UI | WeaponShopModal | 武器購入モーダル（BUYメニュー） |

詳細は `docs/godot/api/<クラス名>.md` を参照。

### 実装後のドキュメント更新（必須）
**実装が完了したら、必ず関連するAPIドキュメントを更新すること。**

- 新規クラス作成時: `docs/godot/api/<クラス名>.md` を新規作成
- 既存クラス変更時: 対応するドキュメントを更新
- docs/ai/COMMON_INSTRUCTION.mdのクラス一覧も必要に応じて更新

## Tool Priority
1. **Godot MCP** (優先) - シーン作成・編集・実行
2. **GDScript LSP** (`gdscript-lsp`) - シンボル検索、コード解析
3. **ファイル操作** (フォールバック) - スクリプト編集
