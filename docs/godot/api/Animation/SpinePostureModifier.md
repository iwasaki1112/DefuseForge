# SpinePostureModifier

背骨姿勢制御SkeletonModifier3D。Hips → Spine → Chest → UpperChest にピッチ（前傾/後傾）とヨー（左右回転）を重み付き分配で適用する。ヨーは4方向ブレンド+スパイン回転で8方向表現する際に使用。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `SkeletonModifier3D` |
| ファイルパス | `scripts/modifiers/spine_posture_modifier.gd` |
| class_name | `SpinePostureModifier` |
| @tool | なし |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `chain_bones` | `PackedStringArray` | `["Hips", "Spine", "Chest", "UpperChest"]` | ボーンチェーン |
| `chain_weights` | `PackedFloat32Array` | `[0.0, 0.35, 0.35, 0.3]` | pitch各ボーンの重み |
| `yaw_chain_weights` | `PackedFloat32Array` | `[0.0, 0.2, 0.3, 0.5]` | yaw各ボーンの重み（Hips除外、上部重め） |
| `smoothing_speed` | `float` | `10.0` | 補間速度 |

## Public API

### set_posture(pitch: float, roll: float) -> void
ピッチを設定（rollは互換性のために引数に残すが現在未使用）。

### set_pitch(pitch: float) -> void
ピッチのみ設定（正=前傾、ラジアン）。

### set_yaw(yaw: float) -> void
ヨーのみ設定（正=右回転、ラジアン）。SpineIKControllerから自動駆動される。

### set_yaw_chain_weights(weights: PackedFloat32Array) -> void
ヨー重み配列を設定。プリセット例:
- **A: Hips含む全4ボーン**: `[0.25, 0.25, 0.25, 0.25]`
- **B: Hips除外**: `[0.0, 0.33, 0.33, 0.34]`
- **C: 上部重め（デフォルト）**: `[0.0, 0.2, 0.3, 0.5]`

## 内部動作

- `_process_modification()`（旧API）でSkeletonModifier3Dパイプライン内から呼ばれる
- 各ボーンのアニメーション回転を取得し、オフセットとして回転を乗算（read-modify-write）
- rest basisの逆変換でワールド軸→ボーンローカル軸に変換
  - ピッチ: `(inv_rest_basis * Vector3.RIGHT).normalized()`
  - ヨー: `(inv_rest_basis * Vector3.UP).normalized()`
- pitch/yaw全て < 0.001 の場合はスキップ（パフォーマンス最適化）
- スムージング: `lerpf` + `exp(-smoothing_speed * dt)` で滑らかに追従

## 処理順

SkeletonModifier3D処理順で SpineCCDIK → SpineTwistDisperser の直後に配置:

```
[0] SpineCCDIK (influence=0, 将来拡張用)
[1] SpineTwistDisperser (influence=0, 将来拡張用)
[2] SpinePostureModifier ← ここ
[3] HeadRotationModifier
[9] RightArmIK
[10] LeftHandTargetSync
[11] LeftHandIK
```
