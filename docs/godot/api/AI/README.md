# AI API

Beehave（Behavior Tree）ベースのCPUキャラクターAIシステム。

## アドオン

- **Beehave v2.9.2**: `addons/beehave/` — GDScript製 Behavior Tree アドオン

## BTシーン

| シーン | 説明 |
|--------|------|
| `scenes/ai/cpu_character_bt.tscn` | CPUキャラクター用BT定義（MANUALモード） |

## カスタムBTノード

すべて `scripts/ai/` に配置。

### Condition ノード

| クラス | ファイル | 役割 |
|--------|---------|------|
| BTIsTrackingEnemy | `bt_is_tracking_enemy.gd` | CombatAwarenessが敵追跡中かチェック |
| BTIsWanderingEnabled | `bt_is_wandering_enabled.gd` | Blackboardのwandering_enabledチェック |
| BTHasNearbyDoor | `bt_has_nearby_door.gd` | 近くに未開のドアがあるかチェック |
| BTShouldThrowGrenade | `bt_should_throw_grenade.gd` | グレネード投擲条件チェック（追跡中・残数・クールダウン） |

### Action ノード

| クラス | ファイル | 役割 |
|--------|---------|------|
| BTProcessDetection | `bt_process_detection.gd` | 敵検知フェーズ実行 + Blackboard書き込み + スプリントリセット + グレネードクールダウン管理 |
| BTFaceTarget | `bt_face_target.gd` | 追跡中の敵方向を向く |
| BTWander | `bt_wander.gd` | 徘徊処理（壁回避・スタック検知・スプリント判定） |
| BTUpdateAnimation | `bt_update_animation.gd` | アニメーション更新（スプリント対応） |
| BTApplyMovement | `bt_apply_movement.gd` | 物理移動適用（get_current_speed()使用） |
| BTProcessFiring | `bt_process_firing.gd` | 射撃判定実行 |
| BTOpenDoor | `bt_open_door.gd` | ドア開けアクション（fire-and-forget） |
| BTThrowGrenade | `bt_throw_grenade.gd` | グレネード投擲アクション（fire-and-forget） |

## BT構造

```
BeehaveTree (process_thread: MANUAL)
└── Sequence [MainLoop]
    ├── BTProcessDetection           … 敵検知 + スプリントリセット + クールダウン管理
    ├── AlwaysSucceed [MovementSucceeder]
    │   └── Selector [MovementDecision]
    │       ├── Sequence [CombatBranch]
    │       │   ├── BTIsTrackingEnemy
    │       │   └── BTFaceTarget
    │       ├── Sequence [DoorBranch]
    │       │   ├── BTHasNearbyDoor
    │       │   └── BTOpenDoor
    │       └── Sequence [WanderBranch]
    │           ├── BTIsWanderingEnabled
    │           └── BTWander             … is_sprinting セット
    ├── BTUpdateAnimation             … is_sprinting 読み取り
    ├── BTApplyMovement               … get_current_speed() 使用
    └── Selector [CombatAction]
        ├── Sequence [GrenadeBranch]
        │   ├── BTShouldThrowGrenade
        │   └── BTThrowGrenade
        └── BTProcessFiring
```

## Blackboard 共有値

| キー | 型 | 説明 |
|------|-----|------|
| wandering_enabled | bool | 徘徊有効フラグ（IdleCharacterManagerから設定） |
| is_tracking | bool | 敵追跡中フラグ（ProcessDetectionが設定） |
| is_sprinting | bool | スプリント中フラグ（ProcessDetectionがリセット、Wanderがセット） |
| look_direction | Vector3 | 視線方向（ProcessDetectionが設定） |
| move_direction | Vector3 | 移動方向（Wanderが設定） |
| wander_state | int | 徘徊ステート（Wander内部管理） |
| nearby_door | Node3D | 検出された近くのドア（HasNearbyDoorがセット、OpenDoorがクリア） |
| hand_grenade_count | int | グレネード残数（BT作成時に初期化） |
| grenade_cooldown | float | グレネードクールダウン秒数（ProcessDetectionがデクリメント） |

## 行動の詳細

### スプリント
- BTWander で目標地点までの距離が 3.5m を超える場合、`is_sprinting = true` にセット
- BTUpdateAnimation が `update_animation()` にスプリントフラグを渡す
- BTApplyMovement が `get_current_speed()` で実際の速度（0/2.0/6.0）を取得

### ドア開け
- BTHasNearbyDoor: "doors" グループの未開ドアを距離 1.5m 以内で検出（壁越しレイキャスト判定あり）
- BTOpenDoor: キャラをドア方向に向けて `play_door_open()` を呼び、`door_open_impact` シグナルで `DoorService.on_door_open_done()` を実行
- fire-and-forget: SUCCESS を即座に返し、アニメーション完了は CharacterAnimationController が管理

### グレネード投擲
- BTShouldThrowGrenade: 敵追跡中 + 残数あり + クールダウン完了時のみ SUCCESS
- BTThrowGrenade: ターゲット方向を向き、距離に応じて遠投/近投アニメを再生。`throw_release` シグナルで `GrenadeService.spawn_and_throw_hand_grenade()` を実行
- クールダウン: 15秒（BTProcessDetection が毎tick デクリメント）
- fire-and-forget: SUCCESS を即座に返し、アニメーション完了は CharacterAnimationController が管理

## 関連

- [IdleCharacterManager](../System/IdleCharacterManager.md) — BTのホスト（tick呼び出し元）
- [CombatAwarenessComponent](../Character/CombatAwarenessComponent.md) — 敵検出・自動照準
- [CharacterAnimationController](../Animation/CharacterAnimationController.md) — アニメーション制御
- [DoorService](../System/DoorService.md) — ドア開閉管理
- [GrenadeService](../System/GrenadeService.md) — グレネード生成・投擲
