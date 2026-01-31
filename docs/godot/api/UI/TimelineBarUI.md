# TimelineBarUI

## 概要

画面下部に表示されるタイムラインバーUIのメインコンテナ。複数キャラクターのタイムラインを管理し、パス描画時とExecute時の進行状況を可視化する。

## ファイル

`godot/scripts/ui/timeline_bar_ui.gd`

## 継承

`PanelContainer`

## 関連クラス

- [TimelineCalculator](TimelineCalculator.md) - 時間計算
- `CharacterTimelineRow` - 各キャラクターの行
- `TimelineBar` - 実際のバー描画

## 定数

| 定数 | 型 | 値 | 説明 |
|------|-----|-----|------|
| `PANEL_HEIGHT` | float | 80.0 | 2行分のパネル高さ |
| `PANEL_MAX_HEIGHT` | float | 120.0 | 3行以上の場合の最大高さ |
| `ROW_HEIGHT` | float | 32.0 | 1行の高さ |
| `PADDING` | float | 8.0 | パディング |
| `VISIBLE_ROWS` | int | 2 | スクロールなしで表示する行数 |

## 公開メソッド

### set_character_timeline

キャラクターのタイムラインを追加または更新。

```gdscript
func set_character_timeline(
    character: Node,
    path: Array[Vector3],
    run_segments: Array[Dictionary] = [],
    wait_points: Array[Dictionary] = [],
    door_points: Array[Dictionary] = [],
    label_text: String = "A",
    color: Color = Color.CYAN
) -> void
```

| 引数 | 型 | 説明 |
|------|-----|------|
| `character` | Node | キャラクターノード |
| `path` | Array[Vector3] | パスポイント配列 |
| `run_segments` | Array[Dictionary] | Run区間配列 |
| `wait_points` | Array[Dictionary] | Waitポイント配列 |
| `door_points` | Array[Dictionary] | Doorポイント配列 |
| `label_text` | String | ラベル文字 (A, B, C...) |
| `color` | Color | キャラクター色 |

### remove_character_timeline

キャラクターのタイムラインを削除。

```gdscript
func remove_character_timeline(character: Node) -> void
```

### clear_all

全タイムラインをクリア。

```gdscript
func clear_all() -> void
```

### start_execution

実行モードを開始。プログレスインジケーターが表示される。

```gdscript
func start_execution() -> void
```

### stop_execution

実行モードを終了。

```gdscript
func stop_execution() -> void
```

### update_character_progress

キャラクターの進行率を更新（0.0〜1.0）。

```gdscript
func update_character_progress(character: Node, progress: float) -> void
```

### update_character_progress_from_ratio

パス比率から進行率を更新。タイムラインデータを使って時間ベースの進行率に変換。

```gdscript
func update_character_progress_from_ratio(character: Node, ratio: float) -> void
```

### is_executing

実行中かどうかを取得。

```gdscript
func is_executing() -> bool
```

### get_character_count

登録されているキャラクター数を取得。

```gdscript
func get_character_count() -> int
```

## UI構造

```
TimelineBarUI (PanelContainer)
└── ScrollContainer
    └── VBoxContainer
        ├── CharacterTimelineRow_A
        │   ├── Label "A"
        │   └── TimelineBar
        └── CharacterTimelineRow_B
            ├── Label "B"
            └── TimelineBar
```

## 色定義

| セグメント | 色 |
|-----------|-----|
| 歩行 (WALK) | キャラクター色 (80%アルファ) |
| 走行 (RUN) | オレンジ (#FF8800) |
| 待機 (WAIT) | 黄色 (#FFCC00) |
| ドア (DOOR) | 赤 (#FF4444) |
| 背景 | グレー (#333333, 50%アルファ) |
| プログレスライン | 白 |

## 使用例

```gdscript
# GameHUDでの使用例
var timeline_ui = TimelineBarUI.new()
add_child(timeline_ui)

# キャラクターのタイムラインを設定
timeline_ui.set_character_timeline(
    character_a,
    path_points,
    run_segments,
    wait_points,
    door_points,
    "A",
    Color(0.2, 0.6, 1.0)
)

# Execute開始時
timeline_ui.start_execution()

# 毎フレーム更新
timeline_ui.update_character_progress_from_ratio(character_a, 0.5)

# Execute終了時
timeline_ui.stop_execution()
timeline_ui.clear_all()
```
