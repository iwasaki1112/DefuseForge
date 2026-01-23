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

### FiringMode
| 値 | 説明 |
|----|------|
| `SINGLE` (0) | 単発射撃 |
| `BURST` (1) | バースト射撃（指定数発を連続発射） |
| `FULL_AUTO` (2) | フルオート射撃（連続発射） |

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
| `spread` | `float` | `0.1` | 散布（0.0〜1.0、低いほど集弾） |
| `effective_range` | `float` | `20.0` | 有効射程（メートル） |

### 武器カテゴリ別推奨値

| カテゴリ | accuracy | spread | effective_range |
|---------|----------|--------|-----------------|
| SNIPER | 0.95 | 0.05 | 50.0 |
| RIFLE | 0.75-0.85 | 0.10-0.20 | 25.0 |
| SMG | 0.65-0.75 | 0.25-0.35 | 15.0 |
| PISTOL | 0.65-0.75 | 0.20-0.30 | 15.0 |

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
| `attach_offset` | `Vector3` | `Vector3.ZERO` | 右手アタッチ時の位置オフセット（WeaponSocketに適用） |
| `attach_rotation` | `Vector3` | `Vector3.ZERO` | 右手アタッチ時の回転オフセット（度、WeaponSocketに適用） |

### Muzzle Flash
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `muzzle_flash_offset` | `Vector3` | `Vector3.ZERO` | マズルフラッシュ位置オフセット（WeaponSocket基準） |
| `muzzle_flash_scale` | `float` | `1.0` | マズルフラッシュのスケール倍率 |
| `muzzle_flash_rotation` | `Vector3` | `Vector3.ZERO` | マズルフラッシュの回転（度） |

### Auto Firing Mode（RIFLE/SMG専用）

距離に応じて射撃モードを自動切り替えするシステム。CQB（近距離）、Medium（中距離）、Long（長距離）の3レンジで異なる射撃パターンを使用。

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `auto_firing_mode_enabled` | `bool` | `false` | 距離ベース射撃モード切替の有効化 |

#### CQB Range（近距離）
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `cqb_max_distance` | `float` | `5.0` | CQBレンジの最大距離（メートル） |
| `cqb_firing_mode` | `FiringMode` | `FULL_AUTO` | CQBレンジの射撃モード |
| `cqb_shots_per_burst` | `int` | `0` | バースト発数（0=連続、FULL_AUTO用） |
| `cqb_burst_interval` | `float` | `0.08` | バースト内の発射間隔（秒） |
| `cqb_pause_after_burst` | `float` | `0.0` | バースト後の待機時間（秒） |
| `cqb_accuracy_modifier` | `float` | `0.85` | 精度倍率（1.0=標準） |
| `cqb_critical_rate` | `float` | `0.1` | クリティカルヒット確率（0.0-1.0） |

#### Medium Range（中距離）
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `medium_max_distance` | `float` | `15.0` | Mediumレンジの最大距離（メートル） |
| `medium_firing_mode` | `FiringMode` | `BURST` | Mediumレンジの射撃モード |
| `medium_shots_per_burst` | `int` | `3` | バースト発数 |
| `medium_burst_interval` | `float` | `0.10` | バースト内の発射間隔（秒） |
| `medium_pause_after_burst` | `float` | `0.40` | バースト後の待機時間（秒） |
| `medium_accuracy_modifier` | `float` | `1.0` | 精度倍率 |
| `medium_critical_rate` | `float` | `0.25` | クリティカルヒット確率 |

#### Long Range（長距離）
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `long_firing_mode` | `FiringMode` | `SINGLE` | Longレンジの射撃モード |
| `long_shots_per_burst` | `int` | `1` | バースト発数（SINGLEの場合1） |
| `long_burst_interval` | `float` | `0.0` | バースト内の発射間隔（SINGLE時未使用） |
| `long_pause_after_burst` | `float` | `0.60` | 射撃後の待機時間（秒） |
| `long_accuracy_modifier` | `float` | `1.15` | 精度倍率 |
| `long_critical_rate` | `float` | `0.5` | クリティカルヒット確率 |

#### 距離別推奨設定

| 距離 | モード | 動作 | 精度倍率 | クリ率 |
|------|--------|------|----------|--------|
| 0-5m (CQB) | フルオート | 高速連射、制圧用 | 0.85x | 10% |
| 5-15m (Medium) | バースト(3発) | 精度重視連射 | 1.0x | 25% |
| 15m+ (Long) | 単発 | 高精度シングル | 1.15x | 50% |

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
| `scale` | `Vector3.ONE * 100` | スケルトン補正（Mixamoスケルトンが0.01のため） |
| `rotation_degrees` | 武器固有 | GLBモデルの向きにより調整 |
| `position` | 武器固有 | GLBモデルの原点位置により調整 |

※ 武器モデルが現実的なサイズ（メートル単位）であれば、スケールは全武器で100に統一可能

### 武器GLBモデルの推奨設定

Blenderでエクスポートする際：
- **原点**: グリップ位置に設定
- **銃口方向**: -Y方向を向くように配置
- **スケール**: **実寸（メートル単位）**で作成（例: AK47 = 0.87m, Glock = 0.2m）

## APIリファレンス

### シグナル
なし

### メソッド
なし
