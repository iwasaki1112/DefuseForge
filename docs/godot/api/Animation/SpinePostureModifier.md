# SpinePostureModifier

背骨姿勢制御SkeletonModifier3D。Hips → Spine → Chest → UpperChest にピッチ（前傾/後傾）とロール（リーン）を重み付き分配で適用する。

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
| `chain_weights` | `PackedFloat32Array` | `[0.1, 0.2, 0.3, 0.4]` | 各ボーンの重み |
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

## 内部動作

- rest poseの軸基準で変換（`get_bone_global_rest()`使用）
- ピッチ: ローカルX軸回転
- ロール: ローカル-Z軸回転
- Hipsカウンターシフト: リーン方向と逆に微小横移動で重心補正
