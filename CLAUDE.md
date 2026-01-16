# Claude Code Rules (Godot開発)

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `DefuseForge/`
- **言語**: GDScript

## 現在の状態
開発途中。Mixamo専用のキャラクターシステム。

テストシーン：
- `scenes/tests/test_simple_mixamo.tscn` - Mixamoキャラクター＋MixamoCharacter＋StrafeAnimationController確認用

## ドキュメント
`docs/godot/api`　配下にこのプロジェクトで実装済みの機能ドキュメントがあります。

## コマンド
```bash
# エディタ起動
"/Applications/Godot.app/Contents/MacOS/Godot" --path DefuseForge --editor

# プロジェクト実行
"/Applications/Godot.app/Contents/MacOS/Godot" --path DefuseForge
```

## Tool Priority
1. **Godot MCP** (優先) - シーン作成・編集・実行
2. **GDScript LSP** (`gdscript-lsp`) - シンボル検索、コード解析
3. **ファイル操作** (フォールバック) - スクリプト編集
