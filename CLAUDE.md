# Claude Code Rules (Godot開発)

## Goal
Godot MCPを優先的に使用してGodotを操作する。Godot MCPで対応できない場合のみファイル操作ツールを使用する。

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `SupportRateGame/`
- **言語**: GDScript

## ゲーム概要
「支持率アップゲーム」- 60秒間でコインを集めて支持率を上げるゲーム
- TPSスタイルのキャラクター操作
- コイン1個につき支持率3%アップ（基本30%から開始）
- 制限時間60秒

## プロジェクト構造
```
SupportRateGame/
├── project.godot          # プロジェクト設定
├── scenes/
│   ├── title.tscn         # タイトルシーン
│   ├── game.tscn          # ゲームシーン
│   ├── player.tscn        # プレイヤーシーン
│   └── coin.tscn          # コインシーン
├── scripts/
│   ├── game_manager.gd    # ゲーム管理（Autoload）
│   ├── game_scene.gd      # ゲームシーン管理
│   ├── game_ui.gd         # UI管理
│   ├── player.gd          # プレイヤー操作
│   ├── coin.gd            # コイン挙動
│   ├── coin_spawner.gd    # コイン配置
│   └── title_screen.gd    # タイトル画面
└── resources/             # リソースファイル
```

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

## 開発フロー
1. スクリプトファイルはファイル操作ツールで編集
2. シーンファイルはGodot MCPまたはファイル操作ツールで編集
3. テスト実行はGodot MCPの`run_project`を使用

## Error handling
- シーンが読み込めない → UIDを確認
- スクリプトエラー → Godotコンソールを確認
- ノードが見つからない → シーンツリーを確認
