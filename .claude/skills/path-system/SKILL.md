---
name: path-system
description: パスシステム変更ガイド
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
---

# パスシステム変更ガイド

パス描画・実行システムに変更を加える際のガイド。

## 主要ファイル

### コアシステム
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/systems/path_service.gd` | PathService | 統合ファサード（入口） |
| `scripts/systems/path_mode_controller.gd` | PathModeController | パスモード状態管理 |
| `scripts/systems/path_execution_manager.gd` | PathExecutionManager | パス確定・実行・pending_paths管理 |
| `scripts/systems/path_undo_manager.gd` | PathUndoManager | Undo/Redo履歴管理 |

### 描画・ユーティリティ
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/effects/path_drawer.gd` | PathDrawer | パス描画・入力処理 |
| `scripts/characters/path_following_controller.gd` | PathFollowingController | パス追従・実行制御 |
| `scripts/effects/path_calculator.gd` | PathCalculator | パス上の位置計算（static） |
| `scripts/effects/path_raycast_helper.gd` | PathRaycastHelper | 壁・床判定（static） |
| `scripts/effects/path_line_mesh.gd` | PathLineMesh | ドット線メッシュ描画 |
| `scripts/effects/path_line_mesh_pool.gd` | PathLineMeshPool | メッシュプール管理 |

### ポイント処理
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/effects/point_handler_base.gd` | PointHandlerBase | ハンドラ基底クラス |
| `scripts/effects/point_handlers/vision_point_handler.gd` | VisionPointHandler | Vision ポイント |
| `scripts/effects/point_handlers/wait_point_handler.gd` | WaitPointHandler | Wait ポイント |
| `scripts/effects/point_factory.gd` | PointFactory | ポイント生成 |
| `scripts/characters/path_point_checker.gd` | PathPointChecker | 到達判定 |

## シグナルフロー

```
InputController（タップ検出）
    ↓
PathDrawer（描画）
    ├─ path_started → PathExecutionManager.start_realtime_path()
    ├─ path_point_added → PathExecutionManager.add_realtime_path_point()
    └─ drawing_finished → PathModeController.path_ready
        ↓
    UI: 確定/キャンセルボタン表示
        ↓
PathService.execute_all_paths()
    ↓
PathExecutionManager.execute_all_paths()
    ↓
PathFollowingController.start_path()
    ├─ vision_point_reached → ポイント非表示
    ├─ wait_point_reached → 待機開始
    └─ path_completed → メッシュクリア
```

## 重要な設計

### リアルタイム確定
パスは描画終了時ではなく、**ドラッグ中にリアルタイムで** `pending_paths` に追加される。

```
描画開始 → path_started → start_realtime_path()
ドラッグ中 → path_point_added → add_realtime_path_point()
描画終了 → drawing_finished（確定処理は不要、既にpending_pathsにある）
```

### メッシュ所有権
`PathDrawer` → `PathExecutionManager` へメッシュ所有権が移譲される。
- `transfer_vision_meshes_to()` / `transfer_wait_meshes_to()` を使用
- PathDrawer クリア時にメッシュを `queue_free()` しない

## 変更時の注意点

1. **confirm_path()は呼ばれない** - リアルタイム確定設計のため
2. **Undo時は両方更新** - `pending_paths` と `PathDrawer` を同期
3. **距離ベース判定** - `_last_distance_traveled` で単調増加を保証
4. **衝突回避の優先度** - 数値が低いほど高優先
5. **iOS互換** - `load()` で動的ロード推奨

## よくある変更パターン

### 新しいポイント種別を追加
1. `PointHandlerBase` を継承してハンドラ作成
2. `PathDrawer.DrawingMode` に新モード追加
3. `PathDrawer` にハンドラ統合
4. `PathExecutionManager` に `add_realtime_xxx_point()` 追加
5. `PathFollowingController` に `_check_xxx_points()` 追加
6. `PathUndoManager.OperationType` に新型追加

### パス確定時の検証追加
`PathExecutionManager.confirm_path()` 内に検証ロジックを追加

### パス可視化の改善
`PathLineMesh.update_from_points()` の描画ロジックを変更

## デバッグ

```gdscript
const DEBUG_PATH: bool = true  # 各クラスで一時的に有効化
```

---
**関連ドキュメント**: `docs/godot/api/PathService.md`, `docs/godot/api/PathDrawer.md`
