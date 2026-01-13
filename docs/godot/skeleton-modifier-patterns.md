# Skeleton Modifier パターン

Godot 4.x でアニメーション後にボーンを操作するためのパターン。

## SkeletonModifier3D の基本

アニメーション処理後にボーンを操作する場合は `SkeletonModifier3D` を継承する。

```gdscript
@tool
class_name MyBoneModifier
extends SkeletonModifier3D

func _process_modification() -> void:
    var skeleton := get_skeleton()
    # ボーン操作処理
```

### 重要なポイント

1. **実行タイミング**: `_process_modification()` はアニメーション適用後に自動実行される
2. **実行順序**: Skeleton3D の子ノード追加順で決まる
3. **influence**: 0.0〜1.0 でブレンド量を制御可能

## 上半身回転（Upper Body Twist）

敵の方向を向くなど、下半身は進行方向のまま上半身だけ回転させるパターン。

### 実装: `UpperBodyRotationModifier`

```
scripts/utils/upper_body_rotation_modifier.gd
```

### 設計判断

| 問題 | 解決策 |
|------|--------|
| 単一ボーン回転だと不自然 | Spine, Chest, UpperChest の3ボーンに分散 |
| アニメーションに上書きされる | SkeletonModifier3D で後処理として実行 |
| IKとの競合 | 追加順序で制御（回転 → IK の順） |

### 回転の分散

```gdscript
var per_bone_angle = total_rotation / bone_count
for bone_idx in spine_bones:
    var current = skeleton.get_bone_pose_rotation(bone_idx)
    var twist = Quaternion(Vector3.UP, per_bone_angle)
    skeleton.set_bone_pose_rotation(bone_idx, current * twist)
```

## IK との組み合わせ

上半身回転と左手IK（武器グリップ）を組み合わせる場合の実行順序：

```
1. AnimationTree がポーズを適用
2. UpperBodyRotationModifier が上半身を回転
3. TwoBoneIK3D (LeftHandIK) が左手位置を調整
```

### 順序の制御

Skeleton3D への子ノード追加順で決まる：

```gdscript
# animation_component.gd で先に追加
skeleton.add_child(upper_body_modifier)

# weapon_component.gd で後から追加
skeleton.add_child(left_hand_ik)
```

両方とも `active = true` にして自動実行させる。

## 関連ファイル

- `scripts/utils/upper_body_rotation_modifier.gd` - 上半身回転モディファイア
- `scripts/utils/two_bone_ik_3d.gd` - 2ボーンIK実装
- `scripts/characters/components/animation_component.gd` - アニメーション管理
- `scripts/characters/components/weapon_component.gd` - 武器・IK管理
