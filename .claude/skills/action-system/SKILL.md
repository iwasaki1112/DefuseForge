---
name: action-system
description: アクションシステム変更ガイド
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
---

# アクションシステム変更ガイド

Vision/Wait等のアクションポイントに変更を加える際のガイド。

## 主要ファイル

### データ・表示
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/effects/action_point_data.gd` | ActionPointData | ポイントデータ基底クラス |
| `scripts/effects/action_point.gd` | ActionPoint | ポイント表示基底クラス |
| `scripts/effects/vision_point.gd` | VisionPoint | 視線ポイント表示（矢印+ターゲット線） |
| `scripts/effects/wait_point.gd` | WaitPoint | 待機ポイント表示（砂時計+ラベル） |
| `scripts/effects/smoke_grenade_point.gd` | SmokeGrenadePoint | スモークグレネード投擲位置表示（雲アイコン） |

### 入力処理
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/effects/point_handler_base.gd` | PointHandlerBase | 入力処理テンプレート |
| `scripts/effects/point_handlers/vision_point_handler.gd` | VisionPointHandler | Vision入力（ドラッグで方向） |
| `scripts/effects/point_handlers/wait_point_handler.gd` | WaitPointHandler | Wait入力（長押しで時間） |

### ファクトリ・プール
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/effects/point_factory.gd` | PointFactory | ポイント生成（プール統合） |
| `scripts/effects/action_point_pool.gd` | ActionPointPool | オブジェクトプール |
| `scripts/effects/point_definition.gd` | PointDefinition | タイプ定義（クラス名・色・プールサイズ） |
| `scripts/effects/point_registry.gd` | PointRegistry | タイプ定義の一元管理（シングルトン） |
| `scripts/effects/point_collection.gd` | PointCollection | 複数ポイント統一管理 |

### 実行制御
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/characters/path_following_controller.gd` | PathFollowingController | ポイント到達判定・実行 |
| `scripts/characters/path_point_checker.gd` | PathPointChecker | 到達判定（RATIO/DISTANCE） |

## 実行フロー

```
[入力]
VisionPointHandler/WaitPointHandler
    ↓ point_added シグナル
[生成]
PointFactory.create_vision_point/create_wait_point
    ↓ ActionPointPool.acquire_*
[表示]
VisionPoint/WaitPoint メッシュ生成
    ↓
[実行開始]
PathFollowingController.start_following()
    ↓
[毎フレーム]
PathPointChecker.check_all_reached()
    ↓ 到達判定
[効果実行]
ActionPointData.apply_reached_effect()
    ↓
PathFollowingController.apply_vision_effect/apply_wait_effect
```

## 重要な設計

### Vision ポイント
```
入力: ドラッグでアンカー+ターゲット地点を設定
実行時: キャラクター到達で視線方向を計算・適用
  - _active_target_point: ターゲット追従（動的）
  - _forced_look_direction: 固定方向
```

### Wait ポイント
```
入力: 長押しでアンカー+待機時間を設定
実行時: キャラクター到達で待機開始
  - _is_waiting_for_wait = true
  - _wait_timer でカウントダウン
  - wait_duration < 0: 同期待機（-1）
```

### SmokeGrenade ポイント
```
入力: コンテキストメニュー → ターゲット選択の2ステップUI
実行時: キャラクター到達でsmoke_grenade_point_reachedシグナル発火
  - Handlerなし（コンテキストメニューベースのUI）
  - アンカーマーカー（SmokeGrenadePoint）: 投擲地点到達で非表示
  - 着弾マーカー（MeshInstance3D）: グレネード爆発で非表示
  - apply_reached_effect()は空実装（信号ベースで投擲処理）
```

### 到達判定モード
```gdscript
enum CheckMode {
    RATIO,     # パス比率ベース
    DISTANCE,  # 移動距離ベース（Vision/Wait用、精度高）
}
```

## クラス関係

```
RefCounted
├── ActionPointData (基底)
│   ├── VisionPointData
│   ├── WaitPointData
│   └── SmokeGrenadePointData
├── PointHandlerBase (入力基底)
│   ├── VisionPointHandler
│   └── WaitPointHandler
│   （SmokeGrenadeはHandler不要 — コンテキストメニューUI）
├── PathPointChecker
├── ActionPointPool
├── PointRegistry (シングルトン)
└── PointCollection

Resource
└── PointDefinition (タイプ定義)

MeshInstance3D
└── ActionPoint (表示基底)
    ├── VisionPoint
    ├── WaitPoint
    └── SmokeGrenadePoint
```

## 変更時の注意点

1. **距離ベース判定** - RATIO より DISTANCE が高精度
2. **ポイントのソート順** - 単調増加性を保証（PathPointChecker）
3. **オブジェクトプール** - MAX_POOL_SIZE_PER_TYPE を確認
4. **シグナル接続・切断** - メモリリーク防止
5. **iOS互換** - `class_name` 定義済みは直接参照OK、それ以外は `load()`

## よくある変更パターン

### 新しいポイント種別を追加（7ステップパイプライン）

**必ずこの順序で全ステップを実行すること。WaitPoint等の流用は禁止。**

```
Step 1: ActionPointData.Type enum に新タイプ追加
Step 2: XxxPoint extends ActionPoint を新規作成（class_name必須）
Step 3: XxxPointData extends ActionPointData を action_point_data.gd に内部クラスとして追加
        + create() ファクトリに分岐追加
Step 4: PointDefinition.create_point_instance() に分岐追加
        + handler不要なら create_handler_instance() で "" ケースは既に対応済み
Step 5: PointRegistry._initialize_default_definitions() に定義登録
Step 6: ActionPointPool._reset_point() にケース追加
Step 7: PointFactory に create_xxx_point() + create_point_by_type() 分岐追加
```

```gdscript
# Step 2: 表示クラス（例: SmokeGrenadePoint）
class_name SmokeGrenadePoint
extends ActionPoint

func get_action_point_type() -> PointType:
    return PointType.SMOKE_GRENADE

func _build_icon() -> void:
    # アイコン描画

# Step 3: データクラス（action_point_data.gd 内部クラス）
class SmokeGrenadePointData extends ActionPointData:
    var target_pos: Vector3 = Vector3.ZERO
    func _init() -> void:
        type = Type.SMOKE_GRENADE
    func create_point_node() -> Node3D:
        return SmokeGrenadePoint.new()
    func apply_reached_effect(_controller: Node, _idx: int) -> bool:
        return false  # 信号ベースの場合

# Step 5: レジストリ登録（point_registry.gd）
var smoke_def = PointDefinition.new()
smoke_def.type_id = ActionPointData.Type.SMOKE_GRENADE
smoke_def.point_class_name = "SmokeGrenadePoint"
smoke_def.handler_class_name = ""  # Handler不要の場合
smoke_def.max_pool_size = 20
_register(smoke_def)

# Step 7: ファクトリメソッド（point_factory.gd）
static func create_smoke_grenade_point(anchor, target_pos, char_color, parent) -> MeshInstance3D:
    var point = ActionPointPool.acquire(PointType.SMOKE_GRENADE)
    point.set_point_position(anchor)
    point.set_colors(char_color, Color(1.0, 1.0, 1.0, 1.0))
    return point
```

**入力処理が必要な場合のみ追加:**
- `XxxPointHandler extends PointHandlerBase` を作成
- `PointDefinition.create_handler_instance()` に分岐追加
- `PointRegistry` の定義で `handler_class_name` を指定

### 到達判定ロジックの変更
`PathPointChecker._is_point_reached()` をカスタマイズ

### エフェクト実行時のアクション追加
```gdscript
func apply_vision_effect(idx: int, target: Vector3, dir: Vector3) -> void:
    # 既存処理
    if has_target:
        _active_target_point = target

    # 追加処理
    _vfx_manager.play_vision_effect(global_position)
```

## デバッグ

```gdscript
if Debug.enabled:
    print("[PointDebug] reached: idx=%d, ratio=%.3f" % [idx, data.path_ratio])
```

---
**関連ドキュメント**: `docs/godot/api/ActionPointData.md`, `docs/godot/api/PointFactory.md`
