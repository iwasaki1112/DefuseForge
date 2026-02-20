# HandGrenade

**継承:** `Grenade`

ハンドグレネード（爆発ダメージ付き）の実装クラス。
着地時に即爆発し、範囲内のキャラクターに距離減衰付きダメージを与え、爆発VFXを生成します。

## プロパティ

| 名前 | 型 | デフォルト値 | 説明 |
| :--- | :--- | :--- | :--- |
| `explosion_radius` | `float` | `GameConstants.HAND_GRENADE_EXPLOSION_RADIUS` (3.5) | 爆発範囲（メートル） |
| `explosion_damage` | `float` | `GameConstants.HAND_GRENADE_EXPLOSION_DAMAGE` (80.0) | 最大ダメージ |

## メソッド

| 名前 | 戻り値 | 説明 |
| :--- | :--- | :--- |
| `set_explosion_effect_scene(scene)` | `void` | 爆発VFXシーンを設定します（GrenadeServiceから注入） |
| `_explode()` | `void` | オーバーライド。親クラスのダメージ処理 + 爆発VFXスポーン |

## 詳細

- **着地即爆発**: `_physics_process`で`_is_grounded`を検知し、即座に`_explode()`を呼び出す（SmokeGrenadeと同パターン）
- **ダメージ処理**: 親クラス`Grenade._explode()`の既存ロジック（`PhysicsShapeQueryParameters3D`で範囲内キャラクター検索、距離減衰）を使用
- **爆発VFX**: `ExplosionEffect`シーンを爆発位置にスポーン（GrenadeServiceからシーン注入）
- **ネットワーク同期**: `GRENADE_THROW`/`GRENADE_EXPLODE`イベント（`is_smoke=false`パス）で動作
- **所持数**: 1ラウンドにつき`HAND_GRENADE_PER_ROUND`個（デフォルト1）

## シーン構造

```
HandGrenade (Node3D, script: hand_grenade.gd)
  └── Model (hand_granade.glb)
```

## 関連クラス

- [Grenade](Grenade.md) - 親クラス
- [SmokeGrenade](SmokeGrenade.md) - 同パターンの実装
- [ExplosionEffect](../Effect/ExplosionEffect.md) - 爆発VFX
- [GrenadeService](../System/GrenadeService.md) - 生成・管理
