# ExplosionEffect

**継承:** `Node3D`

ハンドグレネードの爆発VFXエフェクト。GPUParticles3Dの火花パーティクルとOmniLight3Dの閃光を管理し、自動削除されます。

## プロパティ

| 名前 | 型 | デフォルト値 | 説明 |
| :--- | :--- | :--- | :--- |
| `lifetime` | `float` | `2.0` | エフェクトの総寿命（秒、自動削除まで） |
| `flash_energy` | `float` | `4.0` | 閃光の初期エネルギー |
| `flash_range` | `float` | `6.0` | 閃光の到達範囲（メートル） |
| `flash_fade_time` | `float` | `0.3` | 閃光のフェードアウト時間（秒） |

## 詳細

- **パーティクル**: GPUParticles3D（one_shot）で火花を放射（24パーティクル、0.6秒寿命）
- **閃光**: OmniLight3D（暖色、Tweenで`flash_fade_time`秒かけてエネルギー0へ減衰）
- **自動削除**: `lifetime`秒後に`queue_free()`で自動削除

## シーン構造

```
ExplosionEffect (Node3D, script: explosion_effect.gd)
  ├── Particles (GPUParticles3D, one_shot)
  └── FlashLight (OmniLight3D)
```

## 関連クラス

- [HandGrenade](../Weapon/HandGrenade.md) - 使用元
- [GrenadeService](../System/GrenadeService.md) - シーンのプリロード・注入
