# LeanModifier

上半身ボーンにリーン（ロール）を適用する`SkeletonModifier3D`。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `SkeletonModifier3D` |
| ファイルパス | `scripts/modifiers/lean_modifier.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `spine_bone_name` | `String` | `"mixamorig_Spine2"` | リーン適用対象のボーン名 |
| `recovery_speed` | `float` | `10.0` | リーンの補間速度 |

## Public API

### set_target_lean(angle_radians: float) -> void
リーン角度（ラジアン）を設定する。

**引数:**
- `angle_radians` - ロール角（ラジアン）。正で右、負で左。

## 内部動作

- 毎フレーム`_target_lean`へ補間し、`spine_bone_name`のローカル前方軸まわりに回転を適用
- `CharacterAnimationController` から利用される前提

## APIリファレンス

### シグナル
なし

### メソッド
- `set_target_lean(angle_radians: float) -> void`
