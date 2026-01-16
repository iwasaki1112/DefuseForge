# Claude Code Rules (Godot開発)

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `DefuseForge/`
- **言語**: GDScript

## 現在の状態
開発途中。Mixamo専用のキャラクターシステム。

テストシーン：
- `scenes/tests/test_character.tscn` - 複数キャラクターのパス移動・視線設定・同時実行テスト用
- `scenes/tests/test_simple_mixamo.tscn` - Mixamoキャラクター＋CharacterAnimationController確認用

## ドキュメント

### 実装時の参照（必須）
**実装前に必ず `docs/godot/api/` 配下のAPIドキュメントを確認すること。**

既存クラスの仕様・使用例・内部動作が記載されており、実装の整合性を保つために重要。

### クラス別APIドキュメント
| カテゴリ | クラス | 概要 |
|---------|--------|------|
| Animation | CharacterAnimationController | 8方向ストレイフ・エイム・リコイル・デスを統合制御 |
| Animation | RecoilModifier | SkeletonModifier3Dで発射時の反動を適用 |
| Character | GameCharacter | HP・チーム・死亡処理を管理するCharacterBody3D |
| Character | VisionComponent | シャドウキャスト法でFoW用の可視ポリゴンを計算 |
| Character | CombatAwarenessComponent | 敵検出・自動照準を管理するコンポーネント |
| Character | PathFollowingController | パス追従＋視線ポイント＋スタック検出を行う再利用可能コントローラー |
| Character | CharacterRotationController | 視線方向変更のスムーズな回転制御 |
| Effect | PathDrawer | マウスドラッグでパス描画＋視線ポイント設定 |
| Effect | PathLineMesh | 破線＋終点ドーナツ円のパスメッシュ描画 |
| Effect | VisionMarker | 円＋矢印で視線方向を示すマーカー |
| Registry | CharacterRegistry | プリセット管理＋キャラクター生成（Autoload） |
| Resource | CharacterPreset | キャラクター定義（ID・チーム・モデル・ステータス） |
| Resource | ContextMenuItem | コンテキストメニュー項目定義 |
| System | FogOfWarSystem | SubViewport+シェーダーでFog of Warを描画 |
| System | PlayerState | プレイヤーチーム管理＋味方/敵分類（Autoload） |
| System | EnemyVisibilitySystem | 味方視界に基づく敵キャラクター可視性制御 |
| UI | ContextMenuComponent | タップ時のコンテキストメニューUI |
| Test | TestCharacterSelector | キャラクター選択・パス移動・FoWのテストシーン |

詳細は `docs/godot/api/<クラス名>.md` を参照。

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
