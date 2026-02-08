---
name: character-system
description: キャラクターシステム変更ガイド
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
---

# キャラクターシステム変更ガイド

キャラクター管理・移動・視界システムに変更を加える際のガイド。

## 主要ファイル

### コア
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/characters/game_character.gd` | GameCharacter | HP、死亡状態、チーム、武器、向き管理 |
| `scripts/animation/character_animation_controller.gd` | CharacterAnimationController | アニメーション制御 |
| `scripts/controllers/tps_player_controller.gd` | TPSPlayerController | TPS直接操作（ツインスティック） |

### 視界システム
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/characters/vision_component.gd` | VisionComponent | FOV可視判定 |
| `scripts/characters/vision_light.gd` | VisionLight | Fog of War 2D Light同期 |

### コンバット
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/characters/combat_awareness_component.gd` | CombatAwarenessComponent | 敵追跡・自動射撃 |
| `scripts/characters/bullet_trail_component.gd` | BulletTrailComponent | 弾道トレイル |
| `scripts/characters/muzzle_flash_component.gd` | MuzzleFlashComponent | マズルフラッシュ |

### マルチプレイヤー
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/characters/remote_interpolation_component.gd` | RemoteInterpolationComponent | リモートキャラ補間 |

### サービス
| ファイル | クラス | 責務 |
|---------|--------|------|
| `scripts/systems/character_manager_service.gd` | CharacterManagerService | キャラクター検索・フィルタ |
| `scripts/systems/character_setup_service.gd` | CharacterSetupService | 初期化（武器、視界） |
| `scripts/registries/character_registry.gd` | CharacterRegistry | プリセット管理 |

## 状態遷移

```
_ready() → initialize components
    ├→ set_anim_controller() → CharacterAnimationController
    ├→ setup_vision() → VisionComponent
    ├→ setup_vision_light() → VisionLight (FoW)
    ├→ setup_combat_awareness() → CombatAwarenessComponent
    └→ equip_weapon() → BulletTrail, MuzzleFlash

take_damage(attacker, is_headshot)
    └─(health <= 0)→ _die()
        ├→ play_death(hit_direction)
        ├→ vision.disable()
        ├→ combat_awareness.clear_target()
        └→ emit died
```

## 重要な設計

### 向き制御（Critical）
**警告**: Mixamoモデルは +Z が前方、Godotの `look_at()` は -Z をターゲットに向けるため **180度ずれる**。

```gdscript
# 正しい方法
character.set_facing_direction_vec(direction)
character.get_facing_direction()

# 間違い（使用禁止）
character.look_at(target)  # 180度ずれる
character._facing_direction = dir  # 同期漏れ
```

### マルチプレイヤー補間
```
ネットワーク受信 (15Hz) → RemoteInterpolationComponent
    ├→ _snapshot_buffer に追加
    ├→ 2点間で線形補間 (80ms遅延バッファ)
    └→ 外挿 (パケットロス時、MAX 150ms)

調整: network_constants.gd の INTERPOLATION_DELAY
  大きく(120ms): 滑らか、ラグ増
  小さく(50ms): レスポンス良、カクつき増
```

## 変更時の注意点

1. **向き制御は `set_facing_direction_vec()` 経由必須**
2. **死亡時の壁検出** - `_detect_nearby_walls()` で安全な方向選択
4. **VisionComponentのFOV計算** - XZ平面で距離・角度計算（Y軸無視）
5. **コンポーネント遅延セットアップ** - `call_deferred()` でパフォーマンス最適化
6. **iOS互換** - `load()` で動的ロード

## よくある変更パターン

### 新しいコンポーネントを追加
```gdscript
# GameCharacterに追加
var my_component: MyComponent = null

func setup_my_component() -> MyComponent:
    if my_component == null:
        my_component = MyComponent.new()
        add_child(my_component)
    return my_component

# CharacterSetupServiceで呼び出し
func _complete_character_setup(character: Node) -> void:
    character.setup_my_component()
```

### カスタム視界ロジック
`VisionComponent.is_position_in_view()` を拡張または新メソッド追加

### マルチプレイヤー状態同期
```gdscript
var snapshot = character.to_character_snapshot()
character.apply_remote_state(state_message)
character.update_remote_interpolation(delta)
```

## 依存グラフ

```
game_character.gd
  ├→ character_animation_controller.gd
  ├→ vision_component.gd → vision_light.gd
  ├→ combat_awareness_component.gd
  ├→ remote_interpolation_component.gd
  ├→ bullet_trail_component.gd
  └→ muzzle_flash_component.gd

tps_player_controller.gd
  ├→ game_character.gd (参照)
  └→ character_animation_controller.gd (参照)
```

---
**関連ドキュメント**: `docs/godot/api/GameCharacter.md`, `docs/godot/api/CharacterAnimationController.md`
