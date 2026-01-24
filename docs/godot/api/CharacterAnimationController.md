# CharacterAnimationController

キャラクターアニメーションを管理するコントローラークラス。移動、戦闘、デスアニメーションを統合的に制御する。

> **重要: Mixamoモデルの向きについて**
>
> | 項目 | 方向 |
> |------|------|
> | Mixamoモデルの前方向 | **+Z** |
> | Godotの`look_at()`/`Basis.looking_at()`がターゲットに向ける軸 | **-Z** |
>
> この180度の差により、キャラクターの向きを変更する際は以下のAPIを使用してください：
> - `GameCharacter.face_towards(target_pos)` - ターゲット位置を向く
> - `GameCharacter.set_facing_direction_vec(direction)` - 方向ベクトルで設定
>
> `CharacterBody3D.look_at()`を直接使用するとモデルが逆方向を向きます。

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

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `fired` | なし | 発射アクションが実行されたタイミング |
| `door_kick_impact` | なし | ドアキックのインパクトタイミング（フレーム36/66、1.2秒） |
| `door_kick_finished` | なし | ドアキックアニメーション完了時 |

## Export Properties

### Movement Speed
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `walk_speed` | `float` | `1.5` | 歩行速度 |
| `run_speed` | `float` | `5.0` | 走行速度 |
| `crouch_speed` | `float` | `1.5` | しゃがみ移動速度 |
| `rotation_speed` | `float` | `15.0` | 回転速度 |

> **Note:** アニメーション基準速度（`ANIM_REF_WALK`, `ANIM_REF_RUN`, `ANIM_REF_CROUCH`）は内部定数として管理され、足滑り防止のためのスケーリングに使用される。

### Recoil
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `rifle_recoil_strength` | `float` | `0.16` | ライフルのリコイル強度 |
| `pistol_recoil_strength` | `float` | `0.24` | ピストルのリコイル強度 |
| `rifle_fire_rate` | `float` | `0.1` | ライフルの発射間隔 |
| `pistol_fire_rate` | `float` | `0.2` | ピストルの発射間隔 |
| `recoil_recovery` | `float` | `10.0` | リコイル回復速度 |

> **重要:** 武器装備時、`WeaponPreset.recoil_strength`がこれらのデフォルト値を上書きします。リコイル強度を調整する場合は、各武器の`.tres`ファイル（`data/weapons/`配下）を編集してください。

### Lean
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `max_lean_degrees` | `float` | `25.0` | リーンの最大角度（度） |
| `lean_speed` | `float` | `10.0` | リーンの補間速度 |
| `lean_deadzone` | `float` | `0.15` | 小さな横移動を無視する閾値 |

> **Note:** リーンは上半身（`spine_bone`）にロールとして適用される。しゃがみ/走行中は無効。

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

### update_animation(movement_direction: Vector3, look_direction: Vector3, is_running: bool, delta: float) -> void
毎フレーム呼び出してアニメーションを更新する。

**引数:**
- `movement_direction` - 移動方向ベクトル（ワールド座標）
- `look_direction` - 視線方向ベクトル
- `is_running` - 走行中か
- `delta` - デルタタイム

### set_stance(stance: Stance) -> void
姿勢を設定する。

### set_weapon(weapon: Weapon) -> void
武器タイプを設定する。

### fire() -> void
発射アクションをトリガーする。リコイルアニメーションを再生。

### get_current_speed() -> float
現在の状態に基づく移動速度を返す。

**戻り値:** 現在の移動速度

### is_dead() -> bool
キャラクターが死亡状態か確認する。

**戻り値:** 死亡状態なら`true`

### get_look_direction() -> Vector3
現在の視線方向を取得する（視界計算用）。

**戻り値:** 視線方向ベクトル（正規化済み）

### set_look_direction(direction: Vector3) -> void
視線方向を直接設定する（回転モード用）。モデルの向きも即座に更新。

**引数:**
- `direction` - 視線方向ベクトル

### play_death(hit_direction: HitDirection = HitDirection.FRONT, headshot: bool = false) -> void
デスアニメーションを再生する。被弾方向に応じて適切なアニメーションを選択。

**引数:**
- `hit_direction` - 被弾方向（倒れる方向を決定）
- `headshot` - ヘッドショットか（将来拡張用）

**方向別アニメーション:**
| 被弾方向 | 倒れる方向 | アニメーション |
|---------|----------|--------------|
| `FRONT` | 後ろ | `death_forward` |
| `BACK` | 前 | `death_backward` |
| `RIGHT` | 左 | `death_right` |
| `LEFT` | 右 | `death_forward`（フォールバック）|

> **Note:** `death_left`アニメーションは存在しないため、`LEFT`被弾時は`death_forward`にフォールバックする。
> `GameCharacter._select_safe_death_direction()`で壁を避けた安全な方向が選択される。

### play_door_kick() -> void
ドアキックアニメーションを再生する。武器タイプに応じて適切なアニメーションが選択される。

- `Weapon.RIFLE` → `rifle_door_kick`
- `Weapon.PISTOL` → `pistol_door_kick`

アニメーション再生中は`update_animation()`の更新がスキップされ、`get_current_speed()`は0を返す。
アニメーション完了時に`door_kick_finished`シグナルが発火し、0.3秒のクロスフェードでアイドルアニメーションに遷移する。

### is_door_kicking() -> bool
ドアキックアニメーション再生中か確認する。

**戻り値:** ドアキック中なら`true`

## 使用例

```gdscript
# セットアップ
var anim_ctrl = CharacterAnimationController.new()
character.add_child(anim_ctrl)
anim_ctrl.setup(model, anim_player)

# 毎フレーム更新
func _physics_process(delta):
    var move_dir = Vector3(input_x, 0, input_z)
    var look_dir = target_position - global_position
    anim_ctrl.update_animation(move_dir, look_dir, is_running, delta)

# 状態変更
anim_ctrl.set_stance(CharacterAnimationController.Stance.CROUCH)
anim_ctrl.set_weapon(CharacterAnimationController.Weapon.RIFLE)
anim_ctrl.fire()

# ドアキック
anim_ctrl.door_kick_finished.connect(_on_door_kick_done)
anim_ctrl.play_door_kick()

func _on_door_kick_done():
    print("Door kick completed!")
```

## 内部動作

- 8方向ストレイフアニメーションを`BlendSpace2D`で管理
- `RecoilModifier`でプロシージャルリコイルを適用
- Mixamoリグ専用設計

## 重要: モデル向き制御の注意点

> **警告: 絶対に変更しないこと**
>
> モデルの向き制御で `Basis.looking_at(-direction)` を使用している箇所がある。
> この **マイナス符号は必須** であり、削除してはならない。
>
> **理由:**
> - Mixamoモデルの前方向: **+Z**
> - `Basis.looking_at()` がターゲットに向ける軸: **-Z**
>
> この仕様の違いを吸収するために `-direction` を渡している。
> マイナスを削除するとモデルが意図した方向と **逆を向く**。
>
> 該当箇所:
> - `set_model_direction()`
> - `set_look_direction()`
> - `_update_model_rotation()`

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `fired` | なし |
| `door_kick_impact` | なし |
| `door_kick_finished` | なし |

### メソッド
- `setup(model: Node3D, anim_player: AnimationPlayer) -> void`
- `update_animation(`
- `set_stance(stance: Stance) -> void`
- `get_stance() -> Stance`
- `set_weapon(weapon: Weapon) -> void`
- `fire() -> void`
- `get_current_speed() -> float`
- `is_dead() -> bool`
- `set_animation_tree_active(active: bool) -> void`
- `get_look_direction() -> Vector3`
- `get_model() -> Node3D`
- `set_look_direction(direction: Vector3) -> void`
- `set_model_direction(direction: Vector3) -> void`
- `play_death(hit_direction: HitDirection = HitDirection.FRONT, _headshot: bool = false) -> void`
- `play_door_kick() -> void`
- `is_door_kicking() -> bool`
