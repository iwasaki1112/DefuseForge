# LeftHandIKModifier

TwoBoneIK3Dによる左手IKの制御を管理するノード。武器モデル内のグリップノードに左手を追従させ、リアルな武器保持を実現する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/modifiers/left_hand_ik_modifier.gd` |

## 概要

Marker3D経由でグリップノードを毎フレーム追跡する。`_process()`内でMarker3Dの位置を更新することで、SkeletonModifier3Dパイプライン実行時に正しいターゲット位置が確定している。

旧方式（TwoBoneIK3Dのtarget_nodeを直接gripノードに設定）では、modifier pipeline中にBoneAttachment3Dが未更新のためグリップ位置がずれていた。Marker3D経由にすることで、`_process()`時点のグリップ位置（前フレームのBoneAttachment3D更新済み）を使用できる。

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `DEFAULT_BLEND_SPEED` | `15.0` | influence遷移速度 |
| `DEFAULT_POLE_OFFSET` | `0.3` | ポールターゲットのデフォルトオフセット（肘方向制御） |

## Public API

### setup(skeleton: Skeleton3D, model: Node3D) -> void
IKノードとターゲットを作成してスケルトンに追加する。

**引数:**
- `skeleton`: IKチェーンを構築するSkeleton3D
- `model`: キャラクターモデル参照

**処理内容:**
1. IKターゲット用Marker3D（`LeftHandIKTarget`）を作成
2. ポールターゲット用Marker3D（`LeftHandIKPole`）を作成
3. TwoBoneIK3Dノードを作成、IKチェーンを設定
4. ターゲットは常にMarker3D

### set_enabled(enabled: bool) -> void
IKの有効/無効を設定する。influenceはlerpで滑らかに遷移する。

### disable_immediate() -> void
IKを即座に無効化する（死亡時など、遷移なし）。

### set_grip_source(grip_node: Node3D) -> void
武器モデル内のグリップソースノードを設定する。Marker3D経由で毎フレーム追跡。

### clear_grip_source() -> void
グリップソースをクリアする。

### has_grip_source() -> bool
グリップソースが有効に設定されているかを返す。

### is_enabled() -> bool
IKが有効かどうかを返す（target_influence > 0.5）。

### set_grip_offset(offset: Vector3) -> void
グリップ位置オフセットを設定（武器ローカル空間）。

### set_pole_offset(offset: Vector3) -> void
ポールオフセットを設定（キャラクター空間XYZ）。

## 内部動作

### _process(delta)
毎フレーム以下を処理:
1. **influence遷移**: 現在のinfluenceを目標値に向けてlerp
2. **グリップ追跡**: `_grip_source.global_transform`をMarker3Dにコピー（+ grip_offset適用）
3. **ポール位置更新**: 肩と手の中点 + キャラクター空間オフセット

### _exit_tree()
IKノード、ターゲット、ポールをqueue_freeでクリーンアップ。

## 使用例

```gdscript
# CharacterAnimationController内での使用
var left_hand_ik = LeftHandIKModifier.new()
character.add_child(left_hand_ik)
left_hand_ik.setup(skeleton, model)

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
      └─ LeftHand (end) → Marker3D (target, grip position copy)
```

## 関連クラス
- [CharacterAnimationController](CharacterAnimationController.md) - IKの管理親
- [UpperBodyIKController](UpperBodyIKController.md) - 上半身IK統合コントローラー
- [GameConstants](../Util/GameConstants.md) - ボーン名定数
