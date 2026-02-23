# UpperBodyIKController

上半身IK統合コントローラー。右腕IK + 左手IK + 背骨姿勢 + 頭部追従 + リコイルを一元管理する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/modifiers/upper_body_ik_controller.gd` |

## アーキテクチャ

```
UpperBodyIKController (Node)
  ├── SpinePostureModifier (SkeletonModifier3D) - 背骨姿勢
  ├── RightArmIK (TwoBoneIK3D) - 右腕IK
  ├── LeftHandIKModifier (Node) - 左手IK（既存）
  ├── HeadLookAt (LookAtModifier3D) - 頭部追従
  └── IKRecoilController (Node) - リコイル
```

### SkeletonModifier3D 処理順序（Skeleton3D子ノード順）

1. SpinePostureModifier ← 背骨姿勢（ピッチ/リーン）
2. RightArmIK (TwoBoneIK3D) ← 右腕IK
3. LeftHandIK (TwoBoneIK3D) ← 左腕IK
4. HeadLookAt (LookAtModifier3D) ← 頭部追従

## IKState

| 状態 | 説明 |
|------|------|
| `READY` | 通常の構え位置 |
| `GUN_UP` | 壁/味方接近時の武器上げ |
| `ACTION` | IKActionPlayerが制御中 |
| `DISABLED` | IK全無効（死亡/アクション時） |

## IK位置定数（キャラクター原点基準、+Z前方）

| 定数 | 値 | 用途 |
|------|-----|------|
| `RIFLE_READY_HAND` | `(-0.19, 1.39, 0.13)` | ライフル構え時の右手位置 |
| `RIFLE_READY_POLE` | `(-0.22, 1.13, -0.06)` | ライフル構え時の右肘方向 |
| `PISTOL_READY_HAND` | `(-0.15, 1.36, 0.23)` | ピストル構え時の右手位置 |
| `PISTOL_READY_POLE` | `(-0.22, 0.99, -0.06)` | ピストル構え時の右肘方向 |
| `GUN_UP_HAND` | `(-0.15, 1.55, 0.03)` | 武器上げ時の右手位置 |
| `GUN_UP_POLE` | `(-0.22, 1.25, -0.10)` | 武器上げ時の右肘方向 |

## 座標変換

```gdscript
# キャラクター原点基準 → ワールド座標
world_pos = char_pos + model_basis * local_pos
```

## Public API

### setup(skeleton, model, left_hand_ik) -> void
IKノードを構築して初期化。

### set_state(new_state: IKState) -> void
IK状態を切り替え。

### set_weapon(weapon_type: int) -> void
武器タイプを設定（ピストル時は左手IK無効）。

### set_aim_direction(direction: Vector3) -> void
エイム方向を設定（HeadLookAt + 将来のSpine Aim用）。

### trigger_recoil(strength: float) -> void
IKリコイルを発動。

### set_posture_lean(roll: float) -> void
SpinePostureModifierにリーンを伝播。

### disable_immediate() -> void
IKを即座に全無効化（死亡時用）。

### update(delta: float) -> void
毎フレーム更新。CharacterAnimationControllerから呼ばれる。
