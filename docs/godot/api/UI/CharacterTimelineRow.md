# CharacterTimelineRow

**継承:** `HBoxContainer`

キャラクタータイムライン行コンポーネント。
キャラクターラベル（A, B, C...）と `TimelineBar` を組み合わせたUI要素です。

## 定数

| 名前 | 値 | 説明 |
| :--- | :--- | :--- |
| `LABEL_WIDTH` | `30.0` | ラベル部分の幅 |
| `ROW_HEIGHT` | `28.0` | 行の高さ |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `setup(character: Node, label_text: String, color: Color)` | `void` | キャラクター、ラベルテキスト、色を設定してUIを初期化します。 |
| `set_timeline_data(data: TimelineData)` | `void` | タイムラインデータを設定し、内部の `TimelineBar` を更新します。 |
| `set_max_duration(max_duration: float)` | `void` | 全キャラクター共通のタイムスケールを設定します。 |
| `get_character()` | `Node` | 関連付けられているキャラクターノードを取得します。 |
| `get_total_duration()` | `float` | タイムラインの合計時間を取得します。 |
| `get_time_at_ratio(ratio: float)` | `float` | 指定された比率に対応する時間を取得します。 |
| `clear()` | `void` | タイムライン表示をクリアします。 |
