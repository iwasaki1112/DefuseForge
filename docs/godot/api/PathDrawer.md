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
| `grenade_marker_added` | `path_ratio: float, target_pos: Vector3` | グレネードマーカー追加時 |
| `door_marker_added` | `path_ratio: float, door: Node3D` | ドアマーカー追加時 |
| `wait_marker_added` | `path_ratio: float, wait_duration: float` | Waitマーカー追加時 |
| `path_undone` | なし | パス描画がUndoされた時 |
| `mode_changed` | `mode: int` | モード変更時（0=MOVEMENT, 1=VISION_POINT, 2=RUN_MARKER, 3=CLEAR_MARKER, 4=GRENADE, 5=DOOR, 6=WAIT） |

## Enums

### DrawingMode
描画モード。

| 値 | 説明 |
|----|------|
| `MOVEMENT` | 移動パス描画モード |
| `VISION_POINT` | 視線ポイント設定モード |
| `RUN_MARKER` | Runマーカー設定モード |
| `CLEAR_MARKER` | Clearマーカー設定モード |
| `GRENADE_MARKER` | グレネードマーカー設定モード |
| `DOOR_MARKER` | ドアマーカー設定モード |
| `WAIT_MARKER` | 待機マーカー設定モード |

### MarkerType
マーカー種別（Undo履歴用）。

| 値 | 説明 |
|----|------|
| `VISION` | 視線ポイント |
| `RUN` | Run区間 |
| `CLEAR` | Clearポイント |
| `PATH` | パス描画自体 |
| `GRENADE` | グレネードマーカー |
| `DOOR` | ドアマーカー |
| `WAIT` | 待機マーカー |
| `PATH_EXTENSION` | パス拡張（Undoで拡張前に戻る） |

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

#### restore_pending_path(character: Node3D, path_data: Dictionary) -> bool
既存の確定済みパスを読み込んで編集モードに入る。PathExecutionManagerから取得したパスデータを復元する。

**引数:**
- `character` - 対象キャラクター
- `path_data` - PathExecutionManagerから取得したパスデータ

**戻り値:** 復元に成功した場合`true`

**注意:**
- 通常はPathService経由で自動的に呼び出される。直接呼び出す必要はない
- データ配列とメッシュ配列は同期して復元される（Undo操作の整合性を保つため）
- 無効なマーカーメッシュがある場合、対応するデータも復元されない
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

#### is_marker_mode() -> bool
マーカーモード（VISION_POINT, RUN_MARKER, CLEAR_MARKER）かどうかを確認する。

**戻り値:** MOVEMENTモード以外なら`true`

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
キャラクター色を設定する。パス線・VisionMarker・RunMarkerに適用される。

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

#### take_vision_markers() -> Array[MeshInstance3D]
視線マーカーの所有権を移譲する（呼び出し元が管理責任を持つ）。

### Run Marker API

#### start_run_mode() -> bool
Runマーカー設定モードに切り替える。

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

#### take_run_markers() -> Array[MeshInstance3D]
Runマーカーの所有権を移譲する（呼び出し元が管理責任を持つ）。

### Clear Marker API

#### start_clear_mode() -> bool
Clearマーカー設定モードに切り替える。パス上をクリックでClearポイントを設定する。このポイント以降はVision/Runがクリアされ、キャラクターは進行方向を向く。

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

#### take_clear_markers() -> Array[MeshInstance3D]
Clearマーカーの所有権を移譲する（呼び出し元が管理責任を持つ）。

### Unified Undo API

#### undo_last_marker() -> int
最後に追加したマーカーを種別を問わず削除する（統一Undo）。

**戻り値:** 削除したマーカーの種別（MarkerType）。何も削除しなかった場合は`-1`

```gdscript
# 使用例
var removed_type = path_drawer.undo_last_marker()
match removed_type:
    PathDrawer.MarkerType.VISION:
        print("Vision marker removed")
    PathDrawer.MarkerType.RUN:
        print("Run marker removed")
    PathDrawer.MarkerType.CLEAR:
        print("Clear marker removed")
    PathDrawer.MarkerType.PATH:
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
グレネードマーカー設定モードに切り替える。パス上をクリック→ドラッグでグレネード投擲位置と目標を設定。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### has_grenade_markers() -> bool
グレネードマーカーがあるか確認する。

#### get_grenade_markers() -> Array[Dictionary]
グレネードマーカーを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "target_pos": Vector3, "bounce_point": Vector3 }` の配列

#### take_grenade_markers() -> Array[MeshInstance3D]
グレネードマーカーの所有権を移譲する。

### Door Marker API

#### start_door_mode() -> bool
ドアマーカー設定モードに切り替える。ドアをクリックしてキック位置を設定。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### has_door_markers() -> bool
ドアマーカーがあるか確認する。

#### get_door_markers() -> Array[Dictionary]
ドアマーカーを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "door_node": Node3D }` の配列

#### take_door_markers() -> Array[MeshInstance3D]
ドアマーカーの所有権を移譲する。

### Wait Marker API

#### start_wait_mode() -> bool
待機マーカー設定モードに切り替える。パス上を長押しして待機位置と待機時間を設定。長押し時間が待機時間になる。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

**動作:**
- タッチ/クリック開始で時刻記録
- 長押し中はプレビューマーカーが表示され、リアルタイムで待機時間が更新
- 指を離すと経過時間が待機時間として確定
- 最小待機時間: 0.5秒（これ未満はキャンセル扱い）
- 最大待機時間: 10.0秒

#### has_wait_markers() -> bool
Waitマーカーがあるか確認する。

#### get_wait_markers() -> Array[Dictionary]
Waitマーカーを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "wait_duration": float }` の配列

#### get_wait_marker_count() -> int
Waitマーカー数を取得する。

#### take_wait_markers() -> Array[MeshInstance3D]
Waitマーカーの所有権を移譲する。

#### get_wait_marker_count_for_character(character: Node) -> int
指定キャラクターのWaitマーカー数を取得する。

#### get_all_wait_markers() -> Dictionary
全キャラクターのWaitマーカーを取得する。

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとしたWaitマーカーの辞書

#### take_all_wait_markers() -> Dictionary
全キャラクターのWaitマーカーの所有権を移譲する。

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

### Unified Marker API (新システム)

マーカータイプを問わず統一的にアクセスするためのAPI。`ActionMarkerData.Type`列挙型を使用する。

#### get_markers_by_type(marker_type: ActionMarkerData.Type) -> Array[Dictionary]
アクティブキャラクターの指定タイプのマーカーデータを取得する。

**引数:**
- `marker_type` - `ActionMarkerData.Type`の値（VISION, CLEAR, RUN, GRENADE, DOOR）

**戻り値:** 指定タイプのマーカーデータ配列

#### take_markers_by_type(marker_type: ActionMarkerData.Type) -> Array[MeshInstance3D]
アクティブキャラクターの指定タイプのマーカーメッシュを取得して所有権を移譲する。

**引数:**
- `marker_type` - `ActionMarkerData.Type`の値

**戻り値:** マーカーメッシュ配列

#### get_all_markers_by_type(marker_type: ActionMarkerData.Type) -> Dictionary
全キャラクターの指定タイプのマーカーデータを取得する。

**引数:**
- `marker_type` - `ActionMarkerData.Type`の値

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとしたマーカーデータの辞書

#### take_all_markers_by_type(marker_type: ActionMarkerData.Type) -> Dictionary
全キャラクターの指定タイプのマーカーメッシュを取得して所有権を移譲する。

**引数:**
- `marker_type` - `ActionMarkerData.Type`の値

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

#### get_all_marker_types_data() -> Dictionary
全タイプのマーカーデータを一括取得する。

**戻り値:** `{ ActionMarkerData.Type: Array[Dictionary] }`

#### take_all_marker_types_meshes() -> Dictionary
全タイプのマーカーメッシュを一括取得して所有権を移譲する。

**戻り値:** `{ ActionMarkerData.Type: Array[MeshInstance3D] }`

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

# Runマーカーモードに切り替え
if path_drawer.start_run_mode():
    print("Now in run marker mode")
    # パス上をクリックして開始点、再度クリックして終点を設置

# Clearマーカーモードに切り替え
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
- `VisionMarker`で視線ポイントを可視化
- `RunMarker`でRun区間の開始/終点を可視化
- `ClearMarker`でClearポイントを可視化（リセットマーカー）
- `WaitMarker`で待機ポイントを可視化（砂時計アイコン）
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

## 障害物（壁）検出

パス描画中に障害物を貫通しないよう、以下のレイキャストチェックを行う:

1. **描画開始時**: キャラクター位置→開始点間に壁があれば描画開始を拒否
2. **ポイント追加時**: 直前のポイント→新ポイント間に壁があれば、壁直前で停止して描画終了

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
| `mode_changed` | `mode: int` |
| `run_segment_added` | `start_ratio: float, end_ratio: float` |
| `clear_point_added` | `path_ratio: float` |
| `wait_marker_added` | `path_ratio: float, wait_duration: float` |
| `path_undone` | なし |

### メソッド
- `setup(camera: Camera3D, character: Node3D = null) -> void`
- `clear() -> void`
- `take_vision_markers() -> Array[MeshInstance3D]`
- `take_run_markers() -> Array[MeshInstance3D]`
- `take_clear_markers() -> Array[MeshInstance3D]`
- `get_drawn_path() -> PackedVector3Array`
- `get_smoothed_path() -> PackedVector3Array`
- `get_relative_path() -> PackedVector3Array`
- `get_relative_vision_points() -> Array[Dictionary]`
- `is_drawing() -> bool`
- `is_point_on_path(ground_pos: Vector3) -> bool`
- `is_marker_mode() -> bool`
- `can_extend_path() -> bool`
- `is_extending_path() -> bool`
- `set_line_color(color: Color) -> void`
- `set_character_color(color: Color) -> void`
- `enable(character: Node3D) -> void`
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
- `undo_last_marker() -> int`
- `execute(run: bool = false) -> bool`
- `execute_with_vision(run: bool = false) -> bool`
- `has_pending_path() -> bool`
- `clear_pending() -> void`
- `set_active_edit_character(character: Node) -> void`
- `get_active_edit_character() -> Node`
- `start_grenade_mode() -> bool`
- `has_grenade_markers() -> bool`
- `get_grenade_markers() -> Array[Dictionary]`
- `take_grenade_markers() -> Array[MeshInstance3D]`
- `start_door_mode() -> bool`
- `has_door_markers() -> bool`
- `get_door_markers() -> Array[Dictionary]`
- `take_door_markers() -> Array[MeshInstance3D]`
- `start_wait_mode() -> bool`
- `has_wait_markers() -> bool`
- `get_wait_markers() -> Array[Dictionary]`
- `get_wait_marker_count() -> int`
- `take_wait_markers() -> Array[MeshInstance3D]`
- `get_wait_marker_count_for_character(character: Node) -> int`
- `get_all_wait_markers() -> Dictionary`
- `take_all_wait_markers() -> Dictionary`
- `get_markers_by_type(marker_type: ActionMarkerData.Type) -> Array[Dictionary]`
- `take_markers_by_type(marker_type: ActionMarkerData.Type) -> Array[MeshInstance3D]`
- `get_all_markers_by_type(marker_type: ActionMarkerData.Type) -> Dictionary`
- `take_all_markers_by_type(marker_type: ActionMarkerData.Type) -> Dictionary`
- `get_all_marker_types_data() -> Dictionary`
- `take_all_marker_types_meshes() -> Dictionary`

## アーキテクチャ

PathDrawerは単一責任原則に従って責務分離された複数のヘルパークラスで構成されている。

### クラス構成

```
godot/scripts/effects/
├── path_drawer.gd                    # ファサード（Public API提供）
├── path_state.gd                     # パス状態管理
├── path_calculator.gd                # パス計算ユーティリティ（静的メソッド）
├── path_raycast_helper.gd            # レイキャスト・壁検出（静的メソッド）
├── path_input_handler.gd             # 入力処理統括
├── marker_handler_base.gd            # マーカーハンドラ基底クラス
└── marker_handlers/                  # マーカーハンドラ実装
    ├── vision_marker_handler.gd      # 視線マーカー
    ├── run_marker_handler.gd         # Runマーカー
    ├── clear_marker_handler.gd       # Clearマーカー
    ├── grenade_marker_handler.gd     # グレネードマーカー
    ├── smoke_grenade_marker_handler.gd # スモークグレネードマーカー
    ├── door_marker_handler.gd        # ドアマーカー
    └── wait_marker_handler.gd        # Waitマーカー
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

### MarkerHandlerBase

各マーカー種別のハンドラの共通機能を提供する基底クラス。

| メソッド | 説明 |
|---------|------|
| `handle_input()` | 入力処理（子クラスでオーバーライド） |
| `create_marker()` | マーカー作成 |
| `undo_last()` | 最後のマーカーをUndo |
| `clear_all()` | 全マーカーをクリア |
| `get_markers()` | マーカーデータを取得 |
| `take_markers()` | マーカーメッシュの所有権を移譲 |

### PathInputHandler

入力処理を統括し、描画モードに応じて適切なマーカーハンドラに委譲する。

```gdscript
# 使用例（内部実装）
var input_handler = PathInputHandler.new()
input_handler.setup(path_drawer, camera)

# モードに応じた入力処理
input_handler.handle_input(event, DrawingMode.VISION_POINT)
```

## 関連クラス

- `ActionMarker` - アクションマーカーの基底クラス
- `ActionMarkerData` - マーカーデータの統一基底クラス
- `MarkerCollection` - マーカーの統一管理コレクション
- `VisionMarker` - 視線マーカー（ActionMarker継承）
- `ClearMarker` - クリアマーカー（ActionMarker継承）
- `RunMarker` - ダッシュマーカー（ActionMarker継承）
- `GrenadeMarker` - グレネードマーカー（ActionMarker継承）
- `DoorMarker` - ドアマーカー（ActionMarker継承）
- `WaitMarker` - 待機マーカー（ActionMarker継承）
- `PathLineMesh` - パス描画メッシュ
- `PathSmoother` - パススムージング
- `PathCalculator` - パス計算ユーティリティ
- `PathRaycastHelper` - レイキャストユーティリティ
- `PathInputHandler` - 入力処理統括
- `MarkerHandlerBase` - マーカーハンドラ基底クラス
