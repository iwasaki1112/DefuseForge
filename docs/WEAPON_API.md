# Weapon API リファレンス

武器システムのAPIリファレンスです。武器の装備、データ取得、管理に関する機能を提供します。

## 概要

```gdscript
# 基本的な使用方法
CharacterAPI.equip_weapon(player, CharacterSetup.WeaponId.AK47)
CharacterAPI.unequip_weapon(player)
var weapon_data = CharacterAPI.get_weapon_data(CharacterSetup.WeaponId.AK47)
```

## 武器ID・タイプ定義

### WeaponId（武器ID）

`CharacterSetup.WeaponId` で定義されています。

| ID | 名前 | 説明 |
|----|------|------|
| `NONE` | なし | 武器なし |
| `AK47` | AK-47 | アサルトライフル |
| `USP` | USP | ピストル |

```gdscript
CharacterSetup.WeaponId.NONE   # 0
CharacterSetup.WeaponId.AK47   # 1
CharacterSetup.WeaponId.USP    # 2
```

### WeaponType（武器タイプ）

`CharacterSetup.WeaponType` で定義されています。アニメーション選択に使用されます。

| タイプ | 説明 | 速度倍率 |
|--------|------|----------|
| `NONE` | 武器なし | 1.0 |
| `PISTOL` | ピストル | 0.9 |
| `RIFLE` | ライフル | 0.75 |

```gdscript
CharacterSetup.WeaponType.NONE    # 0
CharacterSetup.WeaponType.RIFLE   # 1
CharacterSetup.WeaponType.PISTOL  # 2
```

---

## CharacterAPI 武器メソッド

### equip_weapon
武器を装備します。

```gdscript
CharacterAPI.equip_weapon(character, CharacterSetup.WeaponId.AK47)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| weapon_id | int | 武器ID（CharacterSetup.WeaponId） |

**処理内容:**
- 武器モデルを右手ボーン（mixamorig_RightHand）にアタッチ
- 武器タイプに応じたアニメーションに自動切替
- 移動速度を武器の重さに応じて調整
- `weapon_changed` シグナルを発行

### unequip_weapon
武器を解除します。

```gdscript
CharacterAPI.unequip_weapon(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

### get_weapon_id
現在装備中の武器IDを取得します。

```gdscript
var weapon_id = CharacterAPI.get_weapon_id(character)
if weapon_id == CharacterSetup.WeaponId.AK47:
    print("AK-47を装備中")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `int` - 武器ID

### get_weapon_data
武器データを辞書形式で取得します。

```gdscript
var data = CharacterAPI.get_weapon_data(CharacterSetup.WeaponId.AK47)
print(data.name)      # "AK-47"
print(data.damage)    # 36
print(data.accuracy)  # 0.85
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| weapon_id | int | 武器ID |

**戻り値:** `Dictionary` - 武器データ

```gdscript
{
    "name": String,              # 武器名
    "type": int,                 # WeaponType
    "price": int,                # 購入価格
    "damage": float,             # 基本ダメージ
    "fire_rate": float,          # 発射間隔（秒）
    "accuracy": float,           # 命中率（0.0-1.0）
    "range": float,              # 有効射程
    "headshot_multiplier": float, # ヘッドショット倍率
    "bodyshot_multiplier": float, # ボディショット倍率
    "scene_path": String,        # 武器シーンパス
    "kill_reward": int           # キル報酬
}
```

### update_weapon_stats
武器ステータスを動的に更新します。

```gdscript
CharacterAPI.update_weapon_stats(CharacterSetup.WeaponId.AK47, {
    "damage": 40,
    "accuracy": 0.9
})
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| weapon_id | int | 武器ID |
| updates | Dictionary | 更新する値 |

**戻り値:** `bool` - 成功/失敗

---

## CharacterBase 武器メソッド

キャラクターインスタンスから直接呼び出すこともできます。

### set_weapon
武器を設定します。

```gdscript
character.set_weapon(CharacterSetup.WeaponId.AK47)
character.set_weapon(CharacterSetup.WeaponId.NONE)  # 武器解除
```

### get_weapon_id / get_current_weapon_id
現在の武器IDを取得します。

```gdscript
var id = character.get_weapon_id()
var id = character.get_current_weapon_id()  # エイリアス
```

### get_weapon_data
現在装備中の武器データを取得します。

```gdscript
var data = character.get_weapon_data()
```

### get_weapon_type_name
現在の武器タイプ名を取得します。

```gdscript
var type_name = character.get_weapon_type_name()  # "rifle", "pistol", "none"
```

### get_speed_modifier
武器による速度倍率を取得します。

```gdscript
var modifier = character.get_speed_modifier()  # 0.75 (RIFLE)
```

---

## 武器データクラス

### WeaponResource

武器データをリソースとして管理するクラスです。

**ファイル:** `scripts/resources/weapon_resource.gd`

```gdscript
class_name WeaponResource
extends Resource

@export var weapon_id: int
@export var weapon_name: String
@export var weapon_type: int
@export var price: int
@export var kill_reward: int
@export var damage: float
@export var fire_rate: float
@export var accuracy: float
@export var effective_range: float
@export var headshot_multiplier: float
@export var bodyshot_multiplier: float
@export var scene_path: String
```

**メソッド:**

| メソッド | 説明 |
|----------|------|
| `to_dict()` | 辞書形式に変換 |
| `from_dict(data, id)` | 辞書からリソースを作成（静的） |

### WeaponDatabase

全武器データを一元管理するクラスです。

**ファイル:** `scripts/resources/weapon_database.gd`

```gdscript
class_name WeaponDatabase
extends Resource

@export var weapons: Array[WeaponResource]
```

**メソッド:**

| メソッド | 戻り値 | 説明 |
|----------|--------|------|
| `get_weapon(weapon_id)` | WeaponResource | 武器データを取得 |
| `get_weapon_dict(weapon_id)` | Dictionary | 辞書形式で取得 |
| `get_all_weapon_ids()` | Array[int] | 全武器IDを取得 |
| `get_weapons_by_type(type)` | Array[WeaponResource] | タイプでフィルタ |
| `add_weapon(weapon)` | void | 武器を追加 |
| `update_weapon(id, updates)` | bool | 武器を更新 |

---

## CharacterSetup ユーティリティ

**ファイル:** `scripts/utils/character_setup.gd`

### 武器関連メソッド

| メソッド | 戻り値 | 説明 |
|----------|--------|------|
| `get_weapon_type_from_id(weapon_id)` | int | 武器IDからタイプを取得 |
| `get_weapon_data(weapon_id)` | Dictionary | 武器データを取得 |
| `create_weapon_attachment(weapon_id)` | Node3D | 武器ノードを作成 |
| `attach_weapon_to_character(char, skel, id, name)` | Node3D | キャラクターに武器をアタッチ |
| `update_weapon_position(attach, id, state, name)` | void | アニメーション状態に応じて位置更新 |

### 武器データ定数

```gdscript
# 武器データ定義
CharacterSetup.WEAPON_DATA[WeaponId.AK47]
# {
#     "name": "AK-47",
#     "type": WeaponType.RIFLE,
#     "price": 0,
#     "damage": 36,
#     "fire_rate": 0.1,
#     "accuracy": 0.85,
#     "range": 20.0,
#     ...
# }

# 武器タイプ別速度倍率
CharacterSetup.WEAPON_SPEED_MODIFIER[WeaponType.RIFLE]  # 0.75
```

---

## シグナル

### CharacterBase.weapon_changed

武器が変更されたときに発行されます。

```gdscript
character.weapon_changed.connect(_on_weapon_changed)

func _on_weapon_changed(weapon_id: int) -> void:
    print("武器が変更されました: ", weapon_id)
```

---

## 使用例

### 基本的な武器装備

```gdscript
# CharacterAPI経由
CharacterAPI.equip_weapon(player, CharacterSetup.WeaponId.AK47)

# または直接
player.set_weapon(CharacterSetup.WeaponId.AK47)
```

### 武器情報の取得

```gdscript
var weapon_id = player.get_weapon_id()
var weapon_data = player.get_weapon_data()

print("装備中: ", weapon_data.name)
print("ダメージ: ", weapon_data.damage)
print("命中率: ", weapon_data.accuracy * 100, "%")
```

### 武器の切り替え

```gdscript
func switch_weapon(player: CharacterBase) -> void:
    var current = player.get_weapon_id()
    
    if current == CharacterSetup.WeaponId.AK47:
        player.set_weapon(CharacterSetup.WeaponId.USP)
    else:
        player.set_weapon(CharacterSetup.WeaponId.AK47)
```

### 武器タイプによる処理分岐

```gdscript
var weapon_type = CharacterSetup.get_weapon_type_from_id(player.get_weapon_id())

match weapon_type:
    CharacterSetup.WeaponType.RIFLE:
        # ライフル用処理
        pass
    CharacterSetup.WeaponType.PISTOL:
        # ピストル用処理
        pass
    CharacterSetup.WeaponType.NONE:
        # 素手
        pass
```

---

## 武器シーン構造

武器シーン（例: `scenes/weapons/ak47.tscn`）の構造：

```
AK47 (Node3D)
├── Model (Node3D)           # 位置・回転オフセット用
│   └── ak47 (MeshInstance3D) # 武器メッシュ
└── MuzzlePoint (Node3D)     # マズルフラッシュ位置
    └── MuzzleFlash (Node3D) # マズルフラッシュエフェクト
```

### 武器位置のカスタマイズ

`CharacterSetup.WEAPON_BASE_TRANSFORM` で武器ごとのベース位置を設定：

```gdscript
const WEAPON_BASE_TRANSFORM := {
    WeaponId.AK47: {
        "position": Vector3(-0.03, 0.13, 0.02),
        "rotation": Vector3(-6.13, 56.77, 3.96)  # 度数法
    },
    ...
}
```

---

## 関連ファイル

| ファイル | 説明 |
|----------|------|
| `scripts/api/character_api.gd` | 統一API |
| `scripts/utils/character_setup.gd` | セットアップユーティリティ |
| `scripts/resources/weapon_resource.gd` | 武器リソースクラス |
| `scripts/resources/weapon_database.gd` | 武器データベース |
| `scripts/characters/character_base.gd` | キャラクター基底クラス |
| `scenes/weapons/ak47.tscn` | AK-47武器シーン |
