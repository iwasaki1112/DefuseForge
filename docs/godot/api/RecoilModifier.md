# RecoilModifier

上半身ボーンにプロシージャルリコイルを適用するSkeletonModifier。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `SkeletonModifier3D` |
| ファイルパス | `scripts/modifiers/recoil_modifier.gd` |
| ツール対応 | `@tool`（エディタでも動作） |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `spine_bone_name` | `String` | `"mixamorig_Spine2"` | リコイル適用ボーン名 |
| `recoil_strength` | `float` | `0.1` | リコイル強度（デフォルト） |
| `recovery_speed` | `float` | `10.0` | リコイル回復速度 |

## Public API

### trigger_recoil(strength: float = -1.0) -> void
リコイルをトリガーする。

**引数:**
- `strength` - リコイル強度（-1.0でデフォルト値を使用）

## 使用例

```gdscript
# Skeleton3Dの子として追加
var recoil = RecoilModifier.new()
recoil.spine_bone_name = "mixamorig_Spine2"
recoil.recoil_strength = 0.1
recoil.recovery_speed = 10.0
skeleton.add_child(recoil)

# リコイルをトリガー
recoil.trigger_recoil(0.15)  # カスタム強度
recoil.trigger_recoil()      # デフォルト強度
```

## 内部動作

### リコイルアニメーション
1. `trigger_recoil()`で`_current_recoil`を設定
2. `_process_modification()`で毎フレーム処理:
   - 指定ボーンをローカルX軸周りに回転（上向き/後方へ傾く）
   - `lerp`で`_current_recoil`を0に向けて回復

### 回転計算
```gdscript
var recoil_rotation = Quaternion(Vector3.RIGHT, -_current_recoil)
skeleton.set_bone_pose_rotation(bone_idx, current_pose * recoil_rotation)
```

Mixamoリグの場合、Spine2ボーンに適用することで自然な反動表現が可能。
