# Grenade

投擲グレネードクラス。放物線軌道で飛び、壁・床に跳ね返り、一定時間後に爆発する。
2タップ方式でくの字投げ（バウンス投擲）に対応。

## 継承

`RigidBody3D`

## シーン構成

```
Grenade (RigidBody3D)
├── CollisionShape3D (SphereShape3D, radius=0.05)
├── Model (hand_granade.glb)
└── FuseTimer (Timer, 内部生成)
```

## シグナル

| シグナル | パラメータ | 説明 |
|---------|-----------|------|
| `exploded` | `position: Vector3` | 爆発時に発火。爆発位置を通知 |

## エクスポートプロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `fuse_time` | `float` | `3.0` | 導火線時間（秒） |
| `explosion_radius` | `float` | `5.0` | 爆発範囲（メートル） |
| `explosion_damage` | `float` | `100.0` | 中心での最大ダメージ |
| `default_arc_height` | `float` | `2.0` | 放物線のデフォルト高さ |
| `throw_gravity` | `float` | `9.8` | 軌道計算用の重力値 |

## 物理設定

| 設定 | 値 | 説明 |
|-----|-----|------|
| `collision_layer` | `1` | キャラクターレイヤー |
| `collision_mask` | `3` | 床(1) + 壁(2) |
| `mass` | `0.4` | 質量（kg） |
| `bounce` | `0.5` | 跳ね返り係数 |
| `friction` | `0.3` | 摩擦係数 |

## メソッド

### throw

```gdscript
func throw(start_pos: Vector3, target_pos: Vector3, thrower: Node3D = null, arc_height: float = -1.0) -> void
```

グレネードを直接投擲する（バウンスなし）。

| パラメータ | 説明 |
|-----------|------|
| `start_pos` | 投擲開始位置 |
| `target_pos` | 目標着弾位置 |
| `thrower` | 投げたキャラクター（オプション） |
| `arc_height` | 放物線の高さ（-1で`default_arc_height`を使用） |

### throw_with_bounce

```gdscript
func throw_with_bounce(start_pos: Vector3, bounce_pos: Vector3, bounce_normal: Vector3, target_pos: Vector3, thrower: Node3D = null) -> void
```

バウンス投擲（くの字投げ）。バウンスポイントで跳ね返ってターゲットに向かう。

| パラメータ | 説明 |
|-----------|------|
| `start_pos` | 投擲開始位置 |
| `bounce_pos` | バウンスポイント（壁/エッジ位置） |
| `bounce_normal` | バウンス面の法線 |
| `target_pos` | 最終目標位置 |
| `thrower` | 投げたキャラクター（オプション） |

### force_explode

```gdscript
func force_explode() -> void
```

手動で即座に爆発させる（デバッグ用）。

## 2タップ投擲フロー

```
1. Crouchメニュー選択 → グレネードモード開始
   - マウス移動で投擲予測線をリアルタイム表示

2. 1タップ目: バウンスポイント（壁/ドアエッジ）をタップ
   - 第1区間のプレビュー表示（オレンジ色の実線）
   - バウンスポイントにクロスマーカー表示

3. マウス移動: ターゲット位置のプレビュー
   - 第2区間のプレビュー表示（オレンジ色の破線）
   - ターゲット位置にクロスマーカー表示

4. 2タップ目: 最終目標位置をタップ
   - グレネード投擲実行
   - バウンスポイントで跳ね返り、ターゲット方向へ

ESCキー: グレネードモードをキャンセル
```

## 内部処理

### 放物線軌道計算

`_calculate_throw_velocity()` で放物運動の初速度を計算:

1. 垂直初速度: `v_y = sqrt(2 * g * h)` （頂点高さから算出）
2. 上昇時間: `t_up = v_y / g`
3. 下降時間: `t_down = sqrt(2 * h_fall / g)`
4. 水平速度: `v_h = distance / (t_up + t_down)`

### バウンス投擲計算

`_calculate_bounce_throw_velocity()` でバウンス投擲の初速度を計算:

1. 総飛行距離に応じた放物線高さを決定
2. バウンスポイントへの到達時間を計算
3. 入射角度が浅すぎる場合は垂直成分を調整
4. 物理エンジンがバウンス処理を担当

### 爆発処理

`_explode()` で範囲ダメージを適用:

1. `SphereShape3D` で爆発範囲内のコライダーを検索
2. 各コライダーから `GameCharacter` を探索
3. 距離に応じたダメージ計算: `damage = max_damage * (1 - dist / radius)`
4. `take_damage()` でダメージ適用

## GameManagerとの連携

`GameManager` は2タップ方式のグレネードモードを管理:

### 状態変数

| 変数 | 説明 |
|------|------|
| `_grenade_mode_active` | グレネードモード中か |
| `_grenade_mode_character` | 投擲キャラクター |
| `_grenade_bounce_point` | 1タップ目のバウンスポイント |
| `_grenade_bounce_normal` | バウンス面の法線 |
| `_grenade_has_bounce_point` | バウンスポイント設定済みか |
| `_grenade_trajectory_mesh` | 軌道プレビューメッシュ |

### メソッド

| メソッド | 説明 |
|---------|------|
| `start_grenade_mode(character)` | グレネードモード開始 |
| `end_grenade_mode()` | グレネードモード終了 |
| `is_grenade_mode()` | グレネードモード中か判定 |
| `has_grenade_bounce_point()` | バウンスポイント設定済みか |
| `update_grenade_preview(screen_pos)` | 軌道プレビューを更新（マウス移動時） |

### シグナル

| シグナル | 説明 |
|---------|------|
| `grenade_thrown(grenade, character)` | グレネード投擲時 |
| `grenade_mode_started(character)` | モード開始時 |
| `grenade_mode_ended()` | モード終了時 |

## 使用例

### GameManager経由での投擲（推奨）

```gdscript
# グレネードモード開始（Crouchメニューから自動呼び出し）
game_manager.start_grenade_mode(character)

# 1タップ目: 壁をタップ → バウンスポイント設定
# 2タップ目: 最終位置をタップ → 投擲実行
# （handle_click内で自動処理）
```

### 直接インスタンス化

```gdscript
const GrenadeScene = preload("res://scenes/weapons/grenade.tscn")

func throw_grenade_bounce(start: Vector3, bounce: Vector3, normal: Vector3, target: Vector3) -> void:
    var grenade = GrenadeScene.instantiate() as Grenade
    add_child(grenade)
    grenade.throw_with_bounce(start, bounce, normal, target)
    grenade.exploded.connect(_on_grenade_exploded)
```

## 関連ファイル

- `godot/scripts/weapons/grenade.gd` - スクリプト
- `godot/scenes/weapons/grenade.tscn` - シーン
- `godot/assets/weapons/hand_granade/hand_granade.glb` - 3Dモデル
- `godot/scripts/systems/game_manager.gd` - グレネードモード管理
