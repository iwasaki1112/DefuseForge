# SpineAimModifier

上半身プロシージャル回転モディファイア。Spine/Chest/UpperChest の回転を武器ポーズと移動リーンに応じて制御する。

LeanModifier の機能を統合し、ポーズリーン（前傾/後傾）を追加。

> **Note:** LeanModifier の後継。移動リーン（ロール）に加え、ポーズリーン（ピッチ: GunDown時の前傾等）をサポート。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `SkeletonModifier3D` |
| ファイルパス | `scripts/modifiers/spine_aim_modifier.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `chain_bones` | `PackedStringArray` | `["Hips", "Spine", "Chest", "UpperChest"]` | 回転を分配するボーンチェーン |
| `chain_weights` | `PackedFloat32Array` | `[0.1, 0.2, 0.3, 0.4]` | 各ボーンへの回転分配ウェイト（合計1.0） |
| `lean_recovery_speed` | `float` | `10.0` | リーンの補間速度 |
| `use_hip_counter_shift` | `bool` | `true` | Hips の横方向カウンターシフト（重心補正）を有効化 |
| `hip_counter_shift` | `float` | `0.03` | カウンターシフト量（meters per radian） |

## Public API

### set_target_lean(angle_radians: float) -> void
移動リーン角度を設定する（ロール: Z軸回転）。

**引数:**
- `angle_radians` - ロール角（ラジアン）。正で右、負で左。

### set_pose_lean(angle_radians: float) -> void
ポーズリーンを設定する（ピッチ: X軸回転）。GunDown時の前傾などに使用。

**引数:**
- `angle_radians` - ピッチ角（ラジアン）。正で前傾、負で後傾。

## 内部動作

- `_process_modification()` で毎フレーム処理（SkeletonModifier3Dの仕組み）
- `chain_bones` に指定したボーンに `chain_weights` で重み付き回転を分配
- 移動リーン: 各ボーンのローカル前方軸（Z）まわりにロール適用
- ポーズリーン: 各ボーンのローカル右方軸（X）まわりにピッチ適用
- Hips カウンターシフト: リーン方向と逆に微小な横移動を加え重心補正
- 指数減衰補間（`1.0 - exp(-speed * dt)`）でスムーズに遷移

## LeanModifier との違い

| 項目 | LeanModifier（非推奨） | SpineAimModifier |
|------|----------------------|-----------------|
| 対象ボーン | 単一ボーン（UpperChest） | 複数ボーンチェーン（重み付き分配） |
| リーン軸 | ロール（Z軸）のみ | ロール（Z軸）+ ピッチ（X軸） |
| ポーズリーン | 非対応 | 対応（GunDown前傾等） |
| 重心補正 | なし | Hips カウンターシフト |

## 使用例

```gdscript
# UpperBodyIKController 内で自動生成される
# 直接使用する場合:
var spine_mod = SpineAimModifier.new()
spine_mod.name = "SpineAimModifier"
skeleton.add_child(spine_mod)

# 移動リーン設定
spine_mod.set_target_lean(deg_to_rad(15.0))  # 右に15度

# ポーズリーン設定（GunDown時）
spine_mod.set_pose_lean(0.15)  # やや前傾
```

## APIリファレンス

### シグナル
なし

### メソッド
- `set_target_lean(angle_radians: float) -> void`
- `set_pose_lean(angle_radians: float) -> void`
