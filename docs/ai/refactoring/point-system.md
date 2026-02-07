# ポイントシステム リファクタリング記録

**実施日:** 2026-01-31
**対象バージョン:** feature/refactor-1

## 概要

Vision/Waitポイントの共通ロジックを抽出し、重複コードを削減。
ポイント作成、状態管理、メッシュ管理を統一化。

## 変更内容

### 1. PointFactory（新規作成）

**ファイル:** `godot/scripts/effects/point_factory.gd`

ポイントメッシュ作成を一元化するファクトリクラスを新規作成。

**主要メソッド:**
- `create_vision_point()` - VisionPointメッシュ作成
- `create_wait_point()` - WaitPointメッシュ作成
- `create_point_by_type()` - タイプに応じたメッシュ作成
- `create_*_preview()` - プレビュー用半透明メッシュ作成
- `free_point_meshes()` - メッシュ配列の解放

### 2. PointHandlerBase強化

**ファイル:** `godot/scripts/effects/point_handler_base.gd`

共通状態と共通メソッドを基底クラスに集約。

**追加された共通状態:**
```gdscript
var _points: Array[Dictionary] = []
var _meshes: Array[MeshInstance3D] = []
var _current_anchor: Vector3 = Vector3.ZERO
var _current_ratio: float = 0.0
var _is_active: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
```

**追加された共通メソッド:**
- `has_points()` - ポイント存在確認
- `get_points()` - ポイントデータ取得
- `take_meshes()` - メッシュ所有権移譲
- `undo_last()` - 最後のポイント取り消し
- `clear_all()` - 全ポイント削除
- `_add_point()` - ポイント追加の共通処理
- `_check_path_click()` - パスクリック判定
- `_is_tap()` - タップ判定ヘルパー

### 3. VisionPointHandler簡略化

**ファイル:** `godot/scripts/effects/point_handlers/vision_point_handler.gd`

**変更前:** ~245行
**変更後:** ~114行

- 状態管理を基底クラスに委譲
- メッシュ作成をPointFactoryに委譲
- 入力処理テンプレートを使用

### 4. WaitPointHandler簡略化

**ファイル:** `godot/scripts/effects/point_handlers/wait_point_handler.gd`

**変更前:** ~286行
**変更後:** ~179行

- 状態管理を基底クラスに委譲
- メッシュ作成をPointFactoryに委譲
- プレビュー機能は固有ロジックとして維持

### 5. PathExecutionManager統合

**ファイル:** `godot/scripts/systems/path_execution_manager.gd`

移動中パスのポイント管理を統合。

**変更前:**
```gdscript
var _moving_path_wait_points: Dictionary = {}
var _moving_path_vision_points: Dictionary = {}
```

**変更後:**
```gdscript
var _moving_path_points: Dictionary = {}  # { char_id -> { point_type -> Array[MeshInstance3D] } }
```

**統合されたメソッド:**
- `_free_moving_path_points()` - ポイントメッシュ解放
- `_on_point_reached()` - ポイント到達コールバック（統一）

## コード削減量

| ファイル | 変更前 | 変更後 | 削減 |
| :--- | ---: | ---: | ---: |
| VisionPointHandler | ~245行 | ~114行 | ~131行 |
| WaitPointHandler | ~286行 | ~179行 | ~107行 |
| PathExecutionManager | - | - | ~100行 |
| **合計** | - | - | **~338行** |

※PointFactory（183行）を追加しても純減となる

## 技術的な変更点

### 変数名変更

| 旧名 | 新名 | 場所 |
| :--- | :--- | :--- |
| `_is_drawing` | `_is_active` | PointHandlerBase |
| `_vision_meshes` | `_meshes` | VisionPointHandler |
| `_vision_points` | `_points` | VisionPointHandler |
| `_wait_meshes` | `_meshes` | WaitPointHandler |
| `_wait_points` | `_points` | WaitPointHandler |

### シーンツリー追加タイミング

PointFactoryでは `parent` パラメータを受け取り、メッシュ作成時に即座にシーンツリーに追加。
これにより `global_position` へのアクセスが安全になり、`!is_inside_tree()` エラーを防止。

## 後方互換性

- 公開APIに変更なし
- シグナルパターン維持
- データ構造維持

## テスト項目

1. パスを描く → 正常に表示
2. VisionPointを配置 → 正常に表示・方向設定
3. WaitPointを配置 → 正常に表示・時間設定
4. 実行開始 → キャラクター移動開始
5. ポイント通過 → 正しく発火・非表示
6. 移動中に延長パス追加 → 延長ポイント動作確認
7. パス完了 → 全メッシュ解放確認

## 関連ドキュメント

- [PointFactory API](../godot/api/Effect/PointFactory.md)
- [PointHandlerBase API](../godot/api/Effect/PointHandlerBase.md)
- [VisionPoint API](../godot/api/Effect/VisionPoint.md)
- [WaitPoint API](../godot/api/Effect/WaitPoint.md)
