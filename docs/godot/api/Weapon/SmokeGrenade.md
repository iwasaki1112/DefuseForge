# SmokeGrenade

**継承:** `Grenade`

スモークグレネードの実装クラス。
爆発時にダメージを与える代わりに、視界を遮るスモークエリア（`SmokeArea`）を生成します。

## プロパティ

| 名前 | 型 | デフォルト値 | 説明 |
| :--- | :--- | :--- | :--- |
| `smoke_duration` | `float` | `GameConstants.SMOKE_DURATION` | スモークの持続時間 |
| `smoke_radius` | `float` | `GameConstants.SMOKE_RADIUS` | スモークの最大半径 |
| `smoke_expand_time` | `float` | `GameConstants.SMOKE_EXPAND_TIME` | 最大半径に達するまでの時間 |
| `smoke_fade_time` | `float` | `GameConstants.SMOKE_FADE_TIME` | 消滅にかかるフェードアウト時間 |

## シグナル

| 名前 | 引数 | 説明 |
| :--- | :--- | :--- |
| `smoke_deployed` | `area: Node3D` | スモークが展開された時に発火します。生成された `SmokeArea` インスタンスを渡します。 |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `set_smoke_manager(manager)` | `void` | スモークエリアの管理を行うマネージャーを設定します。 |
| `_explode()` | `void` | オーバーライド。スモークを展開し、親クラスの `exploded` シグナルを発火します。 |

## 詳細

爆発時、`GameConstants.SCENE_SMOKE_AREA` から `SmokeArea` インスタンスを生成し、現在の位置に配置します。
通常のグレネードと異なり、`explosion_damage` と `explosion_radius` は初期化時に0に設定されます。
