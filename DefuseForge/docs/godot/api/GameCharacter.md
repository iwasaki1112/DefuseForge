# GameCharacter

キャラクター管理クラス。HP、死亡状態、チーム管理を提供し、CharacterAnimationControllerと連携する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `CharacterBody3D` |
| ファイルパス | `scripts/characters/game_character.gd` |

## Enums

### Team
チーム定義。

| 値 | 説明 |
|----|------|
| `NONE` (0) | 所属なし |
| `COUNTER_TERRORIST` (1) | 対テロリスト |
| `TERRORIST` (2) | テロリスト |

## Export Properties

### HP Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `max_health` | `float` | `100.0` | 最大HP |

### Team Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `team` | `Team` | `Team.NONE` | 所属チーム |

## State Variables

| 変数 | 型 | デフォルト | 説明 |
|------|-----|----------|------|
| `current_health` | `float` | `100.0` | 現在のHP |
| `is_alive` | `bool` | `true` | 生存状態 |
| `anim_ctrl` | `Node` | `null` | CharacterAnimationControllerへの参照 |
| `vision` | `VisionComponent` | `null` | VisionComponentへの参照 |
| `current_weapon` | `Resource` | `null` | WeaponPresetへの参照 |

## Public API

### HP API

#### take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void
ダメージを受ける。HPが0以下になると死亡処理が実行される。

**引数:**
- `amount` - ダメージ量
- `attacker` - 攻撃者ノード（被弾方向計算用）
- `is_headshot` - ヘッドショットか

#### heal(amount: float) -> void
回復する。

**引数:**
- `amount` - 回復量

#### get_health_ratio() -> float
HP割合を取得する。

**戻り値:** 0.0〜1.0のHP割合

#### reset_health() -> void
HPをリセットしてリスポーンする。Visionも再有効化。

### Team API

#### is_enemy_of(other: GameCharacter) -> bool
対象が敵チームか判定する。

**引数:**
- `other` - 判定対象キャラクター

**戻り値:** 敵チームなら`true`

### Animation Controller API

#### set_anim_controller(controller: Node) -> void
CharacterAnimationControllerを設定する。

#### get_anim_controller() -> Node
CharacterAnimationControllerを取得する。

### Vision Component API

#### set_vision_component(component: VisionComponent) -> void
VisionComponentを設定する。

#### get_vision_component() -> VisionComponent
VisionComponentを取得する。

#### setup_vision(fov: float = 90.0, view_dist: float = 15.0) -> VisionComponent
VisionComponentをセットアップする（存在しなければ自動作成）。

**引数:**
- `fov` - 視野角（度）
- `view_dist` - 視界距離

**戻り値:** VisionComponentインスタンス

### Weapon API

#### equip_weapon(weapon: Resource) -> void
武器を装備する。WeaponPresetから武器タイプとリコイル設定をCharacterAnimationControllerに適用。

**引数:**
- `weapon` - WeaponPresetリソース

**動作:**
- WeaponCategoryをCharacterAnimationController.Weaponに変換
- PISTOL → Weapon.PISTOL、それ以外 → Weapon.RIFLE
- リコイル強度・回復速度をコントローラーに適用

#### get_current_weapon() -> Resource
装備中の武器を取得する。

**戻り値:** WeaponPresetまたは`null`

## ライフサイクル

- `_ready()`: HP初期化、`"characters"`グループに追加

## 使用例

```gdscript
# キャラクター作成
var character = GameCharacter.new()
character.max_health = 100.0
character.team = GameCharacter.Team.COUNTER_TERRORIST

# ダメージ処理
character.take_damage(25.0, attacker, false)

# 敵判定
if character.is_enemy_of(other_character):
    # 敵として処理
    pass

# Vision設定
var vision = character.setup_vision(90.0, 15.0)

# 武器装備
var weapon = WeaponRegistry.get_preset("m4a1")
character.equip_weapon(weapon)
```

## 内部動作

- 死亡時は`CharacterAnimationController.play_death()`を呼び出し
- 被弾方向は攻撃者位置から自動計算（前/後/左/右）
- 死亡時はVisionを無効化し、コリジョンも無効化
