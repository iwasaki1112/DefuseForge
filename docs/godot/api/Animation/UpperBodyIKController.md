# UpperBodyIKController

上半身IK統合コントローラー。右腕IK（TwoBoneIK3D）、左腕IK（LeftHandIKModifier）、SpineAimModifier を一元管理する。

下半身（脚）は既存の AnimationTree 駆動を維持し、上半身のみ IK で制御する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/modifiers/upper_body_ik_controller.gd` |

## アーキテクチャ

```
AnimationTree → 全身アニメーション適用（脚の歩行はそのまま機能）
  ↓ (SkeletonModifier3D が後処理で上半身を上書き)
SpineAimModifier → Spine/Chest/UpperChest の回転（移動リーン + ポーズリーン）
RightArmIK (TwoBoneIK3D) → 右手をステートに応じた位置へ
LeftHandIK (LeftHandIKModifier) → 左手を武器グリップへ
RecoilModifier → リコイル加算（IK後に適用、外部で追加）
```

**循環参照なし**: 右腕IKターゲットはゲームステートから計算。武器はBoneAttachmentで右手に追従。左手は武器のLeftHandGripにIK追従。

## 定数

| 定数 | 型 | 値 | 説明 |
|------|-----|-----|------|
| `DEFAULT_BLEND_SPEED` | `float` | `15.0` | デフォルト influence 遷移速度 |
| `ACTION_BLEND_SPEED` | `float` | `5.0` | アクション復帰時のゆっくりブレンド速度 |
| `RIGHT_POLE_OFFSET` | `float` | `0.3` | 右肘ポール外側オフセット |
| `READY_RIGHT_HAND_POS` | `Vector3` | `(0.2, 0.7, 0.25)` | READY状態の右手IK位置（スケルトンローカル） |
| `GUN_DOWN_RIGHT_HAND_POS` | `Vector3` | `(0.2, 0.4, 0.1)` | GunDown状態の右手IK位置（スケルトンローカル） |
| `GUN_DOWN_POSE_LEAN` | `float` | `0.15` | GunDown時のポーズリーン（前傾、ラジアン） |

## Public API

### setup(skeleton: Skeleton3D) -> void
IKノードを生成しスケルトンに追加する。

**引数:**
- `skeleton` - キャラクターの Skeleton3D

**生成するノード（順序重要）:**
1. SpineAimModifier → Skeleton3D の子
2. RightHandIKTarget (Marker3D) + RightHandIKPole (Marker3D) + RightArmIK (TwoBoneIK3D) → Skeleton3D の子
3. LeftHandIKModifier → UpperBodyIKController の子（内部で Skeleton3D 上にもノード生成）

### set_left_grip(grip_node: Node3D) -> void
左手グリップを設定する。武器の LeftHandGrip ノードを渡す。

**動作:**
- `grip_node` が null でない場合: グリップソースを設定し、ピストルでなければ左手IKを有効化
- `grip_node` が null の場合: グリップソースをクリア

### has_left_grip() -> bool
左手グリップが設定されているか確認する。

### set_is_pistol(pistol: bool) -> void
武器タイプを変更する。ピストル時は左手IKを無効化（片手持ち）。

### set_gun_down(value: bool) -> void
Gun down状態を設定する。

**動作:**
- `true`: 右手ターゲットを `GUN_DOWN_RIGHT_HAND_POS` に変更、左手IK無効化、ポーズリーン前傾
- `false`: 右手ターゲットを `READY_RIGHT_HAND_POS + _weapon_ik_offset` に復帰、左手IK復帰、ポーズリーン解除

### is_gun_down() -> bool
Gun down状態か確認する。

### set_weapon_ik_offset(offset: Vector3) -> void
武器固有の右手IKオフセットを設定する。`WeaponPreset.right_hand_ik_offset` から設定される。

### set_lean(angle_radians: float) -> void
移動リーン角度を設定する。SpineAimModifier に委譲。

### disable_for_action() -> void
アクションアニメーション前に全IKを即座に無効化する。

**使用タイミング:** 投擲、ドア開け、近接攻撃、会話アニメーション開始前

### resume_after_action() -> void
アクション後にIKを段階的に復帰する（`ACTION_BLEND_SPEED` でゆっくりブレンドイン）。

### reset_blend_speed() -> void
ブレンド速度をデフォルト（`DEFAULT_BLEND_SPEED`）に戻す。

### disable_immediate() -> void
死亡時などの即座無効化。右腕IK influence を即座に0にし、左手IKも即座無効化。

## 内部動作

- `_process()` で毎フレーム右腕IKの influence ブレンドとターゲット位置更新を実行
- 右手ターゲット位置はスケルトンローカル座標で管理し、`_skeleton.global_transform` でグローバル変換
- 右肘ポール: 肩と手の中点から、キャラクター右方向 + 後方にオフセット
- `_exit_tree()` でスケルトン上の生成ノード（SpineAimModifier, TwoBoneIK3D, Marker3D）をクリーンアップ

## 使用例

```gdscript
# CharacterAnimationController 内でのセットアップ
_upper_body_ik = UpperBodyIKController.new()
_upper_body_ik.name = "UpperBodyIK"
_model.add_child(_upper_body_ik)
_upper_body_ik.setup(_skeleton)

# 武器装備時
_upper_body_ik.set_left_grip(weapon_model.get_node_or_null("LeftHandGrip"))
_upper_body_ik.set_is_pistol(weapon.category == WeaponPreset.WeaponCategory.PISTOL)
_upper_body_ik.set_weapon_ik_offset(weapon.right_hand_ik_offset)

# アクション（ドア開け等）
_upper_body_ik.disable_for_action()
# ... アニメーション再生 ...
_upper_body_ik.resume_after_action()
```

## APIリファレンス

### シグナル
なし

### メソッド
- `setup(skeleton: Skeleton3D) -> void`
- `set_left_grip(grip_node: Node3D) -> void`
- `has_left_grip() -> bool`
- `set_is_pistol(pistol: bool) -> void`
- `set_gun_down(value: bool) -> void`
- `is_gun_down() -> bool`
- `set_weapon_ik_offset(offset: Vector3) -> void`
- `set_lean(angle_radians: float) -> void`
- `disable_for_action() -> void`
- `resume_after_action() -> void`
- `reset_blend_speed() -> void`
- `disable_immediate() -> void`
