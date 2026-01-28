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
必要なクラスドキュメントも必ず参照すること

- **画面フローの全体像**: `docs/godot/game-flow.md`
- **最初に表示される画面**: `scenes/screens/main_menu.tscn` / `scripts/screens/main_menu_screen.gd`
- **マップ選択画面**: `scenes/screens/map_selection.tscn` / `scripts/screens/map_selection_screen.gd`
- **設定画面**: `scenes/screens/option.tscn` / `scripts/screens/option_screen.gd`
- **ゲーム本編画面**: `scenes/screens/game.tscn` / `scripts/screens/game_screen.gd`
- **マルチプレイヤーロビー**: `scenes/screens/lobby.tscn` / `scripts/screens/lobby_screen.gd`

## ゲームモードアーキテクチャ

GameScreenはProviderパターンを採用し、TrainingとMultiplayerを統合：

```
GameScreen (統合されたゲーム画面)
    └── GameModeProvider (モード抽象化)
          ├── TrainingModeProvider (シングルプレイヤー)
          └── MultiplayerModeProvider (マルチプレイヤー)
```

- **GameScreen**: 共通処理（マップ、キャラクター、HUD、カメラ）
- **TrainingModeProvider**: ローカル処理のみ
- **MultiplayerModeProvider**: NetworkManager/SyncController保持、ネットワーク同期

詳細: `docs/godot/api/Screen/README.md`

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
詳細は `docs/godot/api/README.md` を参照。
各クラスの仕様・使用例・内部動作が記載されており、実装の整合性を保つために重要。

### 実装後のドキュメント更新（必須）
**実装が完了したら、必ず関連するAPIドキュメントを更新すること。**

- 新規クラス作成時: `docs/godot/api/<クラス名>.md` を新規作成
- 既存クラス変更時: 対応するドキュメントを更新
- docs/ai/COMMON_INSTRUCTION.mdのクラス一覧も必要に応じて更新

## 実装時の重要な注意事項

### キャラクターの向き制御

> **警告: `CharacterBody3D.look_at()`を直接使用しないこと**

| 項目 | 方向 |
|------|------|
| Mixamoモデルの前方向 | **+Z** |
| Godotの`look_at()`がターゲットに向ける軸 | **-Z** |

この180度の差により、キャラクターの向きを変更する際は以下のAPIを使用する：

```gdscript
# 正しい方法
character.face_towards(target_pos)           # ターゲット位置を向く
character.set_facing_direction_vec(direction) # 方向ベクトルで設定

# 間違った方法（使用禁止）
character.look_at(target_pos, Vector3.UP)    # 180度ずれる
```

詳細: `docs/godot/api/GameCharacter.md` および `docs/godot/api/CharacterAnimationController.md` を参照。

## Tool Priority
1. **Godot MCP** (優先) - シーン作成・編集・実行
2. **GDScript LSP** (`gdscript-lsp`) - シンボル検索、コード解析
3. **ファイル操作** (フォールバック) - スクリプト編集
