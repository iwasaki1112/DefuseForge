# LongPressProgressRing

**継承:** `Control`

## 概要

長押し操作（ホールド）の進行状況を円形のプログレスバーとして視覚化するUIコンポーネント。
WaitPointの待機時間設定など、時間経過を伴う操作のフィードバックに使用されます。

## ファイル

`godot/scripts/ui/long_press_progress_ring.gd`

## 機能

*   **円形プログレス:** 中心から時計回りにリングが充填されるアニメーションを描画します。
*   **自動更新:** 開始時に時間を指定することで、`_process` 内で自動的に進行率を更新できます。
*   **手動更新:** 外部から `set_progress` で進行率を制御することも可能です。
*   **カスタマイズ:** リングの半径、太さ、色、背景色をプロパティで変更可能です。

## プロパティ

| プロパティ名 | 型 | デフォルト | 説明 |
| :--- | :--- | :--- | :--- |
| `ring_radius` | `float` | `30.0` | リングの半径。 |
| `ring_width` | `float` | `4.0` | リングの線の太さ。 |
| `ring_color` | `Color` | `White (0.9)` | 進行部分の色。 |
| `background_color` | `Color` | `Gray (0.5)` | 背景リングの色。 |

## メソッド

### start

```gdscript
func start(screen_pos: Vector2, duration: float, color: Color = Color.WHITE) -> void
```

指定位置でプログレス表示を開始します（自動更新モード）。
`duration` 秒後に進行率が1.0になります。

### start_manual

```gdscript
func start_manual(screen_pos: Vector2, color: Color = Color.WHITE) -> void
```

指定位置でプログレス表示を開始します（手動更新モード）。
進行率は `set_progress` または `update_progress` で制御する必要があります。

### update_progress

```gdscript
func update_progress(elapsed: float, duration: float) -> void
```

経過時間と目標時間に基づいて進行率を更新します。手動モード時に使用します。

### complete

```gdscript
func complete() -> void
```

操作完了とみなし、表示を終了（非表示）します。

### cancel

```gdscript
func cancel() -> void
```

操作キャンセルとみなし、表示を終了（非表示）します。

### create (Static)

```gdscript
static func create(parent: Node, radius: float = 30.0) -> LongPressProgressRing
```

新しい `LongPressProgressRing` インスタンスを作成し、指定された親ノードに追加するファクトリーメソッドです。
