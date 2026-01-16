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

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `SCAN_INTERVAL` | `0.05` | 敵スキャン間隔（50ms、EnemyVisibilitySystemと同等） |
| `TRACKING_TIMEOUT` | `0.75` | 視界離脱後の追跡継続時間（秒） |

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

func _on_enemy_spotted(enemy: Node) -> void:
    print("%s spotted %s" % [character.name, enemy.name])

func _on_enemy_lost(enemy: Node) -> void:
    print("%s lost sight of %s" % [character.name, enemy.name])
```

### PathFollowingControllerとの連携

```gdscript
# コントローラーに連携
var controller = PathFollowingController.new()
controller.setup(character)
controller.set_combat_awareness(character.combat_awareness)

# パス追従開始（移動中も敵を自動追跡）
controller.start_path(path, vision_points, false)
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

### ROTATION操作後の敵追跡解除

```gdscript
# 回転モード確定時に敵追跡を解除
func _on_rotation_confirmed(final_direction: Vector3) -> void:
    var rotating_character = rotation_controller.get_character()
    if rotating_character and rotating_character.combat_awareness:
        # 現在の追跡を解除（敵は視界外に出るまで無視される）
        rotating_character.combat_awareness.dismiss_current_target()
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

## パフォーマンス考慮

- スキャン間隔: 50ms（EnemyVisibilitySystemと同等）
- 想定コスト: 5味方 × 10敵 = 最大50レイキャスト/50ms
- VisionComponentの軽量判定を使用（is_position_in_view）
