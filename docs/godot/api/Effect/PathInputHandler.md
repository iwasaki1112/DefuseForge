# PathInputHandler

**継承:** `RefCounted`

`PathDrawer` の入力処理を統括するクラス。
現在の `DrawingMode` に応じて、適切な `MarkerHandlerBase` のサブクラスに入力を委譲します。

## 列挙体 (DrawingMode)

| モード名 | 説明 |
| :--- | :--- |
| `MOVEMENT` | 移動パス描画モード |
| `VISION_POINT` | 視線（Vision）マーカー配置モード |
| `RUN_MARKER` | 走り（Run）区間設定モード |
| `CLEAR_MARKER` | クリアリング（Clear）ポイント配置モード |
| `GRENADE_MARKER` | グレネード投擲ポイント配置モード |
| `SMOKE_GRENADE_MARKER` | スモーク投擲ポイント配置モード |
| `DOOR_MARKER` | ドア操作ポイント配置モード |
| `WAIT_MARKER` | 待機（Wait）ポイント配置モード |

## メソッド

### 初期化・共通操作
| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `setup(path_drawer, camera)` | `void` | 自身と内部の全ハンドラを初期化します。 |
| `set_character_color(color)` | `void` | 全ハンドラのマーカー色を更新します。 |
| `handle_input(event, mode)` | `bool` | 指定モードのハンドラに入力イベントを渡します。 |
| `get_handler(mode)` | `MarkerHandlerBase` | 指定モードのハンドラインスタンスを取得します。 |
| `clear_all()` | `void` | 全ハンドラのデータをクリアします。 |
| `reset_all_states()` | `void` | 全ハンドラの一時状態をリセットします。 |

### データアクセス (State Query & Retrieval)

各マーカータイプに対して、以下の3種類のメソッドが提供されています。
ここで `*` にはマーカー名（`vision`, `run`, `clear`, `grenade`, `smoke_grenade`, `door`, `wait`）が入ります。

1.  **`has_*_markers() -> bool`**
    *   指定タイプのマーカーが存在するかどうかを確認します。
    *   例: `has_vision_points()`, `has_run_segments()`

2.  **`get_*_markers() -> Array[Dictionary]`**
    *   マーカーのデータ（位置、パラメータなど）の配列を取得します。
    *   例: `get_vision_points()`, `get_run_segments()`

3.  **`take_*_markers() -> Array[MeshInstance3D]`**
    *   マーカーの可視化メッシュインスタンスの所有権を取得します。
    *   呼び出し後、ハンドラ内からは管理対象外となります（主にパス確定時の処理用）。
    *   例: `take_vision_markers()`, `take_run_markers()`

## 内部ハンドラ構成

各モードは専用のハンドラクラスによって処理されます：
- `VisionMarkerHandler`
- `RunMarkerHandler`
- `ClearMarkerHandler`
- `GrenadeMarkerHandler`
- `SmokeGrenadeMarkerHandler`
- `DoorMarkerHandler`
- `WaitMarkerHandler`