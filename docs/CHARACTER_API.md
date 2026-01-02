# Character API リファレンス

キャラクター操作の統一APIリファレンスです。すべての操作は`CharacterAPI`クラスの静的メソッドで提供されます。

## 概要

```gdscript
# 基本的な使用方法
CharacterAPI.equip_weapon(player, CharacterSetup.WeaponId.AK47)
CharacterAPI.move_to(player, Vector3(10, 0, 5), true)
CharacterAPI.set_fov(player, 90.0)
```

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
| weapon_type | int | 武器タイプ（省略時は現在の武器） |
| blend_time | float | ブレンド時間（秒）デフォルト: 0.3 |

### set_animation_speed
アニメーション速度を設定します。

```gdscript
CharacterAPI.set_animation_speed(character, 1.5)  # 1.5倍速
```

### get_available_animations
利用可能なアニメーション一覧を取得します。

```gdscript
var anims = CharacterAPI.get_available_animations(character)
# ["idle_none", "walking_none", "idle_rifle", ...]
```

### set_shoot_animation
射撃アニメーションを設定します。

```gdscript
CharacterAPI.set_shoot_animation(character, "idle_aiming")
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

### move_to
単一地点へ移動します。

```gdscript
CharacterAPI.move_to(character, Vector3(10, 0, 5), true)  # 走って移動
```

### stop
移動を停止します。

```gdscript
CharacterAPI.stop(character)
```

### clear_path
パスをクリアします。

```gdscript
CharacterAPI.clear_path(character)
```

### await_path_complete
パス完了を待機します。

```gdscript
await CharacterAPI.await_path_complete(character)
```

---

## 視界API

### set_fov / get_fov
視野角を設定/取得します。

```gdscript
CharacterAPI.set_fov(character, 90.0)  # 90度
var fov = CharacterAPI.get_fov(character)
```

### set_view_distance / get_view_distance
視野距離を設定/取得します。

```gdscript
CharacterAPI.set_view_distance(character, 20.0)  # 20ユニット
var dist = CharacterAPI.get_view_distance(character)
```

### is_position_visible
位置が視野内か判定します（グリッドベース）。

```gdscript
if CharacterAPI.is_position_visible(character, enemy.global_position):
    print("敵を発見！")
```

### is_position_truly_visible
位置が視野内かつ視線が通っているか判定します（遮蔽物考慮）。

```gdscript
if CharacterAPI.is_position_truly_visible(character, enemy.global_position):
    print("敵が見える！")
```

### has_line_of_sight
レイキャストで遮蔽物を考慮した視線チェックを行います。

```gdscript
if CharacterAPI.has_line_of_sight(character, target_pos, 6):  # 壁レイヤー=6
    print("視線が通っている")
```

### get_vision_info
視界情報を辞書形式で取得します。

```gdscript
var info = CharacterAPI.get_vision_info(character)
# {
#   "fov_angle": 120.0,
#   "view_distance": 15.0,
#   "origin_cell": Vector2i(10, 5),
#   "visible_cell_count": 42,
#   "vision_origin": Vector3(10, 0, 5)
# }
```

### force_vision_update
視界を強制更新します。

```gdscript
CharacterAPI.force_vision_update(character)
```

---

## 武器API

### equip_weapon
武器を装備します。

```gdscript
CharacterAPI.equip_weapon(character, CharacterSetup.WeaponId.AK47)
```

### unequip_weapon
武器を解除します。

```gdscript
CharacterAPI.unequip_weapon(character)
```

### get_weapon_id
現在の武器IDを取得します。

```gdscript
var weapon_id = CharacterAPI.get_weapon_id(character)
```

### get_weapon_data
武器データを取得します。

```gdscript
var data = CharacterAPI.get_weapon_data(CharacterSetup.WeaponId.AK47)
# {
#   "name": "AK-47",
#   "damage": 36,
#   "fire_rate": 0.1,
#   "accuracy": 0.85,
#   ...
# }
```

### update_weapon_stats
武器ステータスを動的に調整します。

```gdscript
CharacterAPI.update_weapon_stats(CharacterSetup.WeaponId.AK47, {
    "damage": 40,
    "accuracy": 0.9
})
```

---

## ステータスAPI

### set_health / get_health
HPを設定/取得します。

```gdscript
CharacterAPI.set_health(character, 100.0)
var hp = CharacterAPI.get_health(character)
```

### set_armor / get_armor
アーマーを設定/取得します。

```gdscript
CharacterAPI.set_armor(character, 50.0)
var armor = CharacterAPI.get_armor(character)
```

### apply_damage
ダメージを与えます。

```gdscript
CharacterAPI.apply_damage(character, 25.0, attacker, false)  # 通常ダメージ
CharacterAPI.apply_damage(character, 100.0, attacker, true)  # ヘッドショット
```

### heal
回復します。

```gdscript
CharacterAPI.heal(character, 20.0)
```

### full_heal
完全回復します（HP + アーマー）。

```gdscript
CharacterAPI.full_heal(character)
```

### set_speed / get_speed
移動速度を設定/取得します。

```gdscript
CharacterAPI.set_speed(character, 4.0, 8.0)  # 歩行4.0, 走行8.0
var speed = CharacterAPI.get_speed(character)
# {"walk": 3.0, "run": 4.5, "base_walk": 4.0, "base_run": 8.0, "modifier": 0.75}
```

### apply_stat_modifiers
ステータス倍率を適用します。

```gdscript
CharacterAPI.apply_stat_modifiers(character, {
    "speed_mult": 1.2  # 速度20%アップ
})
```

---

## モデルAPI

### set_model
キャラクターモデルを変更します。

```gdscript
CharacterAPI.set_model(character, "res://assets/characters/new_model.tscn")
CharacterAPI.set_model(character, "res://assets/characters/new_model.tscn", false)  # 武器を維持しない
```

### set_model_textures
モデルのテクスチャを変更します。

```gdscript
CharacterAPI.set_model_textures(
    character,
    "res://assets/characters/skins/custom_albedo.tga",
    "res://assets/characters/skins/custom_normal.tga"
)
```

---

## ユーティリティ

### is_alive
キャラクターが生存しているか確認します。

```gdscript
if CharacterAPI.is_alive(character):
    print("生存中")
```

### is_moving
キャラクターが移動中か確認します。

```gdscript
if CharacterAPI.is_moving(character):
    print("移動中")
```

### get_position
キャラクターの現在位置を取得します。

```gdscript
var pos = CharacterAPI.get_position(character)
```

### get_rotation / set_rotation
キャラクターの向き（Y軸回転）を取得/設定します。

```gdscript
var rot = CharacterAPI.get_rotation(character)
CharacterAPI.set_rotation(character, PI / 2)  # 90度
```

### look_at_position
キャラクターを指定方向に向かせます。

```gdscript
CharacterAPI.look_at_position(character, enemy.global_position)
```

---

## 武器データベース

### 武器Resourceの追加

新しい武器を追加するには、`WeaponResource`を作成します。

```gdscript
var weapon = WeaponResource.new()
weapon.weapon_id = 100
weapon.weapon_name = "Custom Gun"
weapon.weapon_type = CharacterSetup.WeaponType.RIFLE
weapon.damage = 50.0
weapon.fire_rate = 0.08
weapon.accuracy = 0.9
weapon.effective_range = 25.0
weapon.scene_path = "res://scenes/weapons/custom_gun.tscn"

var db = CharacterAPI.get_weapon_database()
db.add_weapon(weapon)
```

### 外部ファイルで管理

`res://resources/weapon_database.tres`を作成してエディタで編集できます：

1. Godotエディタで「新規リソース」→「WeaponDatabase」を作成
2. Inspectorで`weapons`配列に`WeaponResource`を追加
3. 各武器のパラメータを設定

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
