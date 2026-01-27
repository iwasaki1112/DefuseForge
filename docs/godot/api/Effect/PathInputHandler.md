# PathInputHandler

**継承:** `RefCounted`

`PathDrawer` の入力処理を統括するクラス。
現在の `DrawingMode` に応じて、適切な `MarkerHandlerBase` のサブクラスに入力を委譲します。

## 列挙体 (DrawingMode)

`MOVEMENT`, `VISION_POINT`, `RUN_MARKER`, `CLEAR_MARKER`, `GRENADE_MARKER`, `DOOR_MARKER`, `WAIT_MARKER`, `SMOKE_GRENADE_MARKER`

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `setup(path_drawer, camera)` | `void` | 自身と内部の全ハンドラを初期化します。 |
| `set_character_color(color)` | `void` | 全ハンドラのマーカー色を更新します。 |
| `handle_input(event, mode)` | `bool` | 指定モードのハンドラに入力イベントを渡します。 |
| `get_handler(mode)` | `MarkerHandlerBase` | 指定モードのハンドラインスタンスを取得します。 |
| `clear_all()` | `void` | 全ハンドラのデータをクリアします。 |
| `reset_all_states()` | `void` | 全ハンドラの一時状態をリセットします。 |

## データアクセスメソッド
各マーカータイプに対応する `has_*`, `get_*`, `take_*` メソッド群を提供します。

例:
*   `has_vision_points()`: 視線マーカーがあるか
*   `get_vision_points()`: 視線マーカーデータの配列を取得
*   `take_vision_markers()`: 視線マーカーのメッシュインスタンスを取得し、ハンドラからは削除（所有権移動）
