# Character API リファレンス

キャラクター操作の統一APIリファレンスです。すべての操作は`CharacterAPI`クラスの静的メソッドで提供されます。

## クイックスタート

### 1. キャラクターを生成して配置（最もシンプル）

```gdscript
# プレイヤーをAK-47装備で生成・配置
var player = CharacterAPI.create("player", CharacterSetup.WeaponId.AK47)
CharacterAPI.spawn(player, self, Vector3(0, 0, 0))

# 敵をGlock装備で生成・配置
var enemy = CharacterAPI.create("enemies", CharacterSetup.WeaponId.GLOCK)
CharacterAPI.spawn(enemy, self, Vector3(0, 0, -5), PI)  # 180度回転
```

### 2. プリセットシーンを使用（エディタで調整可能）

```gdscript
# プリセットからインスタンス化
var player = preload("res://scenes/characters/player_base.tscn").instantiate()
player.global_position = Vector3(0, 0, 0)
add_child(player)
player.set_weapon(CharacterSetup.WeaponId.AK47)

# または CharacterAPI.create_from_preset を使用
var enemy = CharacterAPI.create_from_preset("enemy", CharacterSetup.WeaponId.GLOCK)
CharacterAPI.spawn(enemy, self, Vector3(0, 0, -5))
```

### 3. 既存キャラクターを操作

```gdscript
CharacterAPI.equip_weapon(player, CharacterSetup.WeaponId.AK47)
CharacterAPI.move_to(player, Vector3(10, 0, 5), true)
CharacterAPI.set_fov(player, 90.0)
```

---

## キャラクター生成API

### create
プログラムでキャラクターを生成します。

```gdscript
# 基本的な生成
var player = CharacterAPI.create("player", CharacterSetup.WeaponId.AK47)

# カスタムモデルを使用
var enemy = CharacterAPI.create("enemies", CharacterSetup.WeaponId.GLOCK, "res://assets/characters/custom.glb")

# 戦闘なしキャラクター（NPC用）
var npc = CharacterAPI.create("", CharacterSetup.WeaponId.NONE, "", false)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| team | String | チーム名（"player" or "enemies"）デフォルト: "player" |
| weapon_id | int | 武器ID（CharacterSetup.WeaponId）デフォルト: NONE |
| model_path | String | GLBモデルパス（省略時はデフォルトモデル） |
| with_combat | bool | CombatComponentを追加するか デフォルト: true |

**戻り値:** `CharacterBase` - 生成されたキャラクター

**自動セットアップ内容:**
- CharacterBaseスクリプト
- CollisionShape3D（CapsuleShape3D）
- CharacterModel（GLBモデル）
- CombatComponent（with_combat=true時）
- グループ追加（team指定時）
- AnimationTree（上半身/下半身ブレンド）
- 武器装備とアニメーション

### create_from_preset
プリセットシーンからキャラクターを生成します。

```gdscript
var player = CharacterAPI.create_from_preset("player", CharacterSetup.WeaponId.AK47)
var enemy = CharacterAPI.create_from_preset("enemy", CharacterSetup.WeaponId.GLOCK)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| preset | String | プリセット名（"player", "enemy", "ally"） |
| weapon_id | int | 武器ID デフォルト: NONE |

**戻り値:** `CharacterBase` - 生成されたキャラクター

**利用可能なプリセット:**
| プリセット | シーンパス | チーム |
|-----------|----------|--------|
| player | `res://scenes/characters/player_base.tscn` | player |
| enemy | `res://scenes/characters/enemy_base.tscn` | enemies |
| ally | `res://scenes/characters/ally_base.tscn` | player |

### spawn
キャラクターをシーンに配置します。

```gdscript
var player = CharacterAPI.create("player", CharacterSetup.WeaponId.AK47)
CharacterAPI.spawn(player, get_tree().current_scene, Vector3(0, 0, 0))

# 回転も指定
CharacterAPI.spawn(enemy, self, Vector3(0, 0, -5), PI)  # 180度回転
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 配置するキャラクター |
| parent | Node | 親ノード |
| position | Vector3 | 配置位置 |
| rotation_y | float | Y軸回転（ラジアン）デフォルト: 0.0 |

**戻り値:** `void`

---

## 概要（レガシー）

```gdscript
# 基本的な使用方法
CharacterAPI.equip_weapon(player, CharacterSetup.WeaponId.AK47)
CharacterAPI.move_to(player, Vector3(10, 0, 5), true)
CharacterAPI.set_fov(player, 90.0)
```

---

## アニメーションAPI

### play_animation
アニメーションを再生します。

```gdscript
CharacterAPI.play_animation(character, "idle")
CharacterAPI.play_animation(character, "walking", CharacterSetup.WeaponType.RIFLE)
CharacterAPI.play_animation(character, "running", -1, 0.5)  # ブレンド時間0.5秒
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| animation_name | String | アニメーション名（"idle", "walking", "running"等） |
| weapon_type | int | 武器タイプ（省略時は現在の武器）デフォルト: -1 |
| blend_time | float | ブレンド時間（秒）デフォルト: 0.3 |

**戻り値:** `void`

**処理内容:**
- 武器タイプに応じたアニメーション名を自動生成（例: "rifle_idle"）
- AnimationPlayerでアニメーションを再生
- ブレンド時間を適用してスムーズに遷移

### set_animation_speed
アニメーション速度を設定します。

```gdscript
CharacterAPI.set_animation_speed(character, 1.5)  # 1.5倍速
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| speed | float | アニメーション速度倍率 |

**戻り値:** `void`

### get_available_animations
利用可能なアニメーション一覧を取得します。

```gdscript
var anims = CharacterAPI.get_available_animations(character)
# ["idle_none", "walking_none", "idle_rifle", ...]
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `Array[String]` - アニメーション名の配列

### set_shoot_animation
射撃アニメーションを設定します。

```gdscript
CharacterAPI.set_shoot_animation(character, "idle_aiming")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| animation_name | String | 射撃時のアニメーション名 |

**戻り値:** `void`

---

## 歩行シーケンスAPI

歩行アニメーションを自動的に開始→ループ→終了の流れで再生します。

### start_walk_sequence
歩行シーケンスを開始します。`_start` → `ループ` の順で再生されます。

```gdscript
# 歩行開始（rifle_walk_start → rifle_walk ループ）
CharacterAPI.start_walk_sequence(character, "walk")

# スプリント開始（rifle_sprint ループ）
CharacterAPI.start_walk_sequence(character, "sprint")

# ブレンド時間を指定
CharacterAPI.start_walk_sequence(character, "walk", 0.5)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| base_name | String | ベース名（"walk", "sprint"等）デフォルト: "walk" |
| blend_time | float | ブレンド時間（秒）デフォルト: 0.3 |

**戻り値:** `void`

**処理内容:**
- 開始アニメーション（`{weapon}_{base_name}_start`）を再生
- animation_finishedシグナルでループアニメーションに自動遷移
- 内部状態を更新（is_walk_sequence_active = true）

### stop_walk_sequence
歩行シーケンスを停止します。`_end` → `idle` の順で再生されます。

```gdscript
# 歩行停止（rifle_walk_end → rifle_idle）
CharacterAPI.stop_walk_sequence(character)

# ブレンド時間を指定
CharacterAPI.stop_walk_sequence(character, 0.5)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| blend_time | float | ブレンド時間（秒）デフォルト: 0.3 |

**戻り値:** `void`

**処理内容:**
- 終了アニメーション（`{weapon}_{base_name}_end`）を再生
- animation_finishedシグナルでidleアニメーションに自動遷移
- 内部状態を更新（is_walk_sequence_active = false）

### cancel_walk_sequence
歩行シーケンスを即座に終了します（終了アニメーションなし）。

```gdscript
CharacterAPI.cancel_walk_sequence(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `void`

### is_walk_sequence_active
歩行シーケンスがアクティブか確認します。

```gdscript
if CharacterAPI.is_walk_sequence_active(character):
    print("歩行中")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `bool` - シーケンスがアクティブならtrue

### 歩行シーケンスの流れ

```
start_walk_sequence("walk") 呼び出し
    ↓
rifle_walk_start 再生（開始アニメーション）
    ↓ (animation_finished)
rifle_walk ループ再生
    ↓
stop_walk_sequence() 呼び出し
    ↓
rifle_walk_end 再生（終了アニメーション）
    ↓ (animation_finished)
rifle_idle 再生
```

---

## パスAPI

### set_path
パスを設定します。

```gdscript
# Vector3配列で設定（自動で走り判定）
CharacterAPI.set_path(character, [Vector3(0,0,0), Vector3(5,0,0), Vector3(10,0,5)], true)

# 辞書配列で詳細設定
CharacterAPI.set_path(character, [
    {"position": Vector3(0,0,0), "run": false},
    {"position": Vector3(5,0,0), "run": true},
])
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| waypoints | Array | 経路点配列（Vector3またはDictionary） |
| run | bool | 走るかどうか（Vector3配列時のみ）デフォルト: false |

**戻り値:** `void`

**処理内容:**
- waypointsをキャラクターの内部配列に設定
- 歩行/走行アニメーションを自動開始
- 移動開始シグナルを発行

### move_to
単一地点へ移動します。

```gdscript
CharacterAPI.move_to(character, Vector3(10, 0, 5), true)  # 走って移動
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| position | Vector3 | 目標位置 |
| run | bool | 走るかどうか デフォルト: false |

**戻り値:** `void`

### stop
移動を停止します。

```gdscript
CharacterAPI.stop(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `void`

### clear_path
パスをクリアします。

```gdscript
CharacterAPI.clear_path(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `void`

### await_path_complete
パス完了を待機します。

```gdscript
await CharacterAPI.await_path_complete(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `Signal` - パス完了時に発行

---

## 視界API

### set_fov
視野角を設定します。

```gdscript
CharacterAPI.set_fov(character, 90.0)  # 90度
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| fov | float | 視野角（度） |

**戻り値:** `void`

### get_fov
視野角を取得します。

```gdscript
var fov = CharacterAPI.get_fov(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `float` - 視野角（度）

### set_view_distance
視野距離を設定します。

```gdscript
CharacterAPI.set_view_distance(character, 20.0)  # 20ユニット
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| distance | float | 視野距離（ユニット） |

**戻り値:** `void`

### get_view_distance
視野距離を取得します。

```gdscript
var dist = CharacterAPI.get_view_distance(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `float` - 視野距離（ユニット）

### is_position_visible
位置が視野内か判定します（グリッドベース）。

```gdscript
if CharacterAPI.is_position_visible(character, enemy.global_position):
    print("敵を発見！")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| position | Vector3 | 判定対象位置 |

**戻り値:** `bool` - 視野内ならtrue

**処理内容:**
- グリッドベースの視界判定を実行
- 遮蔽物は考慮しない（高速判定）
- FogOfWarManagerと連携

### is_position_truly_visible
位置が視野内かつ視線が通っているか判定します（遮蔽物考慮）。

```gdscript
if CharacterAPI.is_position_truly_visible(character, enemy.global_position):
    print("敵が見える！")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| position | Vector3 | 判定対象位置 |

**戻り値:** `bool` - 視野内かつ視線が通っていればtrue

**処理内容:**
- グリッドベースの視界判定 + レイキャストで遮蔽物チェック
- 壁や障害物を考慮した正確な判定
- is_position_visibleより処理コスト高

### has_line_of_sight
レイキャストで遮蔽物を考慮した視線チェックを行います。

```gdscript
if CharacterAPI.has_line_of_sight(character, target_pos, 6):  # 壁レイヤー=6
    print("視線が通っている")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| target_position | Vector3 | 判定対象位置 |
| collision_mask | int | 遮蔽物のコリジョンマスク |

**戻り値:** `bool` - 視線が通っていればtrue

### get_vision_info
視界情報を辞書形式で取得します。

```gdscript
var info = CharacterAPI.get_vision_info(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `Dictionary` - 視界情報

```gdscript
{
    "fov_angle": float,         # 視野角（度）
    "view_distance": float,     # 視野距離
    "origin_cell": Vector2i,    # グリッド原点セル
    "visible_cell_count": int,  # 可視セル数
    "vision_origin": Vector3    # 視界原点位置
}
```

### force_vision_update
視界を強制更新します。

```gdscript
CharacterAPI.force_vision_update(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `void`

**処理内容:**
- VisionComponentの視界計算を強制実行
- FogOfWarテクスチャを更新

---

## 武器API

### equip_weapon
武器を装備します。

```gdscript
CharacterAPI.equip_weapon(character, CharacterSetup.WeaponId.AK47)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| weapon_id | int | 武器ID（CharacterSetup.WeaponId） |

**戻り値:** `void`

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

**戻り値:** `void`

### get_weapon_id
現在の武器IDを取得します。

```gdscript
var weapon_id = CharacterAPI.get_weapon_id(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `int` - 武器ID（CharacterSetup.WeaponId）

### get_weapon_data
武器データを取得します。

```gdscript
var data = CharacterAPI.get_weapon_data(CharacterSetup.WeaponId.AK47)
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
武器ステータスを動的に調整します。

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

## ステータスAPI

### set_health
HPを設定します。

```gdscript
CharacterAPI.set_health(character, 100.0)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| health | float | HP値 |

**戻り値:** `void`

### get_health
HPを取得します。

```gdscript
var hp = CharacterAPI.get_health(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `float` - 現在のHP

### apply_damage
ダメージを与えます。

```gdscript
CharacterAPI.apply_damage(character, 25.0, attacker, false)  # 通常ダメージ
CharacterAPI.apply_damage(character, 100.0, attacker, true)  # ヘッドショット
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| damage | float | ダメージ量 |
| attacker | CharacterBase | 攻撃者（null可） |
| is_headshot | bool | ヘッドショットかどうか |

**戻り値:** `void`

**処理内容:**
- HP0以下で `died` シグナルを発行
- 死亡アニメーションを再生

### heal
回復します。

```gdscript
CharacterAPI.heal(character, 20.0)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| amount | float | 回復量 |

**戻り値:** `void`

### full_heal
HPを完全回復します。

```gdscript
CharacterAPI.full_heal(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `void`

### set_speed
移動速度を設定します。

```gdscript
CharacterAPI.set_speed(character, 4.0, 8.0)  # 歩行4.0, 走行8.0
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| walk_speed | float | 歩行速度 |
| run_speed | float | 走行速度 |

**戻り値:** `void`

### get_speed
移動速度を取得します。

```gdscript
var speed = CharacterAPI.get_speed(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `Dictionary` - 速度情報

```gdscript
{
    "walk": float,       # 実際の歩行速度（倍率適用後）
    "run": float,        # 実際の走行速度（倍率適用後）
    "base_walk": float,  # ベース歩行速度
    "base_run": float,   # ベース走行速度
    "modifier": float    # 武器による速度倍率
}
```

### apply_stat_modifiers
ステータス倍率を適用します。

```gdscript
CharacterAPI.apply_stat_modifiers(character, {
    "speed_mult": 1.2  # 速度20%アップ
})
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| modifiers | Dictionary | 適用する倍率 |

**戻り値:** `void`

---

## モデルAPI

### set_model
キャラクターモデルを変更します。

```gdscript
CharacterAPI.set_model(character, "res://assets/characters/new_model.tscn")
CharacterAPI.set_model(character, "res://assets/characters/new_model.tscn", false)  # 武器を維持しない
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| model_path | String | モデルシーンパス |
| keep_weapon | bool | 武器を維持するか デフォルト: true |

**戻り値:** `void`

**処理内容:**
- 現在のモデルを削除
- 新しいモデルをロード・インスタンス化
- AnimationPlayerを再取得
- keep_weapon=trueの場合、武器を再アタッチ

### set_model_textures
モデルのテクスチャを変更します。

```gdscript
CharacterAPI.set_model_textures(
    character,
    "res://assets/characters/skins/custom_albedo.tga",
    "res://assets/characters/skins/custom_normal.tga"
)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| albedo_path | String | アルベドテクスチャパス |
| normal_path | String | ノーマルマップパス（省略可） |

**戻り値:** `void`

---

## ユーティリティ

### is_alive
キャラクターが生存しているか確認します。

```gdscript
if CharacterAPI.is_alive(character):
    print("生存中")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `bool` - 生存中ならtrue

### is_moving
キャラクターが移動中か確認します。

```gdscript
if CharacterAPI.is_moving(character):
    print("移動中")
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `bool` - 移動中ならtrue

### get_position
キャラクターの現在位置を取得します。

```gdscript
var pos = CharacterAPI.get_position(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `Vector3` - 現在のグローバル位置

### get_rotation
キャラクターの向き（Y軸回転）を取得します。

```gdscript
var rot = CharacterAPI.get_rotation(character)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |

**戻り値:** `float` - Y軸回転（ラジアン）

### set_rotation
キャラクターの向き（Y軸回転）を設定します。

```gdscript
CharacterAPI.set_rotation(character, PI / 2)  # 90度
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| rotation | float | Y軸回転（ラジアン） |

**戻り値:** `void`

### look_at_position
キャラクターを指定方向に向かせます。

```gdscript
CharacterAPI.look_at_position(character, enemy.global_position)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| character | CharacterBase | 対象キャラクター |
| target_position | Vector3 | 向く先の位置 |

**戻り値:** `void`

---

## CharacterBaseクラス

キャラクターの基底クラスです。

**ファイル:** `scripts/characters/character_base.gd`

```gdscript
class_name CharacterBase
extends CharacterBody3D

# ステータス
var health: float = 100.0
var is_dead: bool = false

# 移動
var waypoints: Array[Dictionary] = []
var base_walk_speed: float = 3.0
var base_run_speed: float = 6.0

# 武器
var current_weapon_id: int = 0
var weapon_attachment: BoneAttachment3D = null
```

**主要メソッド:**

| メソッド | 戻り値 | 説明 |
|----------|--------|------|
| `set_weapon(weapon_id)` | void | 武器を設定 |
| `get_weapon_id()` | int | 現在の武器IDを取得 |
| `get_weapon_data()` | Dictionary | 武器データを取得 |
| `get_weapon_type_name()` | String | 武器タイプ名を取得 |
| `get_speed_modifier()` | float | 速度倍率を取得 |

---

## シグナル

### CharacterBase シグナル

| シグナル | パラメータ | 説明 |
|----------|-----------|------|
| `died` | `killer: CharacterBase` | 死亡時に発行 |
| `health_changed` | `new_health: float` | HP変更時に発行 |
| `weapon_changed` | `weapon_id: int` | 武器変更時に発行 |
| `path_completed` | なし | パス完了時に発行 |
| `position_changed` | `new_position: Vector3` | 位置変更時に発行 |

### 使用例

```gdscript
character.died.connect(_on_character_died)
character.weapon_changed.connect(_on_weapon_changed)
character.path_completed.connect(_on_path_completed)

func _on_character_died(killer: CharacterBase) -> void:
    print("キャラクターが死亡しました")

func _on_weapon_changed(weapon_id: int) -> void:
    print("武器が変更されました: ", weapon_id)

func _on_path_completed() -> void:
    print("目的地に到着しました")
```

---

## 使用例

### 敵を発見して攻撃

```gdscript
func _process(delta):
    for enemy in get_tree().get_nodes_in_group("enemies"):
        if CharacterAPI.is_position_truly_visible(player, enemy.global_position):
            CharacterAPI.look_at_position(player, enemy.global_position)
            attack_enemy(enemy)
            break
```

### パスを描画して移動

```gdscript
func execute_path(waypoints: Array[Vector3]):
    CharacterAPI.set_path(player, waypoints, true)
    await CharacterAPI.await_path_complete(player)
    print("目的地に到着")
```

### 武器を切り替えてステータス表示

```gdscript
func switch_weapon(weapon_id: int):
    CharacterAPI.equip_weapon(player, weapon_id)
    var data = CharacterAPI.get_weapon_data(weapon_id)
    print("装備: %s (ダメージ: %d)" % [data.name, data.damage])
```

### キャラクターの初期設定

```gdscript
func setup_player(player: CharacterBase) -> void:
    # ステータス設定
    CharacterAPI.set_health(player, 100.0)
    CharacterAPI.set_speed(player, 3.5, 7.0)

    # 視界設定
    CharacterAPI.set_fov(player, 120.0)
    CharacterAPI.set_view_distance(player, 15.0)

    # 武器装備
    CharacterAPI.equip_weapon(player, CharacterSetup.WeaponId.AK47)
```

---

## リコイルAPI

射撃時のリコイル（反動）エフェクトを制御します。CombatComponentを使用している場合、リコイルは射撃時に自動的に適用されます。

### apply_recoil
リコイルを適用します。武器のキックバックと右腕の反動を同時に処理します。

```gdscript
# 通常のリコイル
character.apply_recoil(1.0)

# 軽いリコイル
character.apply_recoil(0.5)
```

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| intensity | float | リコイル強度（0.0-1.0）デフォルト: 1.0 |

**戻り値:** `void`

**処理内容:**
- 武器モデルのキックバック（Z方向オフセット + 回転）
- 右腕ボーンの反動回転
- 自動的にスムーズに元の位置へ復帰

### リコイル定数

CharacterBaseで定義されているリコイル関連の定数:

| 定数 | 値 | 説明 |
|------|-----|------|
| `RECOIL_KICKBACK` | 0.02 | 武器のZ方向キックバック量 |
| `RECOIL_ROTATION` | Vector3(-5, 0, 0) | 武器の回転（度） |
| `ARM_RECOIL_ANGLE` | 8.0 | 右腕の反動角度（度） |
| `RECOIL_RECOVERY_SPEED` | 10.0 | 元の位置への復帰速度 |

### 自動リコイル

CombatComponentを使用している場合、以下のタイミングでリコイルが自動適用されます:

1. `_execute_attack()` で弾を発射した時
2. `character.apply_recoil(1.0)` が内部で呼ばれる
3. 毎フレーム `_recover_weapon_recoil()` でスムーズに復帰

手動でリコイルを制御したい場合は、CombatComponentのauto_attackをfalseにして直接`apply_recoil()`を呼び出してください。

---

## 関連ファイル

| ファイル | 説明 |
|----------|------|
| `scripts/api/character_api.gd` | 統一API |
| `scripts/characters/character_base.gd` | キャラクター基底クラス |
| `scripts/characters/player.gd` | プレイヤークラス |
| `scripts/characters/enemy.gd` | 敵クラス |
| `scripts/characters/components/vision_component.gd` | 視野コンポーネント |
| `scripts/utils/character_setup.gd` | セットアップユーティリティ |
| `scripts/resources/weapon_resource.gd` | 武器リソースクラス |
| `scripts/resources/weapon_database.gd` | 武器データベース |
