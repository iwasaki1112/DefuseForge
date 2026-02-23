# SpinePostureModifier

背骨姿勢制御SkeletonModifier3D。Hips → Spine → Chest → UpperChest にピッチ（前傾/後傾）、ロール（リーン）、ヨー（左右回転）を重み付き分配で適用する。ヨーは4方向ブレンド+スパイン回転で8方向表現する際に使用。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `SkeletonModifier3D` |
| ファイルパス | `scripts/modifiers/spine_posture_modifier.gd` |
| @tool | あり |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `chain_bones` | `PackedStringArray` | `["Hips", "Spine", "Chest", "UpperChest"]` | ボーンチェーン |
| `chain_weights` | `PackedFloat32Array` | `[0.0, 0.35, 0.35, 0.3]` | pitch/roll各ボーンの重み |
| `yaw_chain_weights` | `PackedFloat32Array` | `[0.0, 0.33, 0.33, 0.34]` | yaw各ボーンの重み（Hips除外がデフォルト） |
| `smoothing_speed` | `float` | `10.0` | 補間速度 |
| `use_hip_counter_shift` | `bool` | `true` | Hipsカウンターシフト有効 |
| `hip_counter_shift` | `float` | `0.03` | カウンターシフト量（m/rad） |

## Public API

### set_posture(pitch: float, roll: float) -> void
ピッチとロールを同時に設定。

### set_pitch(pitch: float) -> void
ピッチのみ設定（正=前傾、ラジアン）。

### set_roll(roll: float) -> void
ロールのみ設定（正=右傾、ラジアン）。

### set_yaw(yaw: float) -> void
ヨーのみ設定（正=右回転、ラジアン）。4方向ブレンドモードでCharacterAnimationControllerから自動駆動される。

### set_yaw_chain_weights(weights: PackedFloat32Array) -> void
ヨー重み配列を設定。プリセット例:
- **A: Hips含む全4ボーン**: `[0.25, 0.25, 0.25, 0.25]`
- **B: Hips除外（デフォルト）**: `[0.0, 0.33, 0.33, 0.34]`
- **C: 上部重め**: `[0.0, 0.2, 0.3, 0.5]`

## 内部動作

- rest poseの軸基準で変換（`get_bone_global_rest()`使用）
- ピッチ: ローカルX軸回転
- ロール: ローカル-Z軸回転
- ヨー: ローカルY軸回転（yaw_chain_weightsで独立重み制御）
- Hipsカウンターシフト: リーン方向と逆に微小横移動で重心補正
- pitch/roll/yaw全て < 0.001 の場合はスキップ（パフォーマンス最適化）
