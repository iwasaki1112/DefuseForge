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
