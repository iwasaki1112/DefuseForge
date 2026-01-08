# Claude Code Rules (Godot開発)

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `SupportRateGame/`
- **言語**: GDScript

## スキル

### プロジェクトスキル
| スキル | 用途 |
|--------|------|
| `/add-weapon` | 武器追加ガイド（Blenderモデル準備→WeaponResource作成→左手IK調整） |
| `/export-character` | BlenderからキャラクターをGLBエクスポート（NLAアニメーション含む）→Godotに配置 |
| `/retarget-animation` | MixamoアニメーションをAuto-Rig Proでリターゲット→NLAトラックにPush Down |
| `/sakurai-review` | 桜井政博氏の哲学に基づくゲーム設計レビュー（リスク/リターン、難易度曲線等） |
| `/difficulty-design` | 難易度設計支援（デコボコ曲線、3分間の法則、救済システム） |
| `/reward-design` | 報酬システム設計（報酬サイクル、数値報酬、コレクション要素） |
| `/game-feel` | ゲームの手触りレビュー（ヒットストップ、攻撃モーション、ジャンプ設計）|

### プラグインスキル
| スキル | 用途 |
|--------|------|
| `/claude-mem:mem-search` | 過去セッションのメモリ検索（「前回どうやった？」等） |
| `/claude-mem:troubleshoot` | claude-memのインストール問題診断・修正 |

## ドキュメント参照
詳細な仕様は以下のドキュメントを参照すること：

| ドキュメント | 内容 |
|------------|------|
| `docs/GAME_DESIGN.md` | ゲーム設計・仕様 |
| `docs/CHARACTER_API.md` | キャラクターAPI |
| `docs/WEAPON_API.md` | 武器システムAPI |
| `docs/BLENDER_ANIMATION.md` | Blenderアニメーション設定 |

## Tool Priority
1. **Godot MCP** (優先) - シーン作成・編集・プロジェクト実行
2. **ファイル操作** (フォールバック) - スクリプト編集・シーンファイル直接編集

## よく使うコマンド
```bash
# Godotエディタを開く
"/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot" --path SupportRateGame --editor

# プロジェクトを実行
"/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot" --path SupportRateGame
```

## iOS実機ビルド
**必ず専用スクリプトを使用すること！**
```bash
./scripts/ios_build.sh --export
```
※ `--export`オプション必須。Godotの`--export-debug`を直接実行しないこと。

## Error handling
- シーンが読み込めない → UIDを確認
- スクリプトエラー → Godotコンソール確認（`get_debug_output`）
- 影が表示されない → マテリアルがPBR（shading_mode=1）か確認
