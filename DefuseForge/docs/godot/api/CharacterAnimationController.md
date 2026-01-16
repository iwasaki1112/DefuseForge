# CharacterAnimationController

キャラクターアニメーションを管理するコントローラークラス。移動、エイム、戦闘、デスアニメーションを統合的に制御する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/animation/character_animation_controller.gd` |

## Enums

### Stance
キャラクターの姿勢。

| 値 | 説明 |
|----|------|
| `STAND` | 立ち状態 |
| `CROUCH` | しゃがみ状態 |

### Weapon
武器タイプ。

| 値 | 説明 |
|----|------|
| `NONE` | 武器なし |
| `RIFLE` | ライフル |
| `PISTOL` | ピストル |

### HitDirection
被弾方向（デスアニメーション用）。

| 値 | 説明 |
|----|------|
| `FRONT` | 正面から |
| `BACK` | 背後から |
| `LEFT` | 左から |
| `RIGHT` | 右から |

## Export Properties

### Movement Speed
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `walk_speed` | `float` | `1.5` | 歩行速度 |
| `run_speed` | `float` | `5.0` | 走行速度 |
| `crouch_speed` | `float` | `1.5` | しゃがみ移動速度 |
| `aim_walk_speed` | `float` | `2.0` | エイム中の歩行速度 |
| `rotation_speed` | `float` | `15.0` | 回転速度 |

> **Note:** アニメーション基準速度（`ANIM_REF_WALK`, `ANIM_REF_RUN`, `ANIM_REF_CROUCH`）は内部定数として管理され、足滑り防止のためのスケーリングに使用される。

### Recoil
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `rifle_recoil_strength` | `float` | `0.08` | ライフルのリコイル強度 |
| `pistol_recoil_strength` | `float` | `0.12` | ピストルのリコイル強度 |
| `rifle_fire_rate` | `float` | `0.1` | ライフルの発射間隔 |
| `pistol_fire_rate` | `float` | `0.2` | ピストルの発射間隔 |
| `recoil_recovery` | `float` | `10.0` | リコイル回復速度 |

### Bone Names
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `upper_body_root` | `String` | `"mixamorig_Spine1"` | 上半身ルートボーン名 |
| `spine_bone` | `String` | `"mixamorig_Spine2"` | リコイル適用ボーン名 |

## Public API

### setup(model: Node3D, anim_player: AnimationPlayer) -> void
アニメーションコントローラーをセットアップする。

**引数:**
- `model` - キャラクターモデル（Skeleton3Dを含む）
- `anim_player` - AnimationPlayerノード

### update_animation(movement_direction: Vector3, aim_direction: Vector3, is_running: bool, delta: float) -> void
毎フレーム呼び出してアニメーションを更新する。

**引数:**
- `movement_direction` - 移動方向ベクトル（ワールド座標）
- `aim_direction` - エイム方向ベクトル
- `is_running` - 走行中か
- `delta` - デルタタイム

### set_stance(stance: Stance) -> void
姿勢を設定する。

### set_weapon(weapon: Weapon) -> void
武器タイプを設定する。

### set_aiming(aiming: bool) -> void
エイム状態を設定する。上半身レイヤーに影響。

### fire() -> void
発射アクションをトリガーする。リコイルアニメーションを再生。

### get_current_speed() -> float
現在の状態に基づく移動速度を返す。

**戻り値:** 現在の移動速度

### is_dead() -> bool
キャラクターが死亡状態か確認する。

**戻り値:** 死亡状態なら`true`

### get_look_direction() -> Vector3
現在のエイム方向を取得する（視界計算用）。

**戻り値:** エイム方向ベクトル（正規化済み）

### set_look_direction(direction: Vector3) -> void
エイム方向を直接設定する（回転モード用）。モデルの向きも即座に更新。

**引数:**
- `direction` - 視線方向ベクトル

### play_death(hit_direction: HitDirection = HitDirection.FRONT, headshot: bool = false) -> void
デスアニメーションを再生する。

**引数:**
- `hit_direction` - 被弾方向
- `headshot` - ヘッドショットか

## 使用例

```gdscript
# セットアップ
var anim_ctrl = CharacterAnimationController.new()
character.add_child(anim_ctrl)
anim_ctrl.setup(model, anim_player)

# 毎フレーム更新
func _physics_process(delta):
    var move_dir = Vector3(input_x, 0, input_z)
    var aim_dir = aim_target - global_position
    anim_ctrl.update_animation(move_dir, aim_dir, is_running, delta)

# 状態変更
anim_ctrl.set_stance(CharacterAnimationController.Stance.CROUCH)
anim_ctrl.set_weapon(CharacterAnimationController.Weapon.RIFLE)
anim_ctrl.set_aiming(true)
anim_ctrl.fire()
```

## 内部動作

- 8方向ストレイフアニメーションを`BlendSpace2D`で管理
- 上半身エイムはボーンフィルター付き`Blend2`で合成
- `RecoilModifier`でプロシージャルリコイルを適用
- Mixamoリグ専用設計
