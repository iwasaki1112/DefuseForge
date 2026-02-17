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

## Network Identity (Multiplayer)

| 変数 | 型 | デフォルト | 説明 |
|------|-----|----------|------|
| `network_id` | `int` | `0` | ネットワーク上のグローバルID（0はローカル専用） |
| `owner_peer_id` | `int` | `0` | 所有者のpeer_id（0はローカル/未割当） |

## State Variables

| 変数 | 型 | デフォルト | 説明 |
|------|-----|----------|------|
| `current_health` | `float` | `100.0` | 現在のHP |
| `is_alive` | `bool` | `true` | 生存状態 |
| `_facing_direction` | `Vector3` | `Vector3.FORWARD` | キャラクターの向き（VisionComponent参照用） |
| `anim_ctrl` | `Node` | `null` | CharacterAnimationControllerへの参照 |
| `vision` | `VisionComponent` | `null` | VisionComponentへの参照 |
| `current_weapon` | `Resource` | `null` | WeaponPresetへの参照 |
| `shell_ejection` | `ShellEjectionComponent` | `null` | 薬莢排出コンポーネント |
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

#### setup_vision(fov: float = 75.0, view_dist: float = 7.0) -> VisionComponent
VisionComponentをセットアップする（存在しなければ自動作成）。

**引数:**
- `fov` - 視野角（度）
- `view_dist` - 視界距離

**戻り値:** VisionComponentインスタンス

### Facing Direction API

キャラクターの向きを一元管理する。VisionComponentはこの値を参照して視界の向きを決定する。

> **重要: キャラクターの向きを変更する場合**
>
> `CharacterBody3D.look_at()`を直接使用しないでください。ARPモデルは+Z方向が前方ですが、Godotの`look_at()`は-Z軸をターゲットに向けるため、180度ずれます。
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
指定位置の方向を向く。内部で`set_facing_direction_vec()`を呼び出し、ARPモデルの向きを正しく処理する。

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

### Weapon API

#### equip_weapon(weapon: Resource) -> void
武器を装備する。WeaponPresetから武器タイプとリコイル設定をCharacterAnimationControllerに適用し、武器モデルを右手ボーンにアタッチする。また、武器の`vision_range`をVisionComponentに反映する。

**引数:**
- `weapon` - WeaponPresetリソース

**動作:**
- 武器モデルを`RightHand`ボーンにBoneAttachment3Dでアタッチ
- WeaponPresetの`attach_offset`/`attach_rotation`でオフセット調整
- WeaponCategoryをCharacterAnimationController.Weaponに変換
- PISTOL → Weapon.PISTOL、それ以外 → Weapon.RIFLE
- リコイル強度・回復速度をコントローラーに適用
- VisionComponentの`view_distance`を武器の`vision_range`で更新（FoWシステムが自動的にVisionLightに反映）

**前提条件:**
- キャラクターモデルに`CharacterModel`ノードが存在すること
- ARP標準のSkeleton（`RightHand`ボーン）

#### get_current_weapon() -> Resource
装備中の武器を取得する。

**戻り値:** WeaponPresetまたは`null`

#### get_weapon_socket() -> Node3D
武器の位置・回転調整用ソケットノードを取得する。

**戻り値:** `WeaponSocket`ノードまたは`null`

### Muzzle Flash, Bullet Trail & Shell Ejection API

#### set_muzzle_flash_preview(enabled: bool) -> void
マズルフラッシュの常時プレビュー表示を切り替える（調整用）。

#### update_muzzle_flash_preview() -> void
現在のWeaponPreset値でマズルフラッシュのプレビュー表示を更新する。

#### _play_bullet_trail() -> void
発砲時に弾道トレイル（Bullet Trail）を描画する。
- Shaderベースのマテリアルを使用
- ターゲット（敵または最大距離）に向かって描画
- 時間経過でフェードアウト

#### _eject_shell_casing() -> void
発砲時に薬莢を排出する。ShellEjectionComponentに委譲。
- 銃の右側から薬莢が放物線を描いて排出
- 地面に落下後、3秒間静止してからフェードアウト
- オブジェクトプール（最大20個）で管理、モバイル最適化

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

### 死亡処理と壁検出

- 死亡時は`CharacterAnimationController.play_death()`を呼び出し
- 被弾方向は攻撃者位置から自動計算（前/後/左/右）
- **壁検出による方向調整**: 死亡アニメーションでキャラクターが壁に埋まらないよう、4方向の壁を検出して安全な倒れ方向を選択
  - `_detect_nearby_walls()`: レイキャストで4方向の壁を検出
  - `_select_safe_death_direction()`: 壁のない方向に倒れるアニメーションを選択
- 死亡時はVisionを無効化し、コリジョンも無効化
- 武器装備時は`CharacterModel`配下のSkeleton3Dを再帰検索
- 武器モデルは`BoneAttachment3D`配下の`WeaponSocket`に配置される
- 新しい武器装備時は古い武器モデルを自動削除
- `CharacterAnimationController.fired`に連動してマズルフラッシュを表示
- マズルフラッシュ位置は`WeaponPreset.muzzle_flash_offset`を優先して使用
- マズルフラッシュ回転は`WeaponPreset.muzzle_flash_rotation`を使用

## Multiplayer API

### is_local() -> bool
ローカルプレイヤーのキャラクターか判定する。シングルプレイヤー時は常に`true`。

### set_network_id(id: int) -> void
ネットワークIDを設定する。

### set_owner_peer_id(peer_id: int) -> void
所有者のpeer_idを設定する。

### apply_remote_state(state: NetworkMessages.CharacterStateMessage) -> void
リモートからの状態更新を適用する。
- スナップショットバッファに状態を追加
- 初回受信時は即座に反映（テレポート防止）
- 以降は`update_remote_interpolation`で補間される

### update_remote_interpolation(delta: float) -> void
リモートキャラクターの位置・回転を補間更新する。
- 過去の2つのスナップショット間を補間
- データ不足時は外挿（Extrapolation）または直近値を使用
- 回転は四元数SLERPで滑らかに更新

### to_character_state() -> NetworkMessages.CharacterStateMessage
現在の状態をCharacterStateMessageに変換する。

### to_character_snapshot() -> SyncState.CharacterSnapshot
現在の状態をCharacterSnapshotに変換する（より詳細）。

### apply_character_snapshot(snapshot: SyncState.CharacterSnapshot) -> void
CharacterSnapshotから状態を復元する（リモートキャラクター用）。

### notify_state_changed() -> void
状態変更を通知する（ネットワーク同期用）。

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `died` | `character: GameCharacter` |
| `state_changed` | `character: GameCharacter` |

### メソッド
- `take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void`
- `heal(amount: float) -> void`
- `get_health_ratio() -> float`
- `reset_health() -> void`
- `is_enemy_of(other: GameCharacter) -> bool`
- `set_anim_controller(controller: CharacterAnimationController) -> void`
- `get_anim_controller() -> CharacterAnimationController`
- `set_facing_direction_vec(direction: Vector3) -> void`
- `set_facing_direction(y_rotation: float) -> void`
- `face_towards(target_pos: Vector3) -> void`
- `get_facing_direction() -> Vector3`
- `set_vision_component(component: VisionComponent) -> void`
- `get_vision_component() -> VisionComponent`
- `setup_vision(fov: float = 75.0, view_dist: float = 7.0) -> VisionComponent`
- `setup_combat_awareness() -> CombatAwarenessComponent`
- `get_combat_awareness() -> CombatAwarenessComponent`
- `equip_weapon(weapon: WeaponPreset) -> void`
- `get_current_weapon() -> WeaponPreset`
- `get_weapon_socket() -> Node3D`
- `set_muzzle_flash_preview(enabled: bool) -> void`
- `update_muzzle_flash_preview() -> void`
- `set_muzzle_flash_quad1_x(x_offset: float) -> void`
- `get_muzzle_flash_quad1_x() -> float`
- `set_muzzle_flash_quad1_z(z_offset: float) -> void`
- `get_muzzle_flash_quad1_z() -> float`
