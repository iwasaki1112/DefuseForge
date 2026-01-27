# PathState

**継承:** `RefCounted`

`PathDrawer` の状態変数をカプセル化したデータクラス。
描画モード、現在のアクティブなパスやキャラクターなどを管理します。

## 列挙体

### State
| 名前 | 説明 |
| :--- | :--- |
| `IDLE` | 待機状態 |
| `DRAWING` | 移動パスの新規描画中 |
| `EXTENDING` | 既存パスの延長中 |
| `MARKER_EDIT` | マーカー（Vision, Grenade等）の編集中 |

### DrawingMode
`MOVEMENT`, `VISION_POINT`, `RUN_MARKER`, `CLEAR_MARKER` などの編集モード。

## プロパティ

| 名前 | 型 | 説明 |
| :--- | :--- | :--- |
| `state` | `State` | 現在のメイン状態 |
| `drawing_mode` | `DrawingMode` | 現在のツールモード |
| `active_character` | `Node3D` | 現在選択中のキャラクター（プレビュー用） |
| `pending_path` | `PackedVector3Array` | 確定前の編集中のパス |
| `is_drawing` | `bool` | パス描画中フラグ |
| `is_extending_path` | `bool` | パス延長中フラグ |
| `character_color` | `Color` | 現在のキャラクターの色 |

## メソッド

状態遷移のためのヘルパーメソッドを提供します。
*   `start_drawing()`, `finish_drawing()`
*   `start_extending()`, `finish_extending()`
*   `set_marker_mode(mode)`, `set_movement_mode()`
*   `has_pending_path()`
