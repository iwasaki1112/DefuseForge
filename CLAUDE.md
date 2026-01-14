# Claude Code Rules (Godot開発)

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `DefuseForge/`
- **言語**: GDScript
- **メインシーン**: `scenes/tests/test_animation_viewer.tscn`

## 現在の状態
開発途中。**test_animation_viewer** のみ稼働中。

## ドキュメント（必要時に参照）
`docs/godot/` 配下：
- `character-api.md` - CharacterBase/CharacterAPI（選択、回転、移動、武器、アニメーション、IK、レーザー、視界、FogOfWar、レジストリ）
- `skeleton-modifier-patterns.md` - SkeletonModifier3D、上半身回転、IK実行順序

**重要**: 仕様追加・変更があった場合は `docs/godot/character-api.md` に定義を追記すること。

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
