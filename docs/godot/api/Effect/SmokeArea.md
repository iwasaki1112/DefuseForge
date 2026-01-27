# SmokeArea

**継承:** `Node3D`

スモークグレネードの効果範囲を表すクラス。
視覚的な煙のエフェクト（`GPUParticles3D`）と、論理的な視界遮断判定を提供します。
時間経過とともに半径が拡大・維持・縮小します。

## プロパティ

| 名前 | 型 | デフォルト値 | 説明 |
| :--- | :--- | :--- | :--- |
| `max_radius` | `float` | `GameConstants.SMOKE_RADIUS` | スモークの最大半径 |
| `duration` | `float` | `GameConstants.SMOKE_DURATION` | スモークの持続時間 |
| `expand_time` | `float` | `GameConstants.SMOKE_EXPAND_TIME` | 展開完了までの時間 |
| `fade_time` | `float` | `GameConstants.SMOKE_FADE_TIME` | フェードアウトにかかる時間 |

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `smoke_started` | `void` | スモーク展開開始時 |
| `smoke_ended` | `void` | スモーク終了時 |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `start(manager)` | `void` | スモークを開始し、マネージャーに自身を登録します。 |
| `intersects_line_segment(from, to)` | `bool` | 指定された線分が現在のスモーク範囲と交差するか判定します（XZ平面）。 |
| `is_position_inside(pos)` | `bool` | 指定された位置がスモーク範囲内にあるか判定します。 |
| `get_current_radius()` | `float` | 現在の有効半径を取得します。 |
| `get_remaining_time()` | `float` | 消滅までの残り時間を取得します。 |

## 詳細

### 半径の推移
1.  **展開フェーズ (0 ~ expand_time):** イーズアウト関数により急速に `max_radius` まで拡大。
2.  **維持フェーズ:** `max_radius` を維持。
3.  **消滅フェーズ (duration - fade_time ~ duration):** 線形に半径が0に向かって縮小。
