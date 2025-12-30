# Tactical Shooter Game Design Document

## ゲームコンセプト
**ゲームルール**: CS1.6（Counter-Strike 1.6）
**操作性・エンジン**: Door Kickers 2

### CS1.6から採用する要素
- テロリスト vs カウンターテロリスト
- 爆弾解除モード（Defuse）/ 人質救出モード（Hostage）
- ラウンド制
- 武器購入システム
- ヘッドショット判定
- 経済システム（キルボーナス、ラウンドボーナス）

### Door Kickers 2から採用する要素
- トップダウン視点
- パス描画による移動指示
- リアルタイム戦術
- Fog of War（視界制限）
- 自動射撃（敵発見時）
- ドア突入・クリアリング

---

## ゲームモード

### 1. 爆弾解除モード (Bomb Defuse)
- テロリスト: 爆弾設置サイトに爆弾を設置
- CT: 爆弾設置を阻止、または設置された爆弾を解除
- ラウンド時間: 1分45秒
- 爆弾タイマー: 40秒

### 2. 人質救出モード (Hostage Rescue)
- テロリスト: 人質を守る
- CT: 人質を救出ゾーンまで誘導
- ラウンド時間: 2分

---

## コアシステム設計

### 1. パス描画・移動システム (PathSystem)

#### 操作方法
- **タップ**: キャラクター選択
- **ドラッグ**: パスを描画
- **ダブルタップ**: 走り指示
- **長押し**: 待機/位置固定

#### 実装
```
PathDrawer (CanvasLayer)
├── draw_path(start: Vector3, points: Array[Vector3])
├── clear_path()
├── confirm_path() → Signal
└── cancel_path()

PathFollower (Component)
├── set_path(waypoints: Array[Vector3])
├── start_moving()
├── stop_moving()
├── pause_at_waypoint(index: int)
└── move_speed: float
```

---

### 2. 視界システム (Fog of War)

#### 視界タイプ
- **完全視界**: キャラクターの視線内
- **探索済み**: 一度見た場所（薄暗い）
- **未探索**: 見たことがない場所（真っ暗）

#### 視線遮断
- 壁による遮蔽
- 視野角（約120度）
- 視界距離

---

### 3. 戦闘システム (Combat)

#### 自動射撃ルール
1. 敵が視界内に入る
2. 射線が通っている（壁越しはNG）
3. 自動で射撃開始
4. 敵が視界外に出る or 倒すまで継続

#### 武器パラメータ
```gdscript
class_name Weapon extends Resource

@export var name: String
@export var damage: float           # ダメージ
@export var fire_rate: float        # 発射レート（秒）
@export var range: float            # 射程
@export var accuracy: float         # 精度（0-1）
@export var magazine_size: int      # マガジン容量
@export var reload_time: float      # リロード時間
@export var price: int              # 購入価格
@export var kill_reward: int        # キルボーナス
```

#### CS1.6準拠の武器リスト（初期実装）
| 武器 | ダメージ | レート | 価格 |
|-----|---------|--------|------|
| Glock | 25 | 0.15s | $400 |
| USP | 34 | 0.17s | $500 |
| AK-47 | 36 | 0.1s | $2500 |
| M4A1 | 33 | 0.09s | $3100 |
| AWP | 115 | 1.2s | $4750 |

---

### 4. 経済システム (Economy)

#### ラウンド報酬
- 勝利: $3250
- 敗北: $1400〜$3400（連敗ボーナス）
- 爆弾設置: $300

#### キル報酬
- 通常武器: $300
- AWP: $100
- ナイフ: $1500

---

### 5. 敵AI (Enemy AI)

#### 状態遷移
```
Idle → Patrol → Alert → Combat → Dead
         ↑         ↓
         └─────────┘
```

#### 行動パターン
- **Patrol**: 指定ルートを巡回
- **Alert**: 音や視覚刺激で警戒、発生源を調査
- **Combat**: 射撃、遮蔽物利用、仲間呼び出し

---

## ファイル構造

```
SupportRateGame/
├── docs/
│   └── GAME_DESIGN.md            # この文書
├── scenes/
│   ├── game.tscn                 # メインゲームシーン
│   ├── title.tscn                # タイトル画面
│   ├── player.tscn               # プレイヤー
│   └── enemy.tscn                # 敵
├── scripts/
│   ├── autoload/                 # シングルトン（薄く保つ）
│   │   ├── game_events.gd        # イベントバス - システム間連携
│   │   ├── game_manager.gd       # シーン遷移・設定のみ
│   │   ├── input_manager.gd      # 入力管理
│   │   ├── squad_manager.gd      # 5人分隊管理
│   │   └── fog_of_war_manager.gd # 視界管理
│   ├── characters/
│   │   ├── character_base.gd     # キャラクター基底クラス
│   │   ├── player.gd             # プレイヤー
│   │   └── enemy.gd              # 敵AI
│   ├── systems/                  # シーン内ノード
│   │   ├── match_manager.gd      # ラウンド/経済/勝敗
│   │   ├── camera_controller.gd  # カメラ制御
│   │   ├── path/
│   │   │   ├── path_manager.gd   # パス管理
│   │   │   ├── path_renderer.gd  # 3D描画
│   │   │   └── path_analyzer.gd  # 2D論理座標解析
│   │   └── vision/
│   │       ├── fog_of_war_renderer.gd
│   │       └── vision_component.gd
│   ├── resources/
│   │   └── economy_rules.gd      # 経済ルール（Resource）
│   ├── data/
│   │   └── player_data.gd        # プレイヤーデータ
│   ├── utils/
│   │   └── character_setup.gd    # 武器データ等
│   ├── game_scene.gd             # ゲームシーン管理
│   ├── game_ui.gd                # UI管理
│   └── title_screen.gd           # タイトル
├── resources/
│   └── maps/
│       └── dust3/                # PBRマップ
├── shaders/
│   └── fog_of_war.gdshader       # 視界シェーダー
└── assets/
    ├── characters/               # キャラクターモデル
    └── maps/                     # マップ
```

### アーキテクチャ設計原則

1. **Autoloadは薄く**: シーン遷移・設定・イベントバスに限定
2. **イベント駆動**: システム間はGameEventsを介して疎結合に連携
3. **シーン内ノード**: ゲームロジック（MatchManager等）はシーン内に配置
4. **2D論理座標**: パスはVector2で管理し、表示時に3Dに投影

---

## 削除対象

| ファイル | 理由 |
|---------|------|
| `coin.gd` | コイン収集は不要 |
| `coin_spawner.gd` | コイン収集は不要 |
| `coin.tscn` | コイン収集は不要 |
| `virtual_joystick.gd` | パス描画に置換 |
| `virtual_joystick.tscn` | パス描画に置換 |
| `terrain_collision.gd` | 新マップシステムで対応 |

---

## 実装フェーズ

### Phase 1: 基盤整備 ✓ 進行中
- [x] 設計ドキュメント作成
- [ ] 不要ファイル削除
- [ ] ディレクトリ構造整理
- [ ] GameManager更新

### Phase 2: パス描画・移動
- [ ] PathDrawer実装（UI）
- [ ] 画面座標→ワールド座標変換
- [ ] PathFollower実装
- [ ] プレイヤー移動をパス追従に変更

### Phase 3: 視界システム
- [ ] Fog of Warシェーダー
- [ ] VisionSystem実装
- [ ] 壁による視線遮断

### Phase 4: 戦闘システム
- [ ] Weaponリソース定義
- [ ] CombatController（自動射撃）
- [ ] ダメージ・ヒット判定

### Phase 5: 敵AI
- [ ] 基本AI（巡回・待機）
- [ ] 検知システム（視覚・聴覚）
- [ ] 戦闘AI

### Phase 6: CS1.6ルール
- [ ] ラウンドシステム
- [ ] 経済システム
- [ ] 武器購入メニュー
- [ ] 爆弾設置/解除

### Phase 7: ポリッシュ
- [ ] エフェクト
- [ ] サウンド
- [ ] マップ作成
- [ ] バランス調整

---

## 技術メモ

### カメラ設定
- トップダウン（ピッチ70-80度）
- ズーム: マウスホイール / ピンチ
- パン: 画面端ドラッグ

### パフォーマンス最適化
- Fog of War: 0.1秒間隔で更新
- 敵AI: 物理フレームで更新（_physics_process）
- オブジェクトプール: 弾丸、エフェクト

### モバイル対応
- タッチでパス描画
- ダブルタップで走り
- 長押しで待機指示
