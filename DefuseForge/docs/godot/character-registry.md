# Character Registry & Preset System

キャラクタープリセットの管理とチーム別キャラクター選択システム。

## ファイル構成

```
scripts/
  resources/
    character_preset.gd    # キャラクター定義リソース
  registries/
    character_registry.gd  # プリセット管理（Autoload）

data/
  characters/
    soldier_t.tres         # Terroristサンプル
    soldier_ct.tres        # Counter-Terroristサンプル

assets/
  characters/
    terrorist/             # T側モデル配置先
    counter_terrorist/     # CT側モデル配置先
```

## CharacterPreset

キャラクターのメタデータを定義するリソース。

### プロパティ

```gdscript
# Basic Info
@export var id: String              # 一意のID（"soldier_t"など）
@export var display_name: String    # UI表示名
@export var description: String     # 説明文

# Team
@export var team: MixamoCharacter.Team  # NONE=0, CT=1, T=2

# Model
@export var model_scene: PackedScene    # キャラクターモデル

# Stats
@export var max_health: float = 100.0
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0

# UI
@export var icon: Texture2D         # 選択UI用アイコン
@export var portrait: Texture2D     # 詳細表示用
```

### プリセット作成手順

1. Godotエディタで `data/characters/` を右クリック
2. 「新規リソース」→ `CharacterPreset` を選択
3. インスペクタで各プロパティを設定
4. `.tres` として保存

## CharacterRegistry

Autoloadシングルトン。起動時に `data/characters/*.tres` を自動読み込み。

### Query API

```gdscript
# IDでプリセット取得
var preset = CharacterRegistry.get_preset("soldier_t")

# チーム別に取得
var terrorists = CharacterRegistry.get_terrorists()
var cts = CharacterRegistry.get_counter_terrorists()

# 全プリセット取得
var all = CharacterRegistry.get_all()
```

### Factory API

```gdscript
# プリセットIDからキャラクター生成
var character = CharacterRegistry.create_character("soldier_t", spawn_position)

# プリセットオブジェクトから生成
var character = CharacterRegistry.create_character_from_preset(preset, spawn_position)
```

生成されるキャラクターの構造：
```
MixamoCharacter
├── CharacterModel (model_scene)
│   └── AnimationPlayer
├── CollisionShape3D
└── StrafeAnimationController
```

## 新しいキャラクター追加手順

### 1. モデル配置

```
assets/characters/terrorist/bomber/
  bomber.glb
  textures/
```

### 2. GLBをシーンとしてインポート

Godotでインポート設定 → 「シーンとして保存」

### 3. プリセット作成

`data/characters/bomber_t.tres`:
```
[gd_resource type="Resource" script_class="CharacterPreset" ...]

id = "bomber_t"
display_name = "Bomber"
team = 2  # TERRORIST
model_scene = "res://assets/characters/terrorist/bomber/bomber.tscn"
max_health = 80.0
```

### 4. 使用

```gdscript
# ゲームコードで
var bomber = CharacterRegistry.create_character("bomber_t", Vector3(0, 0, 5))
add_child(bomber)
```

## チーム選択UI例

```gdscript
func _show_team_selection():
    var terrorists = CharacterRegistry.get_terrorists()
    for preset in terrorists:
        var button = Button.new()
        button.text = preset.display_name
        button.pressed.connect(_on_character_selected.bind(preset))
        terrorist_container.add_child(button)

func _on_character_selected(preset: CharacterPreset):
    var character = CharacterRegistry.create_character_from_preset(preset, spawn_point)
    game_world.add_child(character)
```

## 参照
- [MixamoCharacter API](mixamo-character.md)
- [StrafeAnimationController API](strafe-animation-controller.md)
