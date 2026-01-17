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
| `vision_point_added` | `anchor: Vector3, direction: Vector3` | 視線ポイント追加時 |
| `run_segment_added` | `start_ratio: float, end_ratio: float` | Run区間追加時 |
| `mode_changed` | `mode: int` | モード変更時（0=MOVEMENT, 1=VISION_POINT, 2=RUN_MARKER） |

## Enums

### DrawingMode
描画モード。

| 値 | 説明 |
|----|------|
| `MOVEMENT` | 移動パス描画モード |
| `VISION_POINT` | 視線ポイント設定モード |
| `RUN_MARKER` | Runマーカー設定モード |

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
パスと視線ポイントとRunマーカーをすべてクリアする。

#### get_drawn_path() -> PackedVector3Array
描画されたパスを取得する。

#### is_drawing() -> bool
現在描画中か確認する。

#### set_line_color(color: Color) -> void
ライン色を変更する。

#### get_drawing_mode() -> DrawingMode
現在の描画モードを取得する。

### Vision Point API

#### start_vision_mode() -> bool
視線ポイント設定モードに切り替える。

**戻り値:** 成功なら`true`（パスが存在しない場合は`false`）

#### start_movement_mode() -> void
移動パス描画モードに戻る。

#### has_vision_points() -> bool
視線ポイントがあるか確認する。

#### get_vision_points() -> Array[Dictionary]
視線ポイントを取得する。

**戻り値:** `{ "path_ratio": float, "anchor": Vector3, "direction": Vector3 }` の配列

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

# パス実行
path_drawer.execute_with_vision(false)  # 歩行で実行（Run区間だけ走る）
```

## データ形式

### 視線ポイント
```gdscript
{
    "path_ratio": 0.5,      # パス上の位置（0.0〜1.0）
    "anchor": Vector3(...), # アンカー位置
    "direction": Vector3(...)  # 視線方向（正規化済み）
}
```

### Run区間
```gdscript
{
    "start_ratio": 0.3,  # 開始位置（0.0〜1.0）
    "end_ratio": 0.6     # 終了位置（0.0〜1.0）
}
```

## 内部動作

- `PathLineMesh`でパスを描画（破線+終点ドーナツ）
- `VisionMarker`で視線ポイントを可視化
- `RunMarker`でRun区間の開始/終点を可視化
- パス上クリックで最近接点を計算し、そこから視線方向やRun区間を設定
