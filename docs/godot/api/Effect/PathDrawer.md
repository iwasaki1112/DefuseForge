# PathDrawer

地面にパスを描画するコンポーネント。マウスドラッグでパスを描き、Slice the Pieパターンで視線ポイントを設定可能。Run区間の設定もサポート。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/effects/path_drawer.gd` |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `drawing_finished` | `points: PackedVector3Array` | パス描画完了時 |
| `vision_point_added` | `anchor: Vector3, target_point: Vector3` | 視線ポイント追加時（target_pointはターゲット地点） |
| `run_segment_added` | `start_ratio: float, end_ratio: float` | Run区間追加時 |
| `clear_point_added` | `path_ratio: float` | Clearポイント追加時 |
| `grenade_point_added` | `path_ratio: float, target_pos: Vector3` | グレネードポイント追加時 |
| `smoke_grenade_point_added` | `path_ratio: float, target_pos: Vector3` | スモークグレネードポイント追加時 |
| `door_point_added` | `path_ratio: float, door: Node3D` | ドアポイント追加時 |
| `wait_point_added` | `path_ratio: float, wait_duration: float` | Waitポイント追加時 |
| `path_undone` | なし | パス描画がUndoされた時 |
| `mode_changed` | `mode: int` | モード変更時（0=MOVEMENT, 1=VISION_POINT, 2=RUN_MARKER, 3=CLEAR_MARKER, 4=GRENADE, 5=DOOR, 6=WAIT, 7=SMOKE_GRENADE） |
| `off_path_tapped` | なし | マーカーモード中にパス外をタップした時（パス確定処理に使用） |

## Enums

### DrawingMode
描画モード。

| 値 | 説明 |
|----|------|
| `MOVEMENT` | 移動パス描画モード |
| `VISION_POINT` | 視線ポイント設定モード |
| `RUN_MARKER` | Runポイント設定モード |
| `CLEAR_MARKER` | Clearポイント設定モード |
| `GRENADE_MARKER` | グレネードポイント設定モード |
| `DOOR_MARKER` | ドアポイント設定モード |
| `WAIT_MARKER` | 待機ポイント設定モード |
| `SMOKE_GRENADE_MARKER` | スモークグレネードポイント設定モード |

### PointType
マーカー種別（Undo履歴用）。

| 値 | 説明 |
|----|------|
| `VISION` | 視線ポイント |
| `RUN` | Run区間 |
| `CLEAR` | Clearポイント |
| `PATH` | パス描画自体 |
| `GRENADE` | グレネードポイント |
| `DOOR` | ドアポイント |
| `PATH_EXTENSION` | パス拡張（Undoで拡張前に戻る） |
| `WAIT` | 待機ポイント |
| `SMOKE_GRENADE` | スモークグレネードポイント |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `min_point_distance` | `float` | `0.2` | ポイント間の最小距離 |
| `line_color` | `Color` | 白(0.9 alpha) | パスライン色 |
| `vision_line_color` | `Color` | 紫(0.9 alpha) | 視線ライン色 |
| `vision_line_length` | `float` | `2.0` | 視線ラインの長さ |
| `line_width` | `float` | `0.04` | ラインの幅 |
| `ground_plane_height` | `float` | `0.0` | 地面の高さ |
| `max_points` | `int` | `500` | 最大ポイント数 |
| `path_click_threshold` | `float` | `0.5` | パスクリック判定距離 |
| `path_endpoint_threshold` | `float` | `0.3` | パス終点タップ検出距離（継続描画用） |
| `wall_collision_mask` | `int` | `2` | 壁検出用のコリジョンマスク |
| `enable_wall_sliding` | `bool` | `true` | 壁沿いの自動スライド機能を有効化 |
| `wall_slide_offset` | `float` | `0.5` | 壁スライド時の壁からのオフセット距離 |
| `enable_smoothing` | `bool` | `true` | パススムージングを有効化 |
| `smoothing_epsilon` | `float` | `0.15` | RDP間引き許容誤差（大きいほど間引き強） |
| `smoothing_segments` | `int` | `4` | Catmull-Rom曲線の分割数（大きいほど滑らか） |

## Public API

### Basic API

#### setup(camera: Camera3D, character: Node3D = null) -> void
PathDrawerをセットアップする。

**引数:**
- `camera` - カメラ（レイキャスト用）
- `character` - 対象キャラクター

#### enable(character: Node3D) -> void
PathDrawerを有効化する。

**引数:**
- `character` - パス追従キャラクター

#### enable_from_point(character: Node3D, start_point: Vector3) -> void
指定した開始点からパス描画を開始する（移動中延長用）。

**引数:**
- `character` - パス追従キャラクター
- `start_point` - パス開始点（キャラクターの現在位置ではなく、この点から描画開始）

#### restore_pending_path(character: Node3D, path_data: Dictionary) -> bool
既存の確定済みパスを読み込んで編集モードに入る。PathExecutionManagerから取得したパスデータを復元する。

**引数:**
- `character` - 対象キャラクター
- `path_data` - PathExecutionManagerから取得したパスデータ

**戻り値:** 復元に成功した場合`true`

**注意:**
- 通常はPathService経由で自動的に呼び出される。直接呼び出す必要はない
- データ配列とメッシュ配列は同期して復元される（Undo操作の整合性を保つため）
- 無効なポイントメッシュがある場合、対応するデータも復元されない
- 復元後に`drawing_finished`シグナルが遅延発火し、`PathModeController`が`path_ready`を通知する

#### disable() -> void
PathDrawerを無効化する。

#### is_enabled() -> bool
有効状態を確認する。

#### clear() -> void
パスと全マーカー（Vision、Run、Clear、Grenade、Door）をすべてクリアする。

#### get_drawn_path() -> PackedVector3Array
描画されたパス（生パス）を取得する。

#### get_smoothed_path() -> PackedVector3Array
スムージング済みの内部パスを取得する。キャラクター移動用。

#### get_relative_path() -> PackedVector3Array
基準位置からの相対パスを取得する。各キャラクターの開始位置にオフセットして使用可能。

**戻り値:** パスの最初のポイントを原点とした相対座標の配列

#### get_relative_vision_points() -> Array[Dictionary]
相対視線ポイントを取得する（アンカー位置とターゲット位置を相対座標に変換）。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "target_point": Vector3 }` の配列（anchor, target_pointは相対座標）

#### is_drawing() -> bool
現在描画中か確認する。

#### is_point_on_path(ground_pos: Vector3) -> bool
指定座標がパス上にあるかどうか判定する。

**引数:**
- `ground_pos` - 地面上の座標

**戻り値:** `path_click_threshold`（0.5m）以内なら`true`

#### is_point_mode() -> bool
マーカーモード（VISION_POINT, RUN_MARKER, CLEAR_MARKER）かどうかを確認する。

**戻り値:** MOVEMENTモード以外なら`true`

### Input Handling Methods (InputController連携)

#### `handle_drawing_press(screen_pos: Vector2) -> void`
描画開始（プレス）処理。InputControllerから呼び出される。

#### `handle_drawing_release() -> void`
描画終了（リリース）処理。

#### `handle_movement_press(screen_pos: Vector2) -> bool`
移動モードでのプレス処理（長押しVisionモード判定用）。
**戻り値:** 長押しモードを開始した場合 `true`

#### `handle_movement_release(screen_pos: Vector2) -> void`
移動モードでのリリース処理。

#### `handle_marker_release(screen_pos: Vector2) -> void`
マーカーモードでのリリース処理。

### Path Extension API

パス終点付近をタップ＆ドラッグして、既存パスの末尾から継続描画する機能。

#### can_extend_path() -> bool
パスの継続描画が可能か確認する。

**戻り値:** 未確定パスが存在し、描画中でなければ`true`

#### is_extending_path() -> bool
継続描画中かどうか確認する。

**戻り値:** 継続描画中なら`true`

**使用例:**
```gdscript
# パス描画後、終点付近をタップすると自動的に継続描画モードに入る
# 継続描画が完了すると、既存マーカーのpath_ratioが自動再計算される

# 手動で継続描画可能かチェック
if path_drawer.can_extend_path():
    print("パス終点をタップして継続描画可能")

# 継続描画中かチェック
if path_drawer.is_extending_path():
    print("継続描画中...")
```

**注意事項:**
- **どのモードでも使用可能**: VISION/RUN/CLEAR等のマーカーモードでも、終点付近タップで継続描画が優先される
- 継続描画中は`is_drawing()`も`true`を返す
- 継続描画完了時、既存マーカーの`path_ratio`は自動再計算される
- 壁に当たった場合は自動的に継続描画が終了する
- `path_endpoint_threshold`（デフォルト0.3m）以内をタップすると継続描画開始

#### set_line_color(color: Color) -> void
ライン色を変更する。

#### set_character_color(color: Color) -> void
キャラクター色を設定する。パス線・VisionPoint・RunPointに適用される。

**引数:**
- `color` - キャラクター固有色

```gdscript
# CharacterColorManagerと連携
var char_color = CharacterColorManager.get_character_color(character)
path_drawer.set_character_color(char_color)
```

#### get_drawing_mode() -> DrawingMode
現在の描画モードを取得する。

### Vision Point API

#### start_vision_mode() -> bool
視線ポイント設定モード（ターゲットポイントモード）に切り替える。
パス上をクリック→ドラッグでターゲット地点を設定する。キャラクターはマーカー到達後、移動しながらターゲット地点を見続ける。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### start_movement_mode() -> void
移動パス描画モードに戻る。

#### has_vision_points() -> bool
視線ポイントがあるか確認する。

#### get_vision_points() -> Array[Dictionary]
視線ポイントを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "target_point": Vector3 }` の配列

#### get_vision_point_count() -> int
視線ポイント数を取得する。

#### remove_last_vision_point() -> void
最後の視線ポイントを削除する。

#### take_vision_points() -> Array[MeshInstance3D]
視線ポイントの所有権を移譲する（呼び出し元が管理責任を持つ）。

### Run Marker API

#### start_run_mode() -> bool
Runポイント設定モードに切り替える。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### has_run_segments() -> bool
Run区間があるか確認する。

#### get_run_segments() -> Array[Dictionary]
Run区間を取得する。

**戻り値:** `{ "start_ratio": float, "end_ratio": float }` の配列

#### get_run_segment_count() -> int
Run区間数を取得する。

#### remove_last_run_segment() -> void
最後のRun区間を削除する。未完成の開始点がある場合はそれを削除。

#### has_incomplete_run_start() -> bool
未完成のRun開始点があるか確認する。

#### take_run_points() -> Array[MeshInstance3D]
Runポイントの所有権を移譲する（呼び出し元が管理責任を持つ）。

### Clear Marker API

#### start_clear_mode() -> bool
Clearポイント設定モードに切り替える。パス上をクリックでClearポイントを設定する。このポイント以降はVision/Runがクリアされ、キャラクターは進行方向を向く。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### has_clear_points() -> bool
Clearポイントがあるか確認する。

#### get_clear_points() -> Array[Dictionary]
Clearポイントを取得する。

**戻り値:** `{ "path_ratio": float }` の配列

#### get_clear_point_count() -> int
Clearポイント数を取得する。

#### remove_last_clear_point() -> void
最後のClearポイントを削除する。

#### take_clear_points() -> Array[MeshInstance3D]
Clearポイントの所有権を移譲する（呼び出し元が管理責任を持つ）。

### Unified Undo API

#### undo_last_point() -> int
最後に追加したポイントを種別を問わず削除する（統一Undo）。

**戻り値:** 削除したマーカーの種別（PointType）。何も削除しなかった場合は`-1`

```gdscript
# 使用例
var removed_type = path_drawer.undo_last_point()
match removed_type:
    PathDrawer.PointType.VISION:
        print("Vision marker removed")
    PathDrawer.PointType.RUN:
        print("Run marker removed")
    PathDrawer.PointType.CLEAR:
        print("Clear marker removed")
    PathDrawer.PointType.PATH:
        print("Path removed - back to initial state")
    -1:
        print("Nothing to undo")
```

PATHがUndoされると、パスとすべてのマーカーがクリアされ、`path_undone`シグナルが発火されます。PathServiceはこのシグナルを受けてマーカーパネルを非表示にしつつ、PathDrawerを再度有効化するため、ユーザーは新しいパスを描き直すことができます。

### キャラクター管理 API

#### set_active_edit_character(character: Node) -> void
編集対象キャラクターを設定する。

**引数:**
- `character` - 編集対象キャラクター

#### get_active_edit_character() -> Node
現在の編集対象キャラクターを取得する。

### Grenade Marker API

#### start_grenade_mode() -> bool
グレネードポイント設定モードに切り替える。パス上をクリック→ドラッグでグレネード投擲位置と目標を設定。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### has_grenade_points() -> bool
グレネードポイントがあるか確認する。

#### get_grenade_points() -> Array[Dictionary]
グレネードポイントを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "target_pos": Vector3, "bounce_point": Vector3 }` の配列

#### take_grenade_points() -> Array[MeshInstance3D]
グレネードポイントの所有権を移譲する。

### Smoke Grenade Marker API

#### start_smoke_grenade_mode() -> bool
スモークグレネードポイント設定モードに切り替える。パス上をクリック→ドラッグでスモークグレネード投擲位置と目標を設定。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### has_smoke_grenade_points() -> bool
スモークグレネードポイントがあるか確認する。

#### get_smoke_grenade_points() -> Array[Dictionary]
スモークグレネードポイントを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "target_pos": Vector3 }` の配列

#### get_smoke_grenade_point_count() -> int
スモークグレネードポイント数を取得する。

#### take_smoke_grenade_points() -> Array[MeshInstance3D]
スモークグレネードポイントの所有権を移譲する。

#### get_all_smoke_grenade_points() -> Dictionary
全キャラクターのスモークグレネードポイントを取得する。

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとしたスモークグレネードポイントの辞書

#### take_all_smoke_grenade_points() -> Dictionary
全キャラクターのスモークグレネードポイントの所有権を移譲する。

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

### Door Marker API

#### start_door_mode() -> bool
ドアポイント設定モードに切り替える。ドアをクリックしてキック位置を設定。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### has_door_points() -> bool
ドアポイントがあるか確認する。

#### get_door_points() -> Array[Dictionary]
ドアポイントを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "door_node": Node3D }` の配列

#### take_door_points() -> Array[MeshInstance3D]
ドアポイントの所有権を移譲する。

### Wait Marker API

#### start_wait_mode() -> bool
待機ポイント設定モードに切り替える。パス上を長押しして待機位置と待機時間を設定。長押し時間が待機時間になる。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

**動作:**
- タッチ/クリック開始で時刻記録
- 長押し中はプレビューマーカーが表示され、リアルタイムで待機時間が更新
- 指を離すと経過時間が待機時間として確定
- 最小待機時間: 0.5秒（これ未満はキャンセル扱い）
- 最大待機時間: 10.0秒

#### has_wait_points() -> bool
Waitポイントがあるか確認する。

#### get_wait_points() -> Array[Dictionary]
Waitポイントを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "wait_duration": float }` の配列

#### get_wait_point_count() -> int
Waitポイント数を取得する。

#### take_wait_points() -> Array[MeshInstance3D]
Waitポイントの所有権を移譲する。

#### get_wait_point_count_for_character(character: Node) -> int
指定キャラクターのWaitポイント数を取得する。

#### get_all_wait_points() -> Dictionary
全キャラクターのWaitポイントを取得する。

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとしたWaitポイントの辞書

#### take_all_wait_points() -> Dictionary
全キャラクターのWaitポイントの所有権を移譲する。

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

### Unified Marker API (新システム)

ポイントタイプを問わず統一的にアクセスするためのAPI。`ActionPointData.Type`列挙型を使用する。

#### get_markers_by_type(point_type: ActionPointData.Type) -> Array[Dictionary]
アクティブキャラクターの指定タイプのポイントデータを取得する。

**引数:**
- `point_type` - `ActionPointData.Type`の値（VISION, CLEAR, RUN, GRENADE, DOOR）

**戻り値:** 指定タイプのポイントデータ配列

#### take_markers_by_type(point_type: ActionPointData.Type) -> Array[MeshInstance3D]
アクティブキャラクターの指定タイプのポイントメッシュを取得して所有権を移譲する。

**引数:**
- `point_type` - `ActionPointData.Type`の値

**戻り値:** ポイントメッシュ配列

#### get_all_markers_by_type(point_type: ActionPointData.Type) -> Dictionary
全キャラクターの指定タイプのポイントデータを取得する。

**引数:**
- `point_type` - `ActionPointData.Type`の値

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとしたポイントデータの辞書

#### take_all_markers_by_type(point_type: ActionPointData.Type) -> Dictionary
全キャラクターの指定タイプのポイントメッシュを取得して所有権を移譲する。

**引数:**
- `point_type` - `ActionPointData.Type`の値

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

#### get_all_point_types_data() -> Dictionary
全タイプのポイントデータを一括取得する。

**戻り値:** `{ ActionPointData.Type: Array[Dictionary] }`

#### take_all_point_types_meshes() -> Dictionary
全タイプのポイントメッシュを一括取得して所有権を移譲する。

**戻り値:** `{ ActionPointData.Type: Array[MeshInstance3D] }`

### Execution API

#### execute(run: bool = false) -> bool
パスを実行する（キャラクターに`set_path`を呼び出す）。

**引数:**
- `run` - 走行モードで実行するか

**戻り値:** 成功なら`true`

#### execute_with_vision(run: bool = false) -> bool
視線ポイント付きでパスを実行する。

**引数:**
- `run` - 走行モードで実行するか

**戻り値:** 成功なら`true`

#### has_pending_path() -> bool
未実行のパスがあるか確認する。

#### clear_pending() -> void
未実行のパスをクリアする。

## 使用例

```gdscript
# セットアップ
var path_drawer = PathDrawer.new()
add_child(path_drawer)
path_drawer.setup(camera, character)

# 有効化
path_drawer.enable(character)

# シグナル接続
path_drawer.drawing_finished.connect(_on_path_finished)
path_drawer.vision_point_added.connect(_on_vision_added)
path_drawer.run_segment_added.connect(_on_run_added)

# 視線モードに切り替え
if path_drawer.start_vision_mode():
    print("Now in vision mode")

# Runポイントモードに切り替え
if path_drawer.start_run_mode():
    print("Now in run marker mode")
    # パス上をクリックして開始点、再度クリックして終点を設置

# Clearポイントモードに切り替え
if path_drawer.start_clear_mode():
    print("Now in clear marker mode")
    # パス上をクリックでClearポイントを設置
    # このポイント以降は視線・Run効果がリセットされる

# パス実行
path_drawer.execute_with_vision(false)  # 歩行で実行（Run区間だけ走る）
```

## データ形式

### 視線ポイント（ターゲットポイントモード）
```gdscript
{
    "path_ratio": 0.5,      # パス上の位置（0.0〜1.0）
    "anchor": Vector3(...), # アンカー位置（マーカーの位置）
    "target_point": Vector3(...)  # ターゲット地点（キャラクターが見続ける位置）
}
```

キャラクターはマーカー到達後、`target_point`を動的に見続ける。移動中も常に`target_point`への方向を計算し直す。

### Run区間
```gdscript
{
    "start_ratio": 0.3,  # 開始位置（0.0〜1.0）
    "end_ratio": 0.6     # 終了位置（0.0〜1.0）
}
```

### Clearポイント
```gdscript
{
    "path_ratio": 0.7    # パス上の位置（0.0〜1.0）
}
```

このポイントに到達すると、現在の視線方向とRun状態がリセットされ、キャラクターは進行方向を向く。

### Waitポイント
```gdscript
{
    "path_ratio": 0.6,       # パス上の位置（0.0〜1.0）
    "anchor": Vector3(...),  # アンカー位置
    "wait_duration": 3.0     # 待機時間（秒）
}
```

このポイントに到達すると、キャラクターは指定時間アイドル待機し、待機完了後にパス追従を再開する。

## 内部動作

- `PathLineMesh`でパスを描画（破線+終点ドーナツ）
- `VisionPoint`で視線ポイントを可視化
- `RunPoint`でRun区間の開始/終点を可視化
- `ClearPoint`でClearポイントを可視化（リセットマーカー）
- `WaitPoint`で待機ポイントを可視化（砂時計アイコン）
- パス上クリックで最近接点を計算し、そこから視線方向やRun区間、Clearポイント、待機ポイントを設定
- **パススムージング**: 描画完了時に`PathSmoother`で手ブレを補正

## パススムージング

描画完了時に手描きパスの手ブレを滑らかにする。

### 処理フロー
1. **RDP間引き**: Ramer-Douglas-Peucker法で不要ポイントを削除
2. **Catmull-Rom補間**: 残ったポイントを滑らかな曲線で補間

### パラメータ調整

| パラメータ | 推奨範囲 | 効果 |
|-----------|----------|------|
| `smoothing_epsilon` | 0.1〜0.3m | 大きいほど間引きが強く、パスが単純化 |
| `smoothing_segments` | 3〜6 | 大きいほど滑らかだが、ポイント数が増加 |

```gdscript
# スムージングを無効化
path_drawer.enable_smoothing = false

# カスタム設定
path_drawer.smoothing_epsilon = 0.2  # 強めの間引き
path_drawer.smoothing_segments = 5   # より滑らかな曲線
```

### 備考
- 表示パスは生パス（手描きのまま）、内部パスのみスムージングが適用される
- キャラクターはスムージング後の滑らかなパスを歩く
- 視線ポイント・Run区間はスムージング後のパスを基準に設定される
- 3ポイント未満のパスではスムージングはスキップされる

詳細は [PathSmoother](PathSmoother.md) を参照。

## 障害物（壁）検出と壁沿いスライド

パス描画中に障害物を貫通しないよう、以下のチェックと補正を行う:

1. **壁検出 (Wall Detection)**:
    - 描画開始時: キャラクター位置→開始点間に壁があれば描画開始を拒否
    - ポイント追加時: 直前のポイント→新ポイント間に壁があれば検出

2. **壁沿いスライド (Wall Sliding)**:
    - `enable_wall_sliding` が `true` の場合、壁に当たると自動的に「壁沿いモード」に移行
    - ユーザーが壁に向かってドラッグし続けても、パスは壁に沿って滑らかに伸びる
    - 壁の角（コーナー）を検出すると、自動的に角を曲がって描画を継続
    - `wall_slide_offset` だけ壁から離れた位置にパスポイントを生成し、キャラクターが壁に埋まるのを防ぐ

3. **壁手前停止**:
    - スライドが無効または不可能な場合、壁の直前でパス描画が停止する

壁検出は`wall_collision_mask`で指定されたコリジョンレイヤーを対象とする（デフォルト: レイヤー2）。

```gdscript
# 壁検出を別のレイヤーに変更する場合
path_drawer.wall_collision_mask = 4  # レイヤー3を使用
```

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `drawing_finished` | `points: PackedVector3Array` |
| `vision_point_added` | `anchor: Vector3, target_point: Vector3` |
| `run_segment_added` | `start_ratio: float, end_ratio: float` |
| `clear_point_added` | `path_ratio: float` |
| `grenade_point_added` | `path_ratio: float, target_pos: Vector3` |
| `smoke_grenade_point_added` | `path_ratio: float, target_pos: Vector3` |
| `door_point_added` | `path_ratio: float, door: Node3D` |
| `wait_point_added` | `path_ratio: float, wait_duration: float` |
| `path_undone` | なし |
| `mode_changed` | `mode: int` |
| `off_path_tapped` | なし |

### メソッド
- `setup(camera: Camera3D, character: Node3D = null) -> void`
- `clear() -> void`
- `take_vision_points() -> Array[MeshInstance3D]`
- `take_run_points() -> Array[MeshInstance3D]`
- `take_clear_points() -> Array[MeshInstance3D]`
- `get_drawn_path() -> PackedVector3Array`
- `get_smoothed_path() -> PackedVector3Array`
- `get_relative_path() -> PackedVector3Array`
- `get_relative_vision_points() -> Array[Dictionary]`
- `is_drawing() -> bool`
- `is_point_on_path(ground_pos: Vector3) -> bool`
- `is_point_mode() -> bool`
- `can_extend_path() -> bool`
- `is_extending_path() -> bool`
- `set_line_color(color: Color) -> void`
- `set_character_color(color: Color) -> void`
- `enable(character: Node3D) -> void`
- `enable_from_point(character: Node3D, start_point: Vector3) -> void`
- `restore_pending_path(character: Node3D, path_data: Dictionary) -> bool`
- `disable() -> void`
- `is_enabled() -> bool`
- `get_drawing_mode() -> DrawingMode`
- `start_vision_mode() -> bool`
- `start_movement_mode() -> void`
- `has_vision_points() -> bool`
- `get_vision_points() -> Array[Dictionary]`
- `get_vision_point_count() -> int`
- `remove_last_vision_point() -> void`
- `start_run_mode() -> bool`
- `has_run_segments() -> bool`
- `get_run_segments() -> Array[Dictionary]`
- `get_run_segment_count() -> int`
- `remove_last_run_segment() -> void`
- `has_incomplete_run_start() -> bool`
- `start_clear_mode() -> bool`
- `has_clear_points() -> bool`
- `get_clear_points() -> Array[Dictionary]`
- `get_clear_point_count() -> int`
- `remove_last_clear_point() -> void`
- `undo_last_point() -> int`
- `execute(run: bool = false) -> bool`
- `execute_with_vision(run: bool = false) -> bool`
- `has_pending_path() -> bool`
- `clear_pending() -> void`
- `set_active_edit_character(character: Node) -> void`
- `get_active_edit_character() -> Node`
- `start_grenade_mode() -> bool`
- `has_grenade_points() -> bool`
- `get_grenade_points() -> Array[Dictionary]`
- `take_grenade_points() -> Array[MeshInstance3D]`
- `start_smoke_grenade_mode() -> bool`
- `has_smoke_grenade_points() -> bool`
- `get_smoke_grenade_points() -> Array[Dictionary]`
- `get_smoke_grenade_point_count() -> int`
- `take_smoke_grenade_points() -> Array[MeshInstance3D]`
- `get_all_smoke_grenade_points() -> Dictionary`
- `take_all_smoke_grenade_points() -> Dictionary`
- `start_door_mode() -> bool`
- `has_door_points() -> bool`
- `get_door_points() -> Array[Dictionary]`
- `take_door_points() -> Array[MeshInstance3D]`
- `start_wait_mode() -> bool`
- `has_wait_points() -> bool`
- `get_wait_points() -> Array[Dictionary]`
- `get_wait_point_count() -> int`
- `take_wait_points() -> Array[MeshInstance3D]`
- `get_wait_point_count_for_character(character: Node) -> int`
- `get_all_wait_points() -> Dictionary`
- `take_all_wait_points() -> Dictionary`
- `get_markers_by_type(point_type: ActionPointData.Type) -> Array[Dictionary]`
- `take_markers_by_type(point_type: ActionPointData.Type) -> Array[MeshInstance3D]`
- `get_all_markers_by_type(point_type: ActionPointData.Type) -> Dictionary`
- `take_all_markers_by_type(point_type: ActionPointData.Type) -> Dictionary`
- `get_all_point_types_data() -> Dictionary`
- `take_all_point_types_meshes() -> Dictionary`

## アーキテクチャ

PathDrawerは単一責任原則に従って責務分離された複数のヘルパークラスで構成されている。

### クラス構成

```
godot/scripts/effects/
├── path_drawer.gd                      # ファサード（Public API提供）
├── path_state.gd                       # パス状態管理
├── path_calculator.gd                  # パス計算ユーティリティ（静的メソッド）
├── path_raycast_helper.gd              # レイキャスト・壁検出（静的メソッド）
├── path_input_handler.gd               # 入力処理統括
├── marker_handler_base.gd              # ポイントハンドラ基底クラス
└── marker_handlers/                    # ポイントハンドラ実装
    ├── vision_point_handler.gd        # 視線ポイント
    ├── run_point_handler.gd           # Runポイント
    ├── clear_point_handler.gd         # Clearポイント
    ├── grenade_point_handler.gd       # グレネードポイント
    ├── smoke_grenade_point_handler.gd # スモークグレネードポイント
    ├── door_point_handler.gd          # ドアポイント
    └── wait_point_handler.gd          # Waitポイント
```

### PathCalculator

パス上の最近点検索、オフセット計算などの純粋な計算処理を提供する静的クラス。

| メソッド | 説明 |
|---------|------|
| `find_closest_point_on_path()` | パス上で最も近い点を検索 |
| `find_offset_point_on_path()` | 指定比率からオフセットした点を検索 |
| `calculate_path_length()` | パスの総距離を計算 |
| `get_point_at_ratio()` | 指定比率のパス上位置を取得 |
| `get_path_endpoint()` | パス終点を取得 |
| `is_near_path_endpoint()` | 終点付近かどうか判定 |

### PathRaycastHelper

壁検出、ドア検出などのレイキャスト処理を提供する静的クラス。

| メソッド | 説明 |
|---------|------|
| `check_wall_between()` | 2点間の壁検出（ドアは除外） |
| `raycast_wall_or_floor()` | 壁または床へのレイキャスト |
| `raycast_door()` | ドアをレイキャストで検出 |
| `get_ground_position()` | 地面平面との交点を取得 |
| `is_wall_hit()` | ヒット結果が壁かどうか判定 |

### PointHandlerBase

各マーカー種別のハンドラの共通機能を提供する基底クラス。

| メソッド | 説明 |
|---------|------|
| `handle_input()` | 入力処理（子クラスでオーバーライド） |
| `create_marker()` | マーカー作成 |
| `undo_last()` | 最後のマーカーをUndo |
| `clear_all()` | 全マーカーをクリア |
| `get_markers()` | ポイントデータを取得 |
| `take_markers()` | ポイントメッシュの所有権を移譲 |

### PathInputHandler

入力処理を統括し、描画モードに応じて適切なポイントハンドラに委譲する。

```gdscript
# 使用例（内部実装）
var input_handler = PathInputHandler.new()
input_handler.setup(path_drawer, camera)

# モードに応じた入力処理
input_handler.handle_input(event, DrawingMode.VISION_POINT)
```

## 関連クラス

- `ActionPoint` - アクションポイントの基底クラス
- `ActionPointData` - ポイントデータの統一基底クラス
- `PointCollection` - マーカーの統一管理コレクション
- `VisionPoint` - 視線ポイント（ActionPoint継承）
- `ClearPoint` - クリアポイント（ActionPoint継承）
- `RunPoint` - ダッシュポイント（ActionPoint継承）
- `GrenadePoint` - グレネードポイント（ActionPoint継承）
- `DoorPoint` - ドアポイント（ActionPoint継承）
- `WaitPoint` - 待機ポイント（ActionPoint継承）
- `PathLineMesh` - パス描画メッシュ
- `PathSmoother` - パススムージング
- `PathCalculator` - パス計算ユーティリティ
- `PathRaycastHelper` - レイキャストユーティリティ
- `PathInputHandler` - 入力処理統括
- `PointHandlerBase` - ポイントハンドラ基底クラス
