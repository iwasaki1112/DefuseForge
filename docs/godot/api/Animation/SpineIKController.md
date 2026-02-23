# SpineIKController

## 概要
Godot 4.6の`CCDIK3D` + `BoneTwistDisperser3D`を使用したスパインIKコントローラー。
4方向ブレンド+スパインIKで8方向ストレイフを再現する。

購入アセット "GODOT 4.6 - NEW IK AIM" のスパインIKアプローチを参考に実装。

## クラス情報
- **ファイル**: `scripts/modifiers/spine_ik_controller.gd`
- **継承**: `Node`
- **class_name**: `SpineIKController`

## アーキテクチャ

### SkeletonModifier3Dパイプライン
```
SpineCCDIK (CCDIK3D)         ← スパインチェーン（Spine→Head）をターゲットへ追従
  ↓
SpineTwistDisperser           ← ツイストを自然に分配
  ↓
SpinePostureModifier          ← ピッチ（前傾）を付加
  ↓
HeadRotationModifier          ← 首回転
  ↓
RightArmIK (TwoBoneIK3D)     ← 右腕IK
  ↓
LeftHandTargetSync            ← 左手ターゲット同期
  ↓
LeftHandIK (TwoBoneIK3D)     ← 左手IK
```

### TargetPivotシステム
```
GameCharacter (CharacterBody3D)
  ├── CharacterModel (Node3D)
  │     └── Skeleton3D
  │           ├── SpineCCDIK (CCDIK3D)
  │           └── SpineTwistDisperser (BoneTwistDisperser3D)
  └── SpineIKTargetPivot (Marker3D)  ← 位置/回転を毎フレーム更新
        └── SpineIKTarget (Marker3D)  ← CCDIKのターゲット
```

- TargetPivotはキャラクタールートの子
- 毎フレーム: 位置=キャラクター位置+(0, 1.2, 0)、回転=モデル向き+残差ヨー
- SpineIKTargetはTargetPivotから前方オフセット(0, 0.9, 0.15)

## セットアップ

```gdscript
var spine_ik := SpineIKController.new()
spine_ik.name = "SpineIKController"
add_child(spine_ik)
spine_ik.setup(skeleton, model, character)

# CharacterAnimationControllerに登録
anim_ctrl.set_spine_ik_controller(spine_ik)

# ブレンドモードを設定
anim_ctrl.set_blend_mode(CharacterAnimationController.BlendMode.FOUR_DIR_IK)
```

## Public API

| メソッド | 説明 |
|----------|------|
| `setup(skeleton, model, character_root)` | IKノードを構築 |
| `set_yaw(yaw: float)` | 残差ヨー角度を設定（rad） |
| `set_enabled(enabled: bool)` | 有効/無効切替（influence制御） |
| `update(delta: float)` | 毎フレーム更新（TargetPivot位置/回転） |
| `get_current_yaw() -> float` | 現在のスムーズ済みヨー角度 |
| `is_setup() -> bool` | セットアップ済みか |
| `is_enabled() -> bool` | 有効状態か |

## CCDIK3D設定

- **Root Bone**: Spine
- **End Bone**: Head
- **Joint Count**: 5 (Spine, Chest, UpperChest, Neck, Head)
- **Joint Limits** (JointLimitationCone3D):
  - Spine: 54°, Chest: 29°, UpperChest: 32°, Neck: 14°, Head: 制限なし

## BoneTwistDisperser3D設定

- **Root Bone**: Spine
- **End Bone**: Neck
- **Joint Count**: 4
- **Twist From Rest**: true
- **Disperse Mode**: 0

## 動作原理

4方向ブレンドモードでは:
1. 移動方向を90°単位に量子化（F/R/B/L）
2. 実際の移動方向と量子化方向の差分＝残差角度（±45°以内）
3. 残差角度でTargetPivotを回転
4. CCDIK3Dがスパインチェーンをターゲットに追従させ、自然な上半身ツイストを生成
5. BoneTwistDisperser3Dがツイストを各ボーンに自然分配

## 関連クラス
- `CharacterAnimationController` — ブレンドモード管理、残差角度計算
- `SpinePostureModifier` — ピッチ/ロール制御（SpineIKと併用）
- `UpperBodyIKController` — 腕IK管理
