# LeftHandIKModifier

TwoBoneIK3Dによる左手IKの制御を管理するノード。武器モデル内のグリップノードに左手を追従させ、リアルな武器保持を実現する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/modifiers/left_hand_ik_modifier.gd` |

## 概要

武器モデル内の`LeftHandGrip`ノードにTwoBoneIK3Dのターゲットを直接向けることで、遅延ゼロの左手追従を実現する。IKチェーンは`LeftUpperArm → LeftLowerArm → LeftHand`。

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `IK_BLEND_SPEED` | `15.0` | influence遷移速度 |
| `POLE_DOWN_OFFSET` | `0.3` | ポールターゲットの下方向オフセット（肘方向制御） |

## Public API

### setup(skeleton: Skeleton3D) -> void
IKノードとターゲットを作成してスケルトンに追加する。

**処理内容:**
1. フォールバック用Marker3D（`LeftHandIKTarget`）を作成
2. ポールターゲット用Marker3D（`LeftHandIKPole`）を作成
3. TwoBoneIK3Dノードを作成、IKチェーンを設定
4. 初期ターゲットはフォールバック用Marker3D

### set_enabled(enabled: bool) -> void
IKの有効/無効を設定する。influenceはlerpで滑らかに遷移する。

### disable_immediate() -> void
IKを即座に無効化する（死亡時など、遷移なし）。

### set_grip_source(grip_node: Node3D) -> void
武器モデル内のグリップソースノードを設定する。TwoBoneIK3Dのtarget_nodeを直接gripノードに向けることで遅延なし追従を実現。

### clear_grip_source() -> void
グリップソースをクリアし、ターゲットをフォールバック用Marker3Dに戻す。

### has_grip_source() -> bool
グリップソースが有効に設定されているかを返す。

### is_enabled() -> bool
IKが有効かどうかを返す（target_influence > 0.5）。

## 内部動作

### _process(delta)
毎フレーム以下を処理:
1. **influence遷移**: 現在のinfluenceを目標値に向けてlerp
2. **ポール位置更新**: gripソースとルートボーンの中点から下方向にオフセット（肘が下を向くように制御）

### _exit_tree()
IKノード、ターゲット、ポールをqueue_freeでクリーンアップ。

## 使用例

```gdscript
# CharacterAnimationController内での使用
var left_hand_ik = LeftHandIKModifier.new()
character.add_child(left_hand_ik)
left_hand_ik.setup(skeleton)

# 武器装備時
var grip = weapon_model.find_child("LeftHandGrip")
left_hand_ik.set_grip_source(grip)
left_hand_ik.set_enabled(true)

# 武器解除時
left_hand_ik.clear_grip_source()
```

## IKチェーン

```
LeftUpperArm (root)
  └─ LeftLowerArm (middle)
      └─ LeftHand (end) → LeftHandGrip (target)
```

## 関連クラス
- [CharacterAnimationController](CharacterAnimationController.md) - IKの管理親
- [GameConstants](../Util/GameConstants.md) - ボーン名定数
