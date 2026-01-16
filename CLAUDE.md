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
`docs/godot/` 配下：
- `character-registry.md` - CharacterPreset/CharacterRegistry（キャラクター定義、チーム別管理、ファクトリー）
- `mixamo-character.md` - MixamoCharacter API（HP、死亡、チーム管理）
- `strafe-animation-controller.md` - StrafeAnimationController API（8方向ストレイフ、エイム、武器切替、死亡、汎用アクション）

**重要**:
- 実装前に関連ドキュメントを読むこと（特に `mixamo-character.md` と `strafe-animation-controller.md`）
- 仕様追加・変更があった場合は該当ドキュメントに定義を追記すること

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
