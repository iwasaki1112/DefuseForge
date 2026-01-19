# Mixamoアニメーションの上半身・下半身ブレンド

Mixamoアニメーションで異なるソースから上半身と下半身を組み合わせる際の手順。

## 問題点

Mixamoのリグでは**Hips**がルートボーンであり、上半身のボーン（Spine以上）はHipsの子孫として動作する。そのため、異なるアニメーションから上半身と下半身を単純に組み合わせると：

1. **横揺れ**: 元のHipsの動き（位置・回転）が上半身に影響し、不自然な揺れが発生
2. **カクつき**: BEZIERハンドルの異常な値により、`fc.evaluate()`が予期しない値を返す
3. **不整合**: 下半身のHipsと上半身の動きが同期せず、体がねじれる

## 解決策

### 1. 下半身ソースの安定化

下半身のソースアニメーション（foot_only等）のHipsを安定化：

```python
# Hips location X と Z を0に固定（横揺れ・ルートモーション除去）
for fc in action.fcurves:
    if 'mixamorig:Hips' in fc.data_path and 'location' in fc.data_path:
        if fc.array_index in [0, 2]:  # X and Z
            for kp in fc.keyframe_points:
                kp.co.y = 0.0
                kp.handle_left.y = 0.0
                kp.handle_right.y = 0.0

# Spine系の横揺れ成分を固定
for bone in ['mixamorig:Spine', 'mixamorig:Spine1', 'mixamorig:Spine2']:
    for fc in action.fcurves:
        if bone in fc.data_path and 'rotation_quaternion' in fc.data_path:
            if fc.array_index in [1, 3]:  # Y and W components
                values = [kp.co.y for kp in fc.keyframe_points]
                avg = sum(values) / len(values)
                for kp in fc.keyframe_points:
                    kp.co.y = avg
```

### 2. バックアップの作成

元のアニメーションを壊さないよう、必ずバックアップを作成：

```python
backup = original_action.copy()
backup.name = '_backup_' + original_action.name
```

### 3. キーフレーム値の直接使用

`fc.evaluate()`はBEZIER補間で異常な値を返すことがある。キーフレームの値を直接使用：

```python
# NG: fc.evaluate()を使用
value = fc.evaluate(src_frame)

# OK: キーフレーム値を直接取得
kp_values = {int(kp.co.x): kp.co.y for kp in fc.keyframe_points}
src_frame_int = int(round(src_frame))
value = kp_values.get(src_frame_int, kp_values[min(kp_values.keys(), key=lambda x: abs(x - src_frame_int))])
```

### 4. Hips補正（重要）

上半身のSpine回転に、Hipsの回転差分を適用して吸収：

```python
from mathutils import Quaternion

# 各フレームで:
# 元のHips回転
old_hips_rot = get_hips_rotation(upper_source, src_frame)
# 新しいHips回転
new_hips_rot = get_hips_rotation(lower_source, target_frame)
# 元のSpine回転
old_spine_rot = get_spine_rotation(upper_source, src_frame)

# 補正計算: 新Hips^-1 * 元Hips * 元Spine
new_spine_rot = new_hips_rot.inverted() @ old_hips_rot @ old_spine_rot
```

この計算により、Spineのワールド空間での回転が維持され、新しいHipsの動きに追従する。

### 5. ボーンの分類

```python
# 下半身ボーン（lower_sourceから取得）
lower_body_bones = {
    'mixamorig:Hips',
    'mixamorig:LeftUpLeg', 'mixamorig:LeftLeg', 'mixamorig:LeftFoot',
    'mixamorig:LeftToeBase', 'mixamorig:LeftToe_End',
    'mixamorig:RightUpLeg', 'mixamorig:RightLeg', 'mixamorig:RightFoot',
    'mixamorig:RightToeBase', 'mixamorig:RightToe_End',
}

# 上半身ボーン（upper_sourceから取得、Spine回転は補正必要）
# Spine, Spine1, Spine2, Neck, Head, Shoulder, Arm, Hand等
```

## 完全なマージ手順

1. **下半身ソースを安定化**（Hips X/Z=0、Spine横揺れ固定）
2. **元のアニメーションをバックアップ**
3. **ターゲットアクションをクリア**
4. **下半身をコピー**（安定化済みソースから）
5. **上半身をコピー**（バックアップから、フレームスケーリング）
   - Spine回転にはHips補正を適用
   - その他のボーンはキーフレーム値を直接使用
6. **補間をLINEARに設定**（BEZIER問題を回避）

## 注意点

- 元のアニメーションのHipsが既に安定している場合（location X/Z = 0）でも、回転の差分があればSpine補正は必要
- 79フレーム→31フレーム等のスケーリングでは情報が失われるため、キーフレーム値の最近傍を使用
- `bpy.ops.wm.revert_mainfile()`を使うと未保存のアクションが消えるので注意
