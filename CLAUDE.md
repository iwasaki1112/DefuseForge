# Claude Code Rules (Godot開発)

## Claude設定
- **言語**: 日本語で応答すること

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `DefuseForge/`
- **言語**: GDScript

## 現在の状態
開発途中。Mixamo専用のキャラクターシステム。

テストシーン：
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
| Character | PathFollowingController | パス追従＋視線ポイント＋Run区間＋スタック検出を行う再利用可能コントローラー |
| Character | CharacterRotationController | 視線方向変更のスムーズな回転制御 |
| Effect | PathDrawer | マウスドラッグでパス描画＋視線ポイント＋Runマーカー設定 |
| Effect | PathLineMesh | 破線＋終点ドーナツ円のパスメッシュ描画 |
| Effect | RunMarker | Run区間の開始/終点を示すマーカー |
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

### 実装後のドキュメント更新（必須）
**実装が完了したら、必ず関連するAPIドキュメントを更新すること。**

- 新規クラス作成時: `docs/godot/api/<クラス名>.md` を新規作成
- 既存クラス変更時: 対応するドキュメントを更新
- CLAUDE.mdのクラス一覧も必要に応じて更新

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
