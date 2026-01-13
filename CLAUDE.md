# Claude Code Rules (Godot開発)

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `DefuseForge/`
- **言語**: GDScript
- **メインシーン**: `scenes/tests/test_animation_viewer.tscn`

## 現在の状態
開発途中。**test_animation_viewer** のみ稼働中。

## スキル

### プロジェクトスキル
| スキル | 用途 |
|--------|------|
| `/add-weapon` | 武器追加ガイド |
| `/export-character` | BlenderからGLBエクスポート→Godot配置 |
| `/organize-arp-collection` | ARP Rig&Bind後のコレクション整理 |
| `/retarget-animation` | 外部アニメーションのリターゲット |
| `/sakurai-review` | 桜井政博氏の哲学に基づくゲーム設計レビュー |
| `/difficulty-design` | 難易度設計支援 |
| `/reward-design` | 報酬システム設計 |
| `/game-feel` | ゲームの手触りレビュー |

### プラグインスキル
| スキル | 用途 |
|--------|------|
| `/claude-mem:mem-search` | 過去セッションのメモリ検索 |
| `/claude-mem:troubleshoot` | claude-mem問題診断 |

## ドキュメント（必要時に参照）
`docs/godot/` 配下：
- `character-api.md` - CharacterAPI（アニメーション、モデル切替、IK、レーザー）
- `character-setup.md` - キャラクター追加手順
- `project-structure.md` - プロジェクト構造
- `skeleton-modifier-patterns.md` - SkeletonModifier3D、上半身回転、IK実行順序

## コマンド
```bash
# エディタ起動
"/Applications/Godot.app/Contents/MacOS/Godot" --path DefuseForge --editor

# プロジェクト実行
"/Applications/Godot.app/Contents/MacOS/Godot" --path DefuseForge
```

## Tool Priority
1. **Godot MCP** (優先) - シーン作成・編集・実行
2. **ファイル操作** (フォールバック) - スクリプト編集
