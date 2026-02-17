# IdleCharacterManager

アイドル中キャラクターの状態更新を管理するクラス。

## 概要

TPS操作対象以外のキャラクターのアイドル状態を毎フレーム更新する。
CombatAwareness処理と向き更新を担当し、テストシーンからゲームロジックを分離する。

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

## 定数（徘徊関連）

| 名前 | 値 | 説明 |
|------|-----|------|
| WANDER_RADIUS | 6.0 | ランダム目標地点の最大距離 |
| IDLE_TIME_MIN | 1.5 | 停止時間の最小値（秒） |
| IDLE_TIME_MAX | 4.0 | 停止時間の最大値（秒） |
| ARRIVAL_THRESHOLD | 0.5 | 目標到着判定距離 |
| STUCK_TIME | 2.0 | スタック判定時間（秒） |
| WALL_CHECK_DISTANCE | 1.5 | 前方壁検知レイキャスト距離 |
| RAY_CHECK_INTERVAL | 0.15 | レイキャスト間引き間隔（約7Hz） |
| FAN_RAY_ANGLE | 30° | ファンレイキャストの角度 |

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

キャラクターを管理リストから削除。徘徊データもクリーンアップ。

```gdscript
func remove_character(character: Node) -> void
```

### set_characters()

キャラクターリストを一括更新。徘徊データもクリア。

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

CombatAwareness処理、視線方向更新、重力適用を行う。

## 徘徊システム

### ステートマシン

```
IDLE(1.5〜4秒停止) → WALKING(ランダム方向へ歩行) → IDLE → ...
        ↕                    ↕
     COMBAT(敵検知時: 停止+射撃, CombatAwarenessに連動)
```

### 動作詳細

- **IDLE**: ランダムな時間（1.5〜4秒）停止後、新しい目標地点を選択してWALKINGに遷移
- **WALKING**: 目標地点に向かって歩行（`CharacterAnimationController.WALK_SPEED`で移動）
  - 到着（0.5m以内）→ IDLEに遷移
  - スタック検知（2秒間0.3m未満の移動）→ IDLEに遷移
  - 壁検知（3方向ファンレイキャスト）→ 新しい目標を選択
- **戦闘**: CombatAwarenessが敵を検知すると移動停止、射撃。敵を見失うと徘徊再開

### 壁チェック（ファンレイキャスト）

前方・左30°・右30°の3方向でレイキャストを実行。
角や狭路での往復振動を防止する。レイキャストは`RAY_CHECK_INTERVAL`（約7Hz）で間引き、
キャラごとにタイマー位相をずらしてモバイル負荷を軽減。

### facing_directionの更新

- 徘徊中: `character.set_facing_direction_vec(move_dir)` で移動方向に向く
- 戦闘中: `character.set_facing_direction_vec(look_dir)` で敵方向に向く
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

## 内部処理

### _update_idle_character()

単一キャラクターのアイドル状態を更新:

1. CombatAwareness処理（敵追跡）
2. 視線方向の決定
   - 敵追跡中: CombatAwarenessの視線方向
   - それ以外: 現在の向きを維持
3. 徘徊処理（`wandering_enabled`時のみ）
4. facing_direction明示更新
5. アニメーション更新
6. 物理移動（重力 + move_and_slide）
7. 射撃判定

## 関連クラス

- [CharacterSelectionManager](CharacterSelectionManager.md) - 選択状態管理
- [CombatAwarenessComponent](../Character/CombatAwarenessComponent.md) - 敵検出・自動照準

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
