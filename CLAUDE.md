# Claude Code Rules (Godot開発)

## Goal
Godot MCPを優先的に使用してGodotを操作する。Godot MCPで対応できない場合のみファイル操作ツールを使用する。

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `SupportRateGame/`
- **言語**: GDScript
- **設計ドキュメント**: `docs/GAME_DESIGN.md` - ゲーム設計の詳細

## ゲーム概要
タクティカルシューター（CS1.6 + Door Kickers 2スタイル）
- トップダウンビューカメラ
- パス描画による移動指示（Door Kickers 2スタイル）
- ラウンド制（MR15）
- 作戦フェーズ + 実行フェーズ（ターン制）
- オンラインマルチプレイ対応（Nakama）

## プロジェクト構造
```
SupportRateGame/
├── project.godot          # プロジェクト設定
├── scenes/
│   ├── title.tscn         # タイトルシーン
│   ├── game.tscn          # ゲームシーン（dust3マップ使用）
│   ├── player.tscn        # プレイヤーシーン
│   ├── enemy.tscn         # 敵シーン
│   ├── lobby/
│   │   └── lobby.tscn     # ロビーシーン（オンラインマッチ）
│   ├── systems/           # システムシーン
│   │   ├── squad_manager.tscn
│   │   ├── match_manager.tscn
│   │   ├── path_manager.tscn
│   │   ├── camera_controller.tscn
│   │   ├── fog_of_war_manager.tscn
│   │   └── fog_of_war_renderer.tscn
│   └── weapons/
│       └── ak47.tscn      # 武器シーン
├── scripts/
│   ├── autoload/
│   │   ├── game_events.gd     # イベントバス（Autoload）- システム間連携
│   │   ├── game_manager.gd    # ゲーム管理（Autoload）- シーン遷移・設定・参照保持
│   │   ├── input_manager.gd   # 入力管理（Autoload）- タッチ/マウス入力統合
│   │   └── nakama_client.gd   # オンライン通信（Autoload）- Nakamaクライアント
│   ├── characters/
│   │   ├── character_base.gd  # キャラクター基底クラス（移動・アニメーション）
│   │   ├── player.gd          # プレイヤークラス
│   │   ├── enemy.gd           # 敵クラス（AI）
│   │   └── components/
│   │       └── vision_component.gd  # 視野コンポーネント
│   ├── systems/
│   │   ├── match_manager.gd      # マッチ管理（シーン内）- ラウンド・経済・勝敗
│   │   ├── squad_manager.gd      # 分隊管理（シーン内）- プレイヤー管理
│   │   ├── camera_controller.gd  # カメラ制御（ズーム・パン）
│   │   ├── network_sync_manager.gd  # ネットワーク同期（オンラインマッチ）
│   │   ├── grid/
│   │   │   ├── grid_manager.gd      # グリッド管理（A*パスファインディング）
│   │   │   └── path_grid_converter.gd  # パス変換（2D/3D座標）
│   │   ├── path/
│   │   │   ├── path_manager.gd   # パス管理
│   │   │   ├── path_renderer.gd  # パス描画（3Dメッシュ）
│   │   │   └── path_analyzer.gd  # パス解析（2D論理座標ベース）
│   │   └── vision/
│   │       ├── fog_of_war_manager.gd   # 視界管理（シーン内）
│   │       ├── fog_of_war_renderer.gd  # Fog描画
│   │       ├── visibility_grid_sync.gd # グリッド同期
│   │       └── visibility_texture_writer.gd  # テクスチャ書き込み
│   ├── lobby/
│   │   └── lobby_screen.gd    # ロビー画面（認証・部屋作成/参加）
│   ├── resources/
│   │   └── economy_rules.gd   # 経済ルール（Resource）
│   ├── data/
│   │   └── player_data.gd     # プレイヤーデータ（RefCounted）
│   ├── utils/
│   │   └── character_setup.gd # キャラクター設定ユーティリティ
│   ├── game_scene.gd      # ゲームシーン管理
│   ├── game_ui.gd         # UI管理（タイマー・スコア・デバッグ情報）
│   ├── title_screen.gd    # タイトル画面
│   ├── map_collision_generator.gd  # マップメッシュからコリジョン自動生成
│   └── wall_collision_generator.gd # 壁メッシュからコリジョン自動生成
├── resources/
│   ├── economy_rules.tres # 経済ルール設定ファイル
│   ├── maps/
│   │   └── dust3/         # PBRマップ（動的シャドウ対応）
│   ├── shaders/                # (未使用)
│   └── weapons/
│       └── ak47/          # 武器モデル・テクスチャ
├── shaders/
│   └── fog_of_war.gdshader    # Fog of Warシェーダー
├── assets/
│   └── characters/        # キャラクターモデル・アニメーション
│       ├── gsg9/          # CT側キャラクター
│       ├── leet/          # T側キャラクター
│       └── animations/    # 共通アニメーション
├── addons/
│   └── nakama/            # Nakamaプラグイン
└── builds/
    ├── ios/               # iOSビルド出力
    └── android/           # Androidビルド出力
```

## アーキテクチャ

### 設計原則
1. **Autoloadは薄く**: シーン遷移・設定・イベントバス・参照保持のみ
2. **シーン内ノード**: ゲームロジックはシーン内に配置（シーン切替で自動クリーンアップ）
3. **イベント駆動**: システム間はGameEventsを介して疎結合に連携
4. **2D論理座標**: パスは2D（Vector2）で管理し、表示時に3Dに投影
5. **Resourceで設定分離**: economy_rules.tresなどで設定をデータ化

### Autoload（シングルトン）
- **GameEvents**: イベントバス - システム間の疎結合連携
- **GameManager**: シーン遷移、設定、シーンノードへの参照保持
- **InputManager**: 全入力を一元管理、シグナルで各システムに通知
- **NakamaClient**: オンライン通信 - 認証・マッチメイキング・リアルタイム同期

### シーン内ノード（game.tscn）
- **MatchManager**: ラウンド/経済/勝敗（GameEventsと連携）
- **SquadManager**: 分隊管理、選択・経済・装備
- **FogOfWarManager**: 視界システム管理
- **PathManager**: パス描画管理
- **CameraController**: カメラ制御
- **FogOfWarRenderer**: Fog描画
- **GridManager**: A*パスファインディング
- **NetworkSyncManager**: オンライン同期（オンラインマッチ時のみ）

※ シーンノードへの参照は`GameManager.squad_manager`、`GameManager.fog_of_war_manager`、`GameManager.grid_manager`経由でアクセス可能

### イベントバス（GameEvents）
systems同士が直接呼び合う代わりにGameEventsを介して連携：
```gdscript
# ユニット関連
signal unit_spotted(observer, target)
signal unit_killed(killer, victim, weapon_id)
signal unit_damaged(target, damage, attacker)

# ラウンド関連
signal round_started(round_number)
signal round_ended(winner_team)
signal buy_phase_started()
signal play_phase_started()

# フェーズ関連
signal strategy_phase_started(turn_number)
signal execution_phase_started(turn_number)

# 経済関連
signal money_changed(player, new_amount)
signal reward_granted(player, amount, reason)

# 爆弾関連
signal bomb_planted(site, planter)
signal bomb_defused(defuser)
```

### クラス階層
```
CharacterBase (character_base.gd)
├── Player (player.gd) - プレイヤー固有機能
└── Enemy (enemy.gd) - AI敵キャラクター
```

### リソース
- **EconomyRules** (`economy_rules.gd` / `economy_rules.tres`): 経済パラメータを一元管理
  - 勝敗/連敗ボーナス/キル報酬/ラウンド時間/購入時間など
- **PlayerData**: プレイヤー個別データ（経済/装備/統計）

## 技術詳細

### マップ
- **dust3**: PBRマテリアル使用（動的シャドウ対応）
- コリジョンは`map_collision_generator.gd`と`wall_collision_generator.gd`で自動生成
  - 地形: collision_layer=2
  - 壁: collision_layer=6（bit 1 + bit 2）

### シャドウ設定（DirectionalLight3D）
```
shadow_enabled = true
shadow_bias = 0.03
shadow_normal_bias = 1.5
shadow_blur = 0.5
directional_shadow_max_distance = 50.0
directional_shadow_mode = 1 (PSSM 2 splits - 軽量化)
directional_shadow_blend_splits = false
```

### プレイヤー/敵
- CharacterBody3D + 重力ベースの地形追従
- パス追従移動（waypoints配列）
- アニメーション: idle, walking, running（FBXから読み込み）
- 敵はAIStateによる状態管理（IDLE, PATROL, CHASE, ATTACK, COVER）
- 敵は`enemies`グループに自動追加

### パスシステム
- **論理座標**: Vector2（XZ平面）で管理
- **表示座標**: Vector3に投影して描画
- PathAnalyzerで2D/3D変換ユーティリティ提供
- GridManagerでA*パスファインディング

### 入力操作
- **1本指ドラッグ**: パス描画（移動指示）
- **2本指ピンチ**: ズーム
- **2本指ドラッグ**: カメラパン
- **マウスホイール**: ズーム（PC）

### オンラインマルチプレイ
- **Nakama**サーバーを使用
- 認証: デバイス認証 / カスタム認証
- マッチメイキング: ルーム作成 / コード参加
- リアルタイム同期: WebSocket経由

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

## iOS実機ビルド（重要）
**必ず専用スクリプトを使用すること！** 手動でGodotエクスポートやXcode操作をしない。

```bash
# iOS実機ビルド＆インストール（常にこれを使用）
./scripts/ios_build.sh --export
```

**重要: 必ず`--export`オプションを付けること！** これにより最新のコードがエクスポートされる。

### スクリプトが行うこと
1. 署名設定を自動修正（Automatic signing, Team ID設定）
2. 実機の接続確認
3. Xcodeビルド
4. 実機へのインストール

### 注意
- Godotの`--export-debug`を直接実行すると署名設定が壊れる
- 必ず`ios_build.sh`経由でビルドすること

## 開発フロー
1. スクリプトファイルはファイル操作ツールで編集
2. シーンファイルはGodot MCPまたはファイル操作ツールで編集
3. テスト実行はGodot MCPの`run_project`を使用
4. **iOS実機ビルドは`./scripts/ios_build.sh`を使用**

## Error handling
- シーンが読み込めない → UIDを確認
- スクリプトエラー → Godotコンソールを確認（`get_debug_output`）
- ノードが見つからない → シーンツリーを確認
- 影が表示されない → マテリアルがPBR（shading_mode=1）か確認
- 影がチラつく → shadow_bias, shadow_normal_biasを調整

## 非推奨API（将来削除予定）
以下のGameManagerメソッドは後方互換性のために維持されているが、新規コードでは使用しないこと：
- `buy_weapon(price)` → `buy_weapon_for_selected(weapon_id)` を使用
- `on_enemy_killed()` → `GameEvents.unit_killed.emit()` を使用
- `on_bomb_planted()` → `GameEvents.bomb_planted.emit()` を使用
- `damage_player()` → `SquadManager.damage_selected_player()` を使用
