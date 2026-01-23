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
| `_facing_direction` | `Vector3` | `Vector3.FORWARD` | キャラクターの向き（VisionComponent参照用） |
| `anim_ctrl` | `Node` | `null` | CharacterAnimationControllerへの参照 |
| `vision` | `VisionComponent` | `null` | VisionComponentへの参照 |
| `current_weapon` | `Resource` | `null` | WeaponPresetへの参照 |
| `_weapon_socket` | `Node3D` | `null` | 武器調整用のソケットノード |

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

### Facing Direction API

キャラクターの向きを一元管理する。VisionComponentはこの値を参照して視界の向きを決定する。

> **重要: キャラクターの向きを変更する場合**
>
> `CharacterBody3D.look_at()`を直接使用しないでください。Mixamoモデルは+Z方向が前方ですが、Godotの`look_at()`は-Z軸をターゲットに向けるため、180度ずれます。
>
> 代わりに以下のメソッドを使用してください：
> - `face_towards(target_pos)` - ターゲット位置を向く
> - `set_facing_direction_vec(direction)` - 方向ベクトルで設定
> - `set_facing_direction(y_rotation)` - Y軸回転で設定

#### set_facing_direction_vec(direction: Vector3) -> void
キャラクターの向きをベクトルで設定する。AnimationControllerのモデル向きも同時に更新。

**引数:**
- `direction` - 向きベクトル（XZ平面、自動正規化）

#### set_facing_direction(y_rotation: float) -> void
キャラクターの向きをY軸回転（ラジアン）で設定する。

**引数:**
- `y_rotation` - Y軸回転（0 = +Z方向）

#### face_towards(target_pos: Vector3) -> void
指定位置の方向を向く。内部で`set_facing_direction_vec()`を呼び出し、Mixamoモデルの向きを正しく処理する。

**引数:**
- `target_pos` - ターゲット位置

**使用例:**
```gdscript
# ドアキック時にドアの方向を向く
character.face_towards(door.global_position)

# 敵の方向を向く
character.face_towards(enemy.global_position)
```

#### get_facing_direction() -> Vector3
現在の向きを取得する。VisionComponentがこれを参照。

**戻り値:** 正規化された向きベクトル

**重要**: PathFollowingControllerは移動中に`_facing_direction`を直接更新する。これにより、移動中も視界の向きが正しく追従する。

### Weapon API

#### equip_weapon(weapon: Resource) -> void
武器を装備する。WeaponPresetから武器タイプとリコイル設定をCharacterAnimationControllerに適用し、武器モデルを右手ボーンにアタッチする。

**引数:**
- `weapon` - WeaponPresetリソース

**動作:**
- 武器モデルを`mixamorig_RightHand`ボーンにBoneAttachment3Dでアタッチ
- WeaponPresetの`attach_offset`/`attach_rotation`でオフセット調整
- WeaponCategoryをCharacterAnimationController.Weaponに変換
- PISTOL → Weapon.PISTOL、それ以外 → Weapon.RIFLE
- リコイル強度・回復速度をコントローラーに適用

**前提条件:**
- キャラクターモデルに`CharacterModel`ノードが存在すること
- Mixamo標準のSkeleton（`mixamorig_RightHand`ボーン）

#### get_current_weapon() -> Resource
装備中の武器を取得する。

**戻り値:** WeaponPresetまたは`null`

#### get_weapon_socket() -> Node3D
武器の位置・回転調整用ソケットノードを取得する。

**戻り値:** `WeaponSocket`ノードまたは`null`

### Muzzle Flash API

#### set_muzzle_flash_preview(enabled: bool) -> void
マズルフラッシュの常時プレビュー表示を切り替える（調整用）。

#### update_muzzle_flash_preview() -> void
現在のWeaponPreset値でマズルフラッシュのプレビュー表示を更新する。

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
- 武器装備時は`CharacterModel`配下のSkeleton3Dを再帰検索
- 武器モデルは`BoneAttachment3D`配下の`WeaponSocket`に配置される
- 新しい武器装備時は古い武器モデルを自動削除
- `CharacterAnimationController.fired`に連動してマズルフラッシュを表示
- マズルフラッシュ位置は`WeaponPreset.muzzle_flash_offset`を優先して使用
- マズルフラッシュ回転は`WeaponPreset.muzzle_flash_rotation`を使用
