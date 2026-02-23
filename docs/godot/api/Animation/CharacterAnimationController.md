# CharacterAnimationController

キャラクターアニメーションを管理するコントローラークラス。上半身を完全にIKで制御し、下半身は武器非依存のBlendSpace2Dアニメーションを維持する。8方向モード（従来）と4方向+SpineYawモード（新規）を切替可能。

> **重要: ARPモデルの向きについて**
>
> | 項目 | 方向 |
> |------|------|
> | ARPモデルの前方向 | **+Z** |
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

## アーキテクチャ

```
CharacterAnimationController
  ├── AnimationTree (下半身のみ実質制御)
  │     output → TimeScale → SpeedBlend → IdleBlend → WalkBlend
  │
  └── UpperBodyIKController
        ├── SpinePostureModifier (背骨姿勢)
        ├── RightArmIK (TwoBoneIK3D)
        ├── LeftHandIKModifier (左手追従)
        ├── HeadLookAt (LookAtModifier3D)
        └── IKRecoilController (射撃リコイル)
```

IKの`influence=1.0`がアニメーションポーズを上書きするため、AnimationTreeへの上半身フィルター設定は不要。

## Enums

### Weapon
武器タイプ。

| 値 | 説明 |
|----|------|
| `NONE` | 武器なし |
| `RIFLE` | ライフル |
| `PISTOL` | ピストル |

### BlendMode
歩行ブレンドモード。

| 値 | 説明 |
|----|------|
| `EIGHT_DIR` | 8方向BlendSpace2D（従来方式） |
| `FOUR_DIR_SPINE` | 4方向BlendSpace2D + SpinePostureModifierのyaw回転で8方向表現 |

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
| `throw_release` | なし | グレネードリリースタイミング |
| `throw_finished` | なし | 投擲アニメーション完了 |
| `door_open_finished` | なし | ドア開けアニメーション完了 |
| `door_open_impact` | なし | ドアを実際に開くインパクトタイミング |
| `melee_impact` | なし | 近接攻撃のインパクトタイミング |
| `melee_finished` | なし | 近接攻撃アニメーション完了 |

## Export Properties

### Movement Speed
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `walk_speed` | `float` | `2.0` | 歩行速度 |
| `rotation_speed` | `float` | `15.0` | 回転速度 |

### Recoil
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `rifle_recoil_strength` | `float` | `0.16` | ライフルのリコイル強度 |
| `pistol_recoil_strength` | `float` | `0.24` | ピストルのリコイル強度 |
| `rifle_fire_rate` | `float` | `0.1` | ライフルの発射間隔 |
| `pistol_fire_rate` | `float` | `0.2` | ピストルの発射間隔 |
| `recoil_recovery` | `float` | `10.0` | リコイル回復速度 |

### Lean
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `max_lean_degrees` | `float` | `10.0` | 移動リーンの最大角度（度） |
| `lean_speed` | `float` | `10.0` | リーンの補間速度 |
| `lean_deadzone` | `float` | `0.15` | 小さな横移動を無視する閾値 |

### Turn Lean
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `turn_lean_degrees` | `float` | `15.0` | 方向転換時の最大リーン角度（度） |
| `turn_lean_smoothing` | `float` | `15.0` | 角速度スムージング速度 |
| `turn_lean_angular_ref` | `float` | `1.5` | 最大リーンとなる角速度（rad/s） |

## Public API

### setup(model: Node3D, anim_player: AnimationPlayer) -> void
アニメーションコントローラーをセットアップする。UpperBodyIKControllerとAnimationTreeを初期化。

### update_animation(movement_direction: Vector3, aim_direction: Vector3, is_running: bool, delta: float) -> void
毎フレーム呼び出してアニメーションを更新する。上半身IKと下半身AnimationTreeの両方を更新。

### set_weapon(weapon: Weapon) -> void
武器タイプを設定する。ロコモーションアニメーションは武器非依存（変化しない）。IK状態のみUpperBodyIKControllerに伝播。

### set_left_hand_grip(grip_node: Node3D) -> void
左手IKのグリップソースを設定する。UpperBodyIKController経由。

### set_gun_down(value: bool) -> void
Gun down状態を設定する。UpperBodyIKControllerのIKState(GUN_DOWN/READY)を切り替え。壁/味方接近時に武器を下げる。

### fire() -> void
発射アクションをトリガーする。IKリコイルを発動（UpperBodyIKController経由）。

### play_death(hit_direction: HitDirection, headshot: bool) -> void
デスアニメーションを再生する。IKを全無効化→AnimationPlayer直接再生。

### play_door_open() -> void
ドア開けアニメーションを再生する。IK無効化→全身AnimationPlayer再生→復帰。

### play_throw_far() / play_throw_close() -> void
投擲アニメーションを再生する。IK無効化→全身AnimationPlayer再生→復帰。

### play_melee() -> void
近接攻撃アニメーションを再生する。IK無効化→全身AnimationPlayer再生→復帰。

### play_talking() / stop_talking() -> void
会話アニメーションのループ再生/停止。IK無効化→全身AnimationPlayer再生→復帰。

### set_blend_mode(mode: BlendMode) -> void
歩行ブレンドモードを切り替える。AnimationTree内のWalkBlendノードをランタイムで差し替え。
- `EIGHT_DIR`: 8方向BlendSpace2D（45度量子化）
- `FOUR_DIR_SPINE`: 4方向BlendSpace2D（90度量子化）+ SpinePostureModifierのyaw回転で残差角度を表現

### set_spine_posture_modifier(modifier: SpinePostureModifier) -> void
SpinePostureModifierを登録する。`FOUR_DIR_SPINE`モードでyaw回転を自動駆動するために必要。

## ネットワーク同期

プロトコル `"move_state,is_firing,blend_x,blend_y,gun_down"` は変更なし。

- `get_animation_state()` → エンコード
- `apply_animation_state(state, delta)` → デコード・適用（リモートキャラクター用）

## 内部動作

- AnimationTree構成: output → TimeScale → SpeedBlend → IdleBlend → WalkBlend
- **武器非依存ロコモーション**: 統一`game_*`アニメーション10種（idle + 8方向walk + sprint）
  - 武器切替時にロコモーションアニメーションは変化しない（`_switch_weapon_animations()`撤廃済み）
  - 上半身差分はIKで完全制御されるため武器別アニメーション不要
- **フォールバック**: 新`game_*`アニメーション未作成時は`game_rifle_*`にフォールバック（`_resolve_anim_name()`）
- **ブレンドモード**: 8方向（デフォルト）と4方向+SpineYaw（新）を切替可能
  - 8方向: 45度量子化、8点BlendSpace2D
  - 4方向+SpineYaw: 90度量子化、4点BlendSpace2D、残差角度（±45°）をSpinePostureModifier.set_yaw()で駆動
  - スプリント中はresidual=0（前方のみ）
  - 停止時はset_yaw(0.0)でスパインを戻す
  - `_rebuild_walk_blend_space()`でランタイムにWalkBlendノードを差し替え
- 上半身はUpperBodyIKController（TwoBoneIK3D + LookAtModifier3D + SpinePostureModifier）で制御
- IKのinfluence=1.0がアニメーションポーズを上書き → 上半身フィルター不要
- **腕IKとの共存**: SpinePostureModifier(index 0)→腕IK(index 2+)の処理順。スパインyaw適用後にTwoBoneIK3Dがワールド空間ターゲットに解決
- アクション（投擲/ドア/近接）時はIK無効化→AnimationPlayer全身再生→IK復帰（アクション用アニメーションは武器別のまま維持）
- 死亡/会話はIK全無効化→AnimationPlayer直接再生
