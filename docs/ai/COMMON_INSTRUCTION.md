# Rules (Godot開発)

## 設定
- **言語**: 日本語で応答すること

## プロジェクト情報
- **エンジン**: Godot 4.6
- **プロジェクトパス**: `godot/`
- **言語**: GDScript

## プロジェクト概要
タクティカルシューター（モバイルゲーム）。TPS直接操作で移動・自動戦闘。

- **入力**: ツインスティック（移動+カメラ） / WASD+マウス
- **パフォーマンス優先**: モバイル向けに最適化すること

## リポジトリ構成（概要）
- **`godot/`**: ゲーム本体（Godotプロジェクト）
- **`server/relay/`**: WebSocketリレーサーバー（Go）
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

## マルチプレイヤーアーキテクチャ

WebSocketリレーサーバー方式を採用：

```
┌─────────┐     ┌─────────────────┐     ┌─────────┐
│ Player1 │────▶│   Cloud Run     │◀────│ Player2 │
│ (Host)  │◀────│ WebSocket Relay │────▶│(Client) │
└─────────┘     └─────────────────┘     └─────────┘
```

- **リレーサーバー**: `server/relay/` (Go, Cloud Run)
- **NetworkManager**: WebSocketPeerベースのルーム管理
- **LobbyScreen**: ルームリスト表示・参加UI

### ローカル開発

```bash
# サーバー起動
cd server/relay && go run .

# Godot側でローカルサーバーに接続
# network_constants.gd の USE_LOCAL_RELAY = true
```

### GCP Cloud Run デプロイ

**プロジェクト**: rescueforge
**リージョン**: asia-northeast1 (東京)
**サービスURL**: `wss://rescueforge-relay-344342786567.asia-northeast1.run.app/ws`

```bash
# デプロイ
cd server/relay
gcloud run deploy rescueforge-relay \
  --source . \
  --platform managed \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --session-affinity \
  --min-instances=1

# ヘルスチェック
curl https://rescueforge-relay-344342786567.asia-northeast1.run.app/health

# ログ確認
gcloud run services logs read rescueforge-relay --region asia-northeast1 --limit 30

# サービス情報
gcloud run services describe rescueforge-relay --region asia-northeast1
```

| オプション | 説明 |
|-----------|------|
| `--session-affinity` | WebSocket用にセッション維持 |
| `--min-instances=1` | コールドスタート回避（重要） |
| `--max-instances=3` | 最大インスタンス数 |

**トラブルシューティング**:
- 接続失敗時: ログ確認 → サーバー再デプロイ
- WebSocket 101成功だがメッセージ未処理: デッドロックの可能性 → 再デプロイ

詳細: `docs/godot/api/Network/NetworkManager.md`

### ラグ補償アーキテクチャ

リモートキャラクターの滑らかな描画のため、以下の技術を採用：

| 技術 | 説明 | 設定値 |
|------|------|--------|
| **補間バッファ** | 受信状態を80ms遅らせて2点間補間 | `INTERPOLATION_DELAY = 0.08` |
| **外挿** | パケットロス時に速度ベースで予測 | `MAX_EXTRAPOLATION_TIME = 0.15` |
| **Tick分離** | シミュレーション60Hz / ネット送信15Hz | `NETWORK_SEND_HZ = 15` |
| **対称送信** | Host/Client両方が同じ15Hzで送信 | 非対称だとラグ差が発生 |

```
受信状態: ──●──────●──────●──────●───→ 時間
                           ↑
                    描画位置（80ms遅延で補間）
```

**チューニング**: `network_constants.gd` の `INTERPOLATION_DELAY` を調整
- 大きく(120ms): より滑らか、ラグ増
- 小さく(50ms): レスポンス良、カクつき増

## game-flowの読み方（最短導線）
1. **画面遷移図**: 起動からゲーム開始までの流れを把握
2. **GameScreen**: 初期化処理と主要システムの関係を把握
3. **データフロー**: MapSelection→GameScreenのデータ伝播を確認
4. **登録済みマップ**: マップ追加・構成の流れを確認

## 現在の状態
開発途中。ARPリグ + in-placeアニメーションのキャラクターシステム。マップはBlenderで作成しGLTFインポート。

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

### iOSビルド時の注意事項

> **警告: iOSエクスポートはPCエディタより厳密にスクリプトを検証する**

iOSでは以下の問題がPCでは発生せず、iOSでのみ発生することがある：

| 問題 | 原因 | 対策 |
|------|------|------|
| `preload`の失敗 | iOSではスクリプトが一括でAOTコンパイルされ、依存関係の解決順序が厳密 | `preload`の代わりに`load`を`_init()`で使用する |
| 変数の重複宣言エラー | iOSでは同一スコープ内の`var`重複がParse Errorになる | 同じ関数内で同じ変数名を再宣言しない |
| スクリプトのロード失敗 | 循環参照や依存関係の問題 | `class_name`を持つクラスは直接参照、それ以外は`load`を使用 |

**推奨パターン:**

```gdscript
# NG: iOSで失敗する可能性あり
const SomeScript = preload("res://scripts/some_script.gd")

# OK: 遅延ロードでiOS互換
var SomeScript: GDScript = null

func _init() -> void:
    SomeScript = load("res://scripts/some_script.gd")

# OK: class_nameを持つクラスは直接参照可能
const PointType = ActionPointData.Type  # ActionPointDataはclass_name定義済み
```

**テスト必須:** PCで動作してもiOSで失敗することがあるため、機能追加後は必ずiOS実機でテストすること。

### キャラクターの向き制御

> **警告: `CharacterBody3D.look_at()`を直接使用しないこと**

| 項目 | 方向 |
|------|------|
| モデルの前方向（ARP/Mixamo共通） | **+Z** |
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
