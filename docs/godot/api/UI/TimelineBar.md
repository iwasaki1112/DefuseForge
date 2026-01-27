# TimelineBar

**継承:** `Control`

単一キャラクターのタイムラインバー。
パスの時間軸を可視化し、セグメント（移動、待機など）とマーカー（アクション）を描画します。

## 定数

### 色設定

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `COLOR_RUN` | `Color("#FF8800")` | 走行（Run）セグメントの色 |
| `COLOR_WAIT` | `Color("#FFCC00")` | 待機（Wait）セグメントの色 |
| `COLOR_DOOR` | `Color("#FF4444")` | ドア操作セグメントの色 |
| `COLOR_VISION` | `Color("#AA66FF")` | ビジョンマーカーの色（紫） |
| `COLOR_CLEAR` | `Color("#66CCFF")` | クリアマーカーの色（水色） |
| `COLOR_GRENADE` | `Color("#66FF66")` | グレネードマーカーの色（緑） |
| `COLOR_SMOKE_GRENADE` | `Color("#AAAAAA")` | スモークグレネードマーカーの色（灰色） |
| `COLOR_BACKGROUND` | `Color("#333333", 0.5)` | 背景色 |

### レイアウト

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `MARKER_ICON_SIZE` | `16.0` | マーカーアイコンのサイズ（ピクセル） |
| `BAR_HEIGHT` | `24.0` | バーの高さ |

## プロパティ

| 名前 | 型 | 説明 |
| :--- | :--- | :--- |
| `_timeline_data` | `TimelineCalculator.TimelineData` | 表示するタイムラインデータ |
| `_max_duration` | `float` | 全体の最大時間（スケーリング用） |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `set_timeline_data(data: TimelineData, color: Color)` | `void` | タイムラインデータを設定し、再描画します。 |
| `set_max_duration(max_duration: float)` | `void` | 相対スケーリングのための最大時間を設定します。 |
| `get_time_at_ratio(ratio: float)` | `float` | バー上の位置（比率 0.0-1.0）に対応する時間を取得します。 |
| `get_total_duration()` | `float` | 現在のタイムラインの合計時間を取得します。 |
| `clear()` | `void` | タイムラインデータをクリアします。 |
