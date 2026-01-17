# WeaponRegistry

武器プリセットを管理するシングルトン。Autoloadとして使用。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/registries/weapon_registry.gd` |
| 使用方法 | Autoload（`WeaponRegistry`） |

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `PRESET_DIR` | `"res://data/weapons/"` | プリセットディレクトリ |

## Public API

### Registration API

#### register(preset: WeaponPreset) -> void
プリセットを登録する。

**引数:**
- `preset` - WeaponPresetリソース

#### unregister(id: String) -> void
プリセットを登録解除する。

**引数:**
- `id` - プリセットID

### Query API

#### get_preset(id: String) -> WeaponPreset
IDでプリセットを取得する。

**引数:**
- `id` - プリセットID

**戻り値:** WeaponPresetまたは`null`

#### has_preset(id: String) -> bool
プリセットが存在するか確認する。

#### get_all() -> Array
全プリセットを取得する。

#### get_by_category(category: WeaponCategory) -> Array
カテゴリー別プリセットを取得する。

**引数:**
- `category` - WeaponPreset.WeaponCategory

**戻り値:** WeaponPresetの配列

#### get_rifles() -> Array
全ライフルを取得する。

#### get_pistols() -> Array
全ピストルを取得する。

#### get_smgs() -> Array
全SMGを取得する。

#### get_shotguns() -> Array
全ショットガンを取得する。

#### get_snipers() -> Array
全スナイパーを取得する。

## 使用例

```gdscript
# プリセット取得
var weapon = WeaponRegistry.get_preset("m4a1")
if weapon:
    print(weapon.display_name)  # "M4A1"
    print(weapon.damage)        # 33.0

# カテゴリー別取得
var rifles = WeaponRegistry.get_rifles()
for rifle in rifles:
    print(rifle.id)

# キャラクターに装備
var character = CharacterRegistry.create_character("breacher")
var weapon = WeaponRegistry.get_preset("m4a1")
character.equip_weapon(weapon)
```

## ライフサイクル

1. `_ready()`:
   - カテゴリー配列初期化
   - `PRESET_DIR`から`.tres`ファイルを自動読み込み

## プリセットファイル配置

```
data/weapons/
├── m4a1.tres
├── glock.tres
└── ...
```
