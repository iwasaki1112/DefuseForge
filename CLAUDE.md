# Claude Code Rules (Godot開発)

## Goal
Godot MCPを優先的に使用してGodotを操作する。Godot MCPで対応できない場合のみファイル操作ツールを使用する。

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `SupportRateGame/`
- **言語**: GDScript

## ゲーム概要
タクティカルシューター（CS1.6 + Door Kickers 2スタイル）
- トップダウンビューカメラ
- パス描画による移動指示（Door Kickers 2スタイル）
- ラウンド制（MR15）
- 購入フェーズ + プレイフェーズ

## プロジェクト構造
```
SupportRateGame/
├── project.godot          # プロジェクト設定
├── scenes/
│   ├── title.tscn         # タイトルシーン
│   ├── game.tscn          # ゲームシーン（dust3マップ使用）
│   ├── player.tscn        # プレイヤーシーン
│   └── enemy.tscn         # 敵シーン
├── scripts/
│   ├── autoload/
│   │   ├── game_manager.gd    # ゲーム管理（Autoload）- ラウンド・経済システム
│   │   └── input_manager.gd   # 入力管理（Autoload）- タッチ/マウス入力統合
│   ├── characters/
│   │   ├── character_base.gd  # キャラクター基底クラス（移動・アニメーション）
│   │   ├── player.gd          # プレイヤークラス
│   │   └── enemy.gd           # 敵クラス（AI）
│   ├── systems/
│   │   ├── camera_controller.gd  # カメラ制御（ズーム・パン・追従）
│   │   └── path/
│   │       ├── path_manager.gd   # パス管理
│   │       ├── path_renderer.gd  # パス描画（3Dメッシュ）
│   │       └── path_analyzer.gd  # パス解析（直線判定・走り/歩き）
│   ├── utils/
│   │   └── character_setup.gd # キャラクター設定ユーティリティ
│   ├── game_scene.gd      # ゲームシーン管理
│   ├── game_ui.gd         # UI管理（タイマー・スコア・デバッグ情報）
│   ├── title_screen.gd    # タイトル画面
│   └── map_collision_generator.gd  # マップメッシュからコリジョン自動生成
├── resources/
│   ├── maps/
│   │   └── dust3/         # PBRマップ（動的シャドウ対応）
│   └── materials/         # マテリアル
├── assets/
│   └── characters/        # キャラクターモデル・アニメーション
└── builds/
    └── ios/               # iOSビルド出力
```

## アーキテクチャ

### Autoload（シングルトン）
- **GameManager**: ゲーム状態、ラウンド、経済システム管理
- **InputManager**: 全入力を一元管理、シグナルで各システムに通知

### クラス階層
```
CharacterBase (character_base.gd)
├── Player (player.gd) - プレイヤー固有機能
└── Enemy (enemy.gd) - AI敵キャラクター
```

### システム
- **CameraController**: カメラ制御（InputManagerからズーム/パン信号を受信）
- **PathManager**: パス描画管理（InputManagerから描画信号を受信）
  - PathRenderer: 3Dメッシュ描画
  - PathAnalyzer: 直線判定、走り/歩き判定

## 技術詳細

### マップ
- **dust3**: PBRマテリアル使用（動的シャドウ対応）
- コリジョンは`map_collision_generator.gd`で自動生成（collision_layer=2）
- マップ座標オフセット: `(4, -1009, -1214)`

### シャドウ設定（DirectionalLight3D）
```
shadow_enabled = true
shadow_bias = 0.05
shadow_normal_bias = 2.0
directional_shadow_max_distance = 100.0
directional_shadow_mode = 2 (PSSM 4 splits)
directional_shadow_blend_splits = true
```

### プレイヤー/敵
- CharacterBody3D + 重力ベースの地形追従
- パス追従移動（waypoints配列）
- アニメーション: idle, walking, running（FBXから読み込み）
- 敵はAIStateによる状態管理（IDLE, PATROL, CHASE, ATTACK, COVER）

### 入力操作
- **1本指ドラッグ**: パス描画（移動指示）
- **2本指ピンチ**: ズーム
- **2本指ドラッグ**: カメラパン
- **マウスホイール**: ズーム（PC）

## Tool Priority
1. **Godot MCP** (優先) - Godot操作
   - シーン作成・編集
   - ノード追加
   - プロジェクト実行

2. **ファイル操作** (フォールバック) - Godot MCPで対応できない場合
   - スクリプト編集
   - シーンファイル直接編集

## よく使うコマンド
```bash
# Godotエディタを開く
"/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot" --path SupportRateGame --editor

# プロジェクトを実行
"/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot" --path SupportRateGame
```

## iOS実機ビルド（重要）
**必ず専用スクリプトを使用すること！** 手動でGodotエクスポートやXcode操作をしない。

```bash
# iOS実機ビルド＆インストール（推奨）
./scripts/ios_build.sh

# Godotエクスポートも含める場合
./scripts/ios_build.sh --export
```

### スクリプトが行うこと
1. 署名設定を自動修正（Automatic signing, Team ID設定）
2. 実機の接続確認
3. Xcodeビルド
4. 実機へのインストール

### 注意
- Godotの`--export-debug`を直接実行すると署名設定が壊れる
- 必ず`ios_build.sh`経由でビルドすること

## 開発フロー
1. スクリプトファイルはファイル操作ツールで編集
2. シーンファイルはGodot MCPまたはファイル操作ツールで編集
3. テスト実行はGodot MCPの`run_project`を使用
4. **iOS実機ビルドは`./scripts/ios_build.sh`を使用**

## Error handling
- シーンが読み込めない → UIDを確認
- スクリプトエラー → Godotコンソールを確認（`get_debug_output`）
- ノードが見つからない → シーンツリーを確認
- 影が表示されない → マテリアルがPBR（shading_mode=1）か確認
- 影がチラつく → shadow_bias, shadow_normal_biasを調整
