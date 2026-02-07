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
│   └── WaitPointData
├── PointHandlerBase (入力基底)
│   ├── VisionPointHandler
│   └── WaitPointHandler
├── PathPointChecker
├── ActionPointPool
└── PointCollection

MeshInstance3D
└── ActionPoint (表示基底)
    ├── VisionPoint
    └── WaitPoint
```

## 変更時の注意点

1. **距離ベース判定** - RATIO より DISTANCE が高精度
2. **ポイントのソート順** - 単調増加性を保証（PathPointChecker）
3. **オブジェクトプール** - MAX_POOL_SIZE_PER_TYPE を確認
4. **シグナル接続・切断** - メモリリーク防止
5. **iOS互換** - `class_name` 定義済みは直接参照OK、それ以外は `load()`

## よくある変更パターン

### 新しいポイント種別を追加

```gdscript
# 1. ActionPointData にサブクラス追加
class CustomPointData extends ActionPointData:
    func _init() -> void:
        type = Type.CUSTOM  # Type enumに追加

    func apply_reached_effect(controller: Node, idx: int) -> bool:
        controller.apply_custom_effect(idx, to_dict())
        return true

# 2. ActionPoint にサブクラス追加
class CustomPoint extends ActionPoint:
    func get_action_point_type() -> PointType:
        return PointType.CUSTOM

# 3. PointFactory にメソッド追加
static func create_custom_point(...) -> MeshInstance3D:
    var point = ActionPointPool.acquire_custom_point()
    return point

# 4. ActionPointPool にプール追加
var _available_custom_points: Array[CustomPoint] = []

# 5. PathFollowingController に効果実行メソッド追加
func apply_custom_effect(idx: int, data: Dictionary) -> void:
    custom_point_reached.emit(idx, data)

# 6. PathDrawer に入力ハンドラ追加
_custom_handler = CustomPointHandler.new()
```

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
