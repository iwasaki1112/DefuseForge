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
| `mode_changed` | `mode: int` | モード変更時（0=MOVEMENT, 1=VISION_POINT, 2=RUN_MARKER, 3=CLEAR_MARKER） |

## Enums

### DrawingMode
描画モード。

| 値 | 説明 |
|----|------|
| `MOVEMENT` | 移動パス描画モード |
| `VISION_POINT` | 視線ポイント設定モード |
| `RUN_MARKER` | Runマーカー設定モード |
| `CLEAR_MARKER` | Clearマーカー設定モード |

### MarkerType
マーカー種別（Undo履歴用）。

| 値 | 説明 |
|----|------|
| `VISION` | 視線ポイント |
| `RUN` | Run区間 |
| `CLEAR` | Clearポイント |

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

#### disable() -> void
PathDrawerを無効化する。

#### is_enabled() -> bool
有効状態を確認する。

#### clear() -> void
パスと視線ポイントとRunマーカーとClearマーカーをすべてクリアする。

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
    -1:
        print("Nothing to undo")
```

### Multi-Character Mode API

マルチセレクト時に各キャラクターに個別のマーカーを設定できるモード。

#### start_multi_character_mode(characters: Array[Node]) -> void
マルチキャラクターモードを開始する。

**引数:**
- `characters` - 対象キャラクター配列

**動作:**
- 各キャラクター用のマーカーストレージを初期化
- 最初のキャラクターをアクティブに設定

#### end_multi_character_mode() -> void
マルチキャラクターモードを終了する。

#### set_active_edit_character(character: Node) -> void
編集対象キャラクターを設定する。マルチモードでキャラクター間を切り替える際に使用。

**引数:**
- `character` - 編集対象キャラクター

#### get_active_edit_character() -> Node
現在の編集対象キャラクターを取得する。

#### is_multi_character_mode() -> bool
マルチキャラクターモードかどうかを確認する。

#### get_vision_point_count_for_character(character: Node) -> int
指定キャラクターの視線ポイント数を取得する。

#### get_run_segment_count_for_character(character: Node) -> int
指定キャラクターのRun区間数を取得する。

#### get_vision_points_for_character(character: Node) -> Array[Dictionary]
指定キャラクターの視線ポイントを取得する。

#### get_run_segments_for_character(character: Node) -> Array[Dictionary]
指定キャラクターのRun区間を取得する。

#### get_clear_point_count_for_character(character: Node) -> int
指定キャラクターのClearポイント数を取得する。

#### get_clear_points_for_character(character: Node) -> Array[Dictionary]
指定キャラクターのClearポイントを取得する。

#### get_all_vision_points() -> Dictionary
全キャラクターの視線ポイントを取得する。

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとした視線ポイントの辞書

#### get_all_run_segments() -> Dictionary
全キャラクターのRun区間を取得する。

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとしたRun区間の辞書

#### get_all_clear_points() -> Dictionary
全キャラクターのClearポイントを取得する。

**戻り値:** `{ char_id: Array[Dictionary] }` - キャラクターIDをキーとしたClearポイントの辞書

#### take_all_vision_markers() -> Dictionary
全キャラクターのVisionMarkersの所有権を移譲する。

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

#### take_all_run_markers() -> Dictionary
全キャラクターのRunMarkersの所有権を移譲する。

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

#### take_all_clear_markers() -> Dictionary
全キャラクターのClearMarkersの所有権を移譲する。

**戻り値:** `{ char_id: Array[MeshInstance3D] }`

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

### マルチキャラクターモードの例

```gdscript
# マルチセレクト時の使用例
var selected_characters: Array[Node] = [char_a, char_b]

# マルチキャラクターモード開始
path_drawer.start_multi_character_mode(selected_characters)

# キャラクターAのマーカーを編集
path_drawer.set_active_edit_character(char_a)
path_drawer.start_vision_mode()
# ユーザーがマーカーを追加...

# キャラクターBに切り替え
path_drawer.set_active_edit_character(char_b)
# ユーザーが別のマーカーを追加...

# 確定時に全キャラクターのマーカーを取得
var all_vision = path_drawer.get_all_vision_points()
# all_vision = { char_a_id: [...], char_b_id: [...] }

# PathExecutionManagerに渡して確定
path_execution_manager.confirm_path(selected_characters, path_drawer, char_a)
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

## 内部動作

- `PathLineMesh`でパスを描画（破線+終点ドーナツ）
- `VisionMarker`で視線ポイントを可視化
- `RunMarker`でRun区間の開始/終点を可視化
- `ClearMarker`でClearポイントを可視化（リセットマーカー）
- パス上クリックで最近接点を計算し、そこから視線方向やRun区間、Clearポイントを設定
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
- `set_line_color(color: Color) -> void`
- `set_character_color(color: Color) -> void`
- `enable(character: Node3D) -> void`
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
- `start_multi_character_mode(characters: Array[Node]) -> void`
- `end_multi_character_mode() -> void`
- `set_active_edit_character(character: Node) -> void`
- `get_active_edit_character() -> Node`
- `is_multi_character_mode() -> bool`
- `get_vision_point_count_for_character(character: Node) -> int`
- `get_run_segment_count_for_character(character: Node) -> int`
- `get_vision_points_for_character(character: Node) -> Array[Dictionary]`
- `get_run_segments_for_character(character: Node) -> Array[Dictionary]`
- `get_clear_point_count_for_character(character: Node) -> int`
- `get_clear_points_for_character(character: Node) -> Array[Dictionary]`
- `get_all_vision_points() -> Dictionary`
- `get_all_run_segments() -> Dictionary`
- `get_all_clear_points() -> Dictionary`
- `take_all_vision_markers() -> Dictionary`
- `take_all_run_markers() -> Dictionary`
- `take_all_clear_markers() -> Dictionary`
