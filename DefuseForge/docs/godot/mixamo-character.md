# MixamoCharacter API

シンプルなキャラクター状態管理クラス。StrafeAnimationControllerと組み合わせて使用。

## ファイル
- `scripts/characters/mixamo_character.gd`

## 概要

MixamoCharacterは最小限の機能のみを提供:
- HP管理（ダメージ、回復、死亡）
- チーム所属
- 死亡状態管理

アニメーション制御はStrafeAnimationControllerに完全に委譲。

## API

### チーム定義
```gdscript
enum Team { NONE = 0, COUNTER_TERRORIST = 1, TERRORIST = 2 }
```

### シグナル
```gdscript
signal died(killer: Node3D)
signal damaged(amount: float, attacker: Node3D, is_headshot: bool)
signal healed(amount: float)
```

### エクスポート設定
```gdscript
@export var max_health: float = 100.0
@export var team: Team = Team.NONE
```

### 状態
```gdscript
var current_health: float = 100.0
var is_alive: bool = true
var anim_ctrl: Node = null  # StrafeAnimationController
```

### HP API
```gdscript
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void
func heal(amount: float) -> void
func get_health_ratio() -> float
func reset_health() -> void
```

### チーム API
```gdscript
func is_enemy_of(other: MixamoCharacter) -> bool
```

### アニメーションコントローラー連携
```gdscript
func set_anim_controller(controller: Node) -> void
func get_anim_controller() -> Node
```

## 使用例

### 基本的な使用

```gdscript
extends MixamoCharacter

const AnimCtrl = preload("res://scripts/animation/strafe_animation_controller.gd")

@onready var model: Node3D = $CharacterModel
@onready var anim_player: AnimationPlayer = $CharacterModel/AnimationPlayer

func _ready() -> void:
    super._ready()

    # アニメーションコントローラー設定
    var ctrl = AnimCtrl.new()
    add_child(ctrl)
    ctrl.setup(model, anim_player)
    set_anim_controller(ctrl)

    # チーム設定
    team = Team.TERRORIST

func _physics_process(delta: float) -> void:
    if not is_alive:
        return

    # 移動処理...
```

### ダメージ処理

```gdscript
# ダメージを与える
character.take_damage(25.0, attacker, false)

# ヘッドショット
character.take_damage(100.0, attacker, true)

# 回復
character.heal(50.0)
```

### 敵判定

```gdscript
if character.is_enemy_of(other_character):
    character.take_damage(50.0, other_character, false)
```

## 死亡処理

`take_damage()`でHPが0以下になると自動的に:
1. `is_alive = false` に設定
2. StrafeAnimationController経由で死亡アニメーション再生
3. コリジョン無効化
4. `died`シグナル発火

## 参照
- [StrafeAnimationController API](strafe-animation-controller.md)
