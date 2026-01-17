# WeaponPreset

武器プリセット定義リソース。武器ステータスを格納。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Resource` |
| ファイルパス | `scripts/resources/weapon_preset.gd` |

## Enum

### WeaponCategory
| 値 | 説明 |
|----|------|
| `RIFLE` (0) | アサルトライフル |
| `PISTOL` (1) | ピストル |
| `SMG` (2) | サブマシンガン |
| `SHOTGUN` (3) | ショットガン |
| `SNIPER` (4) | スナイパーライフル |

## Export Properties

### Basic Info
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `id` | `String` | `""` | 一意識別子（例: "m4a1", "glock"） |
| `display_name` | `String` | `""` | UI表示名 |
| `category` | `WeaponCategory` | `RIFLE` | 武器カテゴリー |

### Combat Stats
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `damage` | `float` | `30.0` | 1発あたりのダメージ |
| `fire_rate` | `float` | `0.1` | 発射間隔（秒） |
| `accuracy` | `float` | `0.9` | 精度（0.0〜1.0） |

### Recoil
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `recoil_strength` | `float` | `0.08` | リコイルアニメーション強度 |
| `recoil_recovery` | `float` | `10.0` | リコイル回復速度 |

### Economy
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `price` | `int` | `0` | 購入価格 |

### Visual
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `model_scene` | `PackedScene` | - | 武器モデル（オプション） |
| `icon` | `Texture2D` | - | UI用武器アイコン |

### Attachment
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `attach_offset` | `Vector3` | `Vector3.ZERO` | 右手アタッチ時の位置オフセット |
| `attach_rotation` | `Vector3` | `Vector3.ZERO` | 右手アタッチ時の回転オフセット（度） |

## 使用例

### GDScriptでの作成
```gdscript
var weapon = WeaponPreset.new()
weapon.id = "m4a1"
weapon.display_name = "M4A1"
weapon.category = WeaponPreset.WeaponCategory.RIFLE
weapon.damage = 33.0
weapon.fire_rate = 0.09
weapon.accuracy = 0.85
weapon.recoil_strength = 0.08
weapon.price = 3100
```

### .tresファイル（エディタで作成）
`res://data/weapons/m4a1.tres`:
```
[gd_resource type="Resource" script_class="WeaponPreset" ...]

[resource]
id = "m4a1"
display_name = "M4A1"
category = 0
damage = 33.0
fire_rate = 0.09
accuracy = 0.85
recoil_strength = 0.08
price = 3100
```

## WeaponRegistryとの連携

1. `data/weapons/`に`.tres`ファイルを配置
2. `WeaponRegistry`が自動的に読み込み
3. `WeaponRegistry.get_preset("m4a1")`で使用

## GameCharacterとの連携

```gdscript
var weapon = WeaponRegistry.get_preset("m4a1")
character.equip_weapon(weapon)
```

## 武器モデルの装着に関する重要な注意点

### Mixamoキャラクターのスケルトンスケール問題

Mixamoからエクスポートしたキャラクターモデルは、**スケルトンに約1/100のスケールが適用されている**場合がある。

これにより、`BoneAttachment3D`に配置したオブジェクトは継承されたスケールの影響を受け、**極端に小さく（約1/100）描画される**。

#### 確認方法

```gdscript
# BoneAttachment3Dのglobal_transformを確認
print("Attachment global_transform: ", attachment.global_transform)
# 正常: X, Y, Zベクトルの長さが約1.0
# 問題あり: X, Y, Zベクトルの長さが約0.01
```

出力例（問題あり）:
```
[X: (0.001729, 0.009372, 0.00303), Y: (-0.000516, 0.003158, -0.009474), Z: (-0.009836, 0.001482, 0.001029), O: ...]
```

### 武器モデルの調整

スケルトンスケールを補正するため、武器モデルには以下の調整が必要：

| 項目 | 値 | 説明 |
|------|-----|------|
| `scale` | `Vector3.ONE * 13` | スケルトン補正(100) × 武器サイズ補正(0.13) |
| `rotation_degrees` | `Vector3(-65, -103, 4)` | AK47の場合の回転調整 |
| `position` | `Vector3(3, 6, 1)` | AK47の場合の位置調整 |

※ 回転・位置はGLBモデルの原点設定により異なる

### 武器GLBモデルの推奨設定

Blenderでエクスポートする際：
- **原点**: グリップ位置に設定
- **銃口方向**: -Y方向を向くように配置
- **スケール**: 実寸（メートル単位）

### テストシーン

`scenes/tests/test_weapon_viewer.tscn` で武器の装着状態を確認できる：
- ドラッグでカメラ回転
- スライダーで回転・位置・スケールをリアルタイム調整
- 調整した値をWeaponPresetの`attach_offset`/`attach_rotation`に反映
