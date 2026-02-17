# CombatAwarenessComponent

キャラクター個別の敵検出・追跡を担当するコンポーネント。視界内の敵を自動検出し、照準方向のオーバーライドを提供する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/characters/combat_awareness_component.gd` |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `enemy_spotted` | `enemy: Node` | 敵を発見したとき |
| `enemy_lost` | `enemy: Node` | 敵を見失ったとき |
| `target_changed` | `new_target: Node, old_target: Node` | ターゲットが変更されたとき |
| `damage_dealt` | `attacker: Node, target: Node, damage: float, is_headshot: bool` | ダメージを与えたとき |

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `SCAN_INTERVAL` | `0.05` | 敵スキャン間隔（50ms、EnemyVisibilitySystemと同等） |
| `TRACKING_TIMEOUT` | `0.75` | 視界離脱後の追跡継続時間（秒） |
| `FIRE_INTERVAL` | `0.5` | 発砲間隔（500ms） |
| `MOVEMENT_THRESHOLD` | `0.5` | 移動判定の速度閾値（m/s） |
| `SPRINT_THRESHOLD` | `4.0` | スプリント判定の速度閾値（m/s） |

## Public API

### setup(character: Node) -> void
コンポーネントを初期化する。

**引数:**
- `character` - 所有キャラクター（GameCharacter）

### get_override_look_direction() -> Vector3
敵方向の照準オーバーライドを取得する。

**戻り値:**
- 敵追跡中: 敵への正規化方向ベクトル
- 非追跡中: `Vector3.ZERO`

### is_tracking_enemy() -> bool
現在敵を追跡中か確認する。

**戻り値:** 敵を追跡中（または最終確認位置を追跡中）なら`true`

### get_current_target() -> Node
現在のターゲットを取得する。

**戻り値:** 現在追跡中の敵ノード（なければ`null`）

### clear_target() -> void
現在のターゲットをクリアする。キャラクター死亡時などに使用。

### dismiss_current_target() -> void
ユーザー操作により現在の追跡を解除する。追跡中の敵を「無視リスト」に追加し、その敵が一度視界外に出るまで追跡対象から除外する。

**用途:** ユーザーがROTATION操作で意図的に向きを変更した場合に呼び出す。

**動作:**
1. 現在の追跡対象を無視リストに追加
2. `clear_target()`を呼び出して追跡を解除
3. 以降のスキャンで無視リスト内の敵はスキップ
4. 敵が視界外に出ると無視リストから削除され、再追跡可能になる

### enable_firing() -> void
自動発砲を有効化する。敵を視認中は自動的に発砲し、ダメージを与える。

### disable_firing() -> void
自動発砲を無効化する。

### is_firing_enabled() -> bool
自動発砲が有効か確認する。

**戻り値:** 自動発砲が有効なら`true`

### get_last_shot_result() -> Dictionary
最後の射撃結果を取得する。

**戻り値:** 以下のキーを含むDictionary
- `hit: bool` - 命中したかどうか
- `miss_offset: Vector3` - 外れた場合のオフセットベクトル
- `critical: bool` - クリティカルヒットだったかどうか

### process(delta: float) -> void
毎フレームの処理を行う。所有者の`_physics_process`から呼び出す。

**引数:**
- `delta` - フレーム時間

## 使用例

### 基本的なセットアップ

```gdscript
# GameCharacter経由でセットアップ
var character: GameCharacter = ...
character.setup_combat_awareness()

# シグナル接続
character.combat_awareness.enemy_spotted.connect(_on_enemy_spotted)
character.combat_awareness.enemy_lost.connect(_on_enemy_lost)

# 自動発砲を有効化
character.combat_awareness.enable_firing()

func _on_enemy_spotted(enemy: Node) -> void:
    print("%s spotted %s" % [character.name, enemy.name])

func _on_enemy_lost(enemy: Node) -> void:
    print("%s lost sight of %s" % [character.name, enemy.name])
```

### アイドル中の敵追跡

```gdscript
func _physics_process(delta: float) -> void:
    # Combat awarenessを処理
    if character.combat_awareness:
        character.combat_awareness.process(delta)

    var look_dir: Vector3 = Vector3.ZERO

    # 敵視認チェック（最優先）
    if character.combat_awareness.is_tracking_enemy():
        look_dir = character.combat_awareness.get_override_look_direction()

    # デフォルト: 現在の向きを維持
    if look_dir.length_squared() < 0.1:
        look_dir = anim_ctrl.get_look_direction()

    anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)
```

## 視線方向の優先順位

このコンポーネントを使用する場合、視線方向は以下の優先順位で決定される：

1. **敵視認** - 最優先（このコンポーネントが提供）
2. **視線ポイント** - ユーザー指定の視線方向
3. **移動方向** - デフォルト（進行方向を向く）

## 内部動作

### 敵スキャンロジック
1. 50msごとに視界内の敵をスキャン
2. 無視リストの更新（視界外に出た敵を削除）
3. 無視リスト内の敵をスキップ
4. `VisionComponent.is_position_in_view()`で視界判定
   - 距離チェック（早期終了）
   - FOV角度チェック（早期終了）
   - レイキャスト（壁遮蔽判定）
5. 複数敵の場合は最も近い敵を優先

### 無視リスト機構
- `dismiss_current_target()`呼び出し時に現在の追跡対象を無視リストに追加
- 無視リスト内の敵は視界内にいても追跡対象から除外
- 毎スキャン時に無視リストを更新し、視界外に出た敵を削除
- 敵が視界外→視界内に戻った時点で再追跡が可能になる

### 追跡継続
- 敵が視界から外れた際、0.75秒間「最終確認位置」を追跡継続
- この間は`is_tracking_enemy()`が`true`を返す
- タイムアウト後に追跡終了

### 敵判定
- `"characters"`グループから敵を検出
- `GameCharacter.is_enemy_of()`または`PlayerState`を使用して敵判定
- 死亡キャラクターは除外

### 自動発砲ロジック
- `enable_firing()`で有効化
- 毎`process_firing()`呼び出し時に発砲判定
- 条件: 発砲有効 AND ターゲット存在 AND ターゲット有効
- 発砲時の動作:
  1. `CharacterAnimationController.fire()`でリコイルアニメーション再生
  2. 武器のダメージ値を取得（デフォルト: 10.0）
  3. `target.take_damage(damage, attacker, is_headshot)`を呼び出し
- ターゲットが死亡した場合、次のスキャンで即座にクリア

## パフォーマンス考慮

- スキャン間隔: 50ms（EnemyVisibilitySystemと同等）
- 想定コスト: 5味方 × 10敵 = 最大50レイキャスト/50ms
- VisionComponentの軽量判定を使用（is_position_in_view）

## 命中判定システム

### 精度カーブベースの命中率計算

Door Kickers 2スタイルの精度システム。武器ごとに最適距離帯があり、移動状態が精度に影響する。

```
# 1. 距離カーブから基礎精度
base_accuracy = get_accuracy_from_curve(weapon, distance)
  # 0 〜 range_min: lerp(accuracy_close, accuracy_peak)
  # range_min 〜 range_max: accuracy_peak（スイートスポット）
  # range_max 〜 max_distance: lerp(accuracy_peak, accuracy_far)
  # max_distance以降: accuracy_far

# 2. Auto Firing Mode修正値（RIFLE/SMG）
base_accuracy *= accuracy_modifier  # CQB:0.85x, Medium:1.0x, Long:1.15x

# 3. 射手の移動ペナルティ
shooter_mult = get_shooter_movement_multiplier(weapon)
  # 静止(〜0.5m/s): 1.0
  # 歩行(0.5〜4.0m/s): lerp(1.0, shooter_walk_penalty)
  # スプリント(4.0m/s〜): shooter_sprint_penalty

# 4. ターゲットの移動ペナルティ
target_mult = get_target_movement_multiplier(weapon)
  # 1.0 - clamp(target_speed / reference, 0, 1) * target_move_penalty

# 5. ランダムなバラつき（精度が高いほど小さい）
spread = (1.0 - base_accuracy) * randf() * 0.3

# 6. 最終命中率
final = (base_accuracy - spread) * shooter_mult * target_mult
final = clamp(final, 0.05, 1.0)  # 最低5%は当たる
```

### ダメージ距離減衰

`damage_falloff_enabled = true` の場合、距離に応じてダメージが減衰する：

```
distance <= start: 1.0（フルダメージ）
start < distance < end: lerp(1.0, damage_falloff_min, 正規化距離)
distance >= end: damage_falloff_min
```

### 外れ時の弾道オフセット

外れた場合、着弾点にランダムオフセットが適用される：
- XZ平面でランダム角度（左右）
- 距離スケーリング: 遠いほどミスの散らばりが大きい（`distance / 20.0`, 0.5〜2.5倍）
- 水平オフセット: 0.3〜1.2m × 距離スケール
- 垂直オフセット: -0.4〜+0.4m × 距離スケール

### GameCharacterとの連携

弾道トレイルは`get_last_shot_result()`を使用して外れ時のオフセットを反映：

```gdscript
var shot_result = combat_awareness.get_last_shot_result()
if not shot_result.hit:
    target_pos += shot_result.miss_offset
```

## 距離ベース射撃モードシステム（Auto Firing Mode）

RIFLE/SMG専用の機能。距離に応じて射撃モード（フルオート/バースト/単発）を自動切り替えする。

### 対象武器

- **対象**: `WeaponCategory.RIFLE`, `WeaponCategory.SMG`
- **非対象**: `PISTOL`, `SHOTGUN`, `SNIPER`（従来の発砲ロジック使用）

### 距離レンジ

| レンジ | 距離 | モード | 特徴 |
|--------|------|--------|------|
| CQB | 0-5m | フルオート | 高速連射、制圧用、精度低下 |
| Medium | 5-15m | バースト(3発) | 精度重視の連射 |
| Long | 15m+ | 単発 | 高精度、クリティカル率高 |

### クリティカルヒット

- 武器の`auto_firing_mode_enabled`がtrueの場合のみ発生
- 距離レンジに応じたクリティカル率（CQB: 10%, Medium: 25%, Long: 50%）
- クリティカル時は2倍ダメージ

### 動作フロー

```
1. 敵を検出
2. 距離を計算 → レンジ判定
3. 射撃モード決定：
   - FULL_AUTO: 高速連続発射
   - BURST: 指定数発を連射後、一時停止
   - SINGLE: 1発射撃後、一時停止
4. 精度カーブ + Auto Firing Mode倍率適用
5. 射手/ターゲット移動ペナルティ適用
6. 命中判定（成功時はクリティカル判定 + ダメージ減衰）
7. ダメージ適用（クリティカル時2倍）
8. 次の射撃サイクルへ
```

### 設定例（AK-47）

```
auto_firing_mode_enabled = true

# Accuracy Curve
accuracy_peak = 0.85
accuracy_close = 0.70
accuracy_far = 0.10
accuracy_range_min = 3.0   # 3m〜20mがスイートスポット
accuracy_range_max = 20.0
accuracy_max_distance = 45.0

# Movement Penalties
shooter_walk_penalty = 0.75
shooter_sprint_penalty = 0.35
target_move_penalty = 0.15

# CQB (0-5m): フルオート
cqb_max_distance = 5.0
cqb_firing_mode = FULL_AUTO
cqb_burst_interval = 0.08  # 高速連射
cqb_accuracy_modifier = 0.85  # 精度低下
cqb_critical_rate = 0.1  # 低クリ率

# Medium (5-15m): 3点バースト
medium_max_distance = 15.0
medium_firing_mode = BURST
medium_shots_per_burst = 3
medium_pause_after_burst = 0.40
medium_critical_rate = 0.25

# Long (15m+): 単発
long_firing_mode = SINGLE
long_pause_after_burst = 0.60
long_accuracy_modifier = 1.15  # 精度向上
long_critical_rate = 0.5  # 高クリ率
```

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `enemy_spotted` | `enemy: Node` |
| `enemy_lost` | `enemy: Node` |
| `target_changed` | `new_target: Node, old_target: Node` |
| `damage_dealt` | `attacker: Node, target: Node, damage: float, is_headshot: bool` |

### メソッド
- `setup(character: Node) -> void`
- `get_override_look_direction() -> Vector3`
- `is_tracking_enemy() -> bool`
- `get_current_target() -> Node`
- `clear_target() -> void`
- `dismiss_current_target() -> void`
- `enable_firing() -> void`
- `disable_firing() -> void`
- `is_firing_enabled() -> bool`
- `get_last_shot_result() -> Dictionary`
- `process(delta: float) -> void`
- `process_firing(delta: float) -> void`
