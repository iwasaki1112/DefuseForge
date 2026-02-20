# IdleCharacterManager

アイドル中キャラクターの状態更新を管理するクラス。

## 概要

TPS操作対象以外のキャラクターのアイドル状態を毎フレーム更新する。
Beehave（Behavior Tree）でCPUキャラクターの行動を制御し、
CombatAwareness処理・徘徊・射撃・アニメーション・移動をBTノードで管理する。

`wandering_enabled = true` の場合、CPUキャラクターが自動的にマップ内を歩き回り、
敵を検知すると停止して射撃する。トレーニングモードで有効化される。

## パス

`res://scripts/systems/idle_character_manager.gd`

## クラス定義

```gdscript
extends Node
class_name IdleCharacterManager
```

## プロパティ

| 名前 | 型 | 説明 |
|------|-----|------|
| characters | Array[Node] | 管理対象キャラクターリスト |
| get_primary_callback | Callable | プライマリキャラクター取得用コールバック |
| wandering_enabled | bool | 徘徊モード有効化（トレーニングモードでON） |

## メソッド

### setup()

マネージャーをセットアップする。

```gdscript
func setup(
    char_list: Array[Node],
    primary_getter: Callable
) -> void
```

**引数:**
- `char_list`: 管理対象キャラクターリスト
- `primary_getter`: プライマリキャラクターを取得するコールバック `func() -> Node`

### add_character()

キャラクターを管理リストに追加。

```gdscript
func add_character(character: Node) -> void
```

### remove_character()

キャラクターを管理リストから削除。BTインスタンスもクリーンアップ。

```gdscript
func remove_character(character: Node) -> void
```

### set_characters()

キャラクターリストを一括更新。全BTインスタンスをクリア。

```gdscript
func set_characters(char_list: Array[Node]) -> void
```

### process_idle_characters()

アイドル中の全キャラクターを更新（毎フレーム呼び出し）。

```gdscript
func process_idle_characters(delta: float) -> void
```

以下の条件のキャラクターはスキップ:
- リモートキャラクター（ネットワークから状態受信）
- プライマリキャラクター（TPSPlayerControllerが制御）
- 死亡中

### process_primary_idle()

プライマリキャラクターのアイドル処理（手動操作無効時）。

```gdscript
func process_primary_idle(character: Node, delta: float) -> void
```

CombatAwareness処理、視線方向更新、重力適用を行う。BT不使用（単純処理のため）。

## Behavior Tree アーキテクチャ

### BT構造

キャラクターごとに `cpu_character_bt.tscn`（MANUALモード）をインスタンス化し、
`_update_idle_character()` で毎フレーム `tick()` を呼ぶ。

```
BeehaveTree (process_thread: MANUAL)
└── Sequence [MainLoop]
    ├── BTProcessDetection           … 敵検知 + スプリントリセット + クールダウン管理
    ├── AlwaysSucceed [MovementSucceeder]
    │   └── Selector [MovementDecision]
    │       ├── Sequence [CombatBranch]
    │       │   ├── BTIsTrackingEnemy   … 敵追跡中？
    │       │   └── BTFaceTarget        … 敵方向を向く
    │       ├── Sequence [DoorBranch]
    │       │   ├── BTHasNearbyDoor     … 近くにドアあり？
    │       │   └── BTOpenDoor          … ドアを開ける
    │       └── Sequence [WanderBranch]
    │           ├── BTIsWanderingEnabled … 徘徊有効？
    │           └── BTWander             … 徘徊処理（スプリント判定含む）
    ├── BTUpdateAnimation             … アニメーション更新（スプリント対応）
    ├── BTApplyMovement               … 物理移動（get_current_speed()使用）
    └── Selector [CombatAction]
        ├── Sequence [GrenadeBranch]
        │   ├── BTShouldThrowGrenade   … グレネード条件チェック
        │   └── BTThrowGrenade         … グレネード投擲
        └── BTProcessFiring            … 射撃判定
```

**AlwaysSucceed**: MovementDecisionのSelectorが失敗しても（敵未追跡 & 徘徊無効の場合）、
後続のアニメーション・移動・射撃ノードが常に実行されるように保証する。

**CombatAction**: グレネード条件が満たされた場合はグレネードを優先投擲し、
それ以外は通常の射撃判定にフォールバックする。

### カスタムBTノード

| ファイル | 型 | 役割 |
|---------|-----|------|
| `bt_process_detection.gd` | ActionLeaf | CombatAwareness処理 + Blackboard書き込み + スプリントリセット + クールダウン管理 |
| `bt_is_tracking_enemy.gd` | ConditionLeaf | 敵追跡中チェック |
| `bt_face_target.gd` | ActionLeaf | 追跡中の敵方向を向く |
| `bt_is_wandering_enabled.gd` | ConditionLeaf | Blackboardのwandering_enabledチェック |
| `bt_wander.gd` | ActionLeaf | 徘徊処理（壁回避・スタック検知・スプリント判定） |
| `bt_has_nearby_door.gd` | ConditionLeaf | 近くの未開ドア検出（壁越しレイキャスト判定） |
| `bt_open_door.gd` | ActionLeaf | ドア開けアクション（fire-and-forget） |
| `bt_update_animation.gd` | ActionLeaf | アニメーション更新（スプリント対応） |
| `bt_apply_movement.gd` | ActionLeaf | 物理移動適用（get_current_speed()使用） |
| `bt_should_throw_grenade.gd` | ConditionLeaf | グレネード投擲条件チェック |
| `bt_throw_grenade.gd` | ActionLeaf | グレネード投擲アクション（fire-and-forget） |
| `bt_process_firing.gd` | ActionLeaf | 射撃判定実行 |

### Blackboard 共有値

| キー | 型 | 説明 |
|------|-----|------|
| wandering_enabled | bool | 徘徊有効フラグ（IdleCharacterManagerから設定） |
| is_tracking | bool | 敵追跡中フラグ（ProcessDetectionが設定） |
| is_sprinting | bool | スプリント中フラグ（ProcessDetectionがリセット、Wanderがセット） |
| look_direction | Vector3 | 視線方向（ProcessDetectionが設定） |
| move_direction | Vector3 | 移動方向（Wanderが設定） |
| wander_state | int | 徘徊ステート（Wander内部管理） |
| nearby_door | Node3D | 検出された近くのドア（HasNearbyDoorがセット、OpenDoorがクリア） |
| hand_grenade_count | int | グレネード残数（BT作成時にHAND_GRENADE_PER_ROUNDで初期化） |
| grenade_cooldown | float | グレネードクールダウン秒数（ProcessDetectionがデクリメント） |

### BT初期化

`_get_or_create_bt()` でBTインスタンス作成時に以下を初期化:
- `hand_grenade_count`: `GameConstants.HAND_GRENADE_PER_ROUND` で設定

### 徘徊動作

- **IDLE**: ランダムな時間（1.5〜4秒）停止後、新しい目標地点を選択してWALKINGに遷移
- **WALKING**: 目標地点に向かって歩行/スプリント
  - 距離 > 3.5m → スプリント（6.0 m/s）
  - 距離 <= 3.5m → 歩行（2.0 m/s）
  - 到着（0.5m以内）→ IDLEに遷移
  - スタック検知（2秒間0.3m未満の移動）→ IDLEに遷移
  - 壁検知（3方向ファンレイキャスト）→ 新しい目標を選択
- **戦闘**: CombatAwarenessが敵を検知すると移動停止、射撃
- **ドア開け**: 近くに未開のドアがあると、ドア方向を向いて開けるアニメーション再生
- **グレネード投擲**: 敵追跡中にグレネード残数 > 0 かつクールダウン完了時、ターゲットに向けて投擲

### facing_directionの更新

- 戦闘中: `character.set_facing_direction_vec(look_dir)` で敵方向に向く
- 徘徊中: `character.set_facing_direction_vec(move_dir)` で移動方向に向く
- これにより `vision_component` の視界判定とネットワーク同期回転が正しく動作

## 使用例

```gdscript
# セットアップ
idle_manager = IdleCharacterManager.new()
idle_manager.name = "IdleCharacterManager"
add_child(idle_manager)
idle_manager.setup(
    characters,
    func(): return selection_manager.primary_character
)

# トレーニングモードで徘徊を有効化
idle_manager.wandering_enabled = true

# キャラクター追加/削除
idle_manager.add_character(new_character)
idle_manager.remove_character(old_character)

# 毎フレーム処理
func _physics_process(delta: float) -> void:
    idle_manager.process_idle_characters(delta)

    # プライマリキャラクターの処理（手動操作無効時）
    if not is_debug_control_enabled:
        idle_manager.process_primary_idle(primary, delta)
```

## 関連クラス

- [CharacterSelectionManager](CharacterSelectionManager.md) - 選択状態管理
- [CombatAwarenessComponent](../Character/CombatAwarenessComponent.md) - 敵検出・自動照準
- [AI BTノード](../AI/README.md) - Beehave カスタムBTノード
- [DoorService](DoorService.md) - ドア開閉管理
- [GrenadeService](GrenadeService.md) - グレネード生成・投擲

## APIリファレンス

### シグナル
なし

### メソッド
- `setup(char_list: Array[Node], primary_getter: Callable) -> void`
- `add_character(character: Node) -> void`
- `remove_character(character: Node) -> void`
- `set_characters(char_list: Array[Node]) -> void`
- `process_idle_characters(delta: float) -> void`
- `process_primary_idle(character: Node, delta: float) -> void`
