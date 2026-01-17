# CharacterPreset

キャラクタープリセット定義リソース。チーム選択用のメタデータを格納。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Resource` |
| ファイルパス | `scripts/resources/character_preset.gd` |

## Export Properties

### Basic Info
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `id` | `String` | `""` | 一意識別子（例: "bomber", "breacher"） |
| `display_name` | `String` | `""` | UI表示名 |
| `description` | `String` | `""` | キャラクター説明 |

### Team
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `team` | `GameCharacter.Team` | `NONE` | 所属チーム |

### Model
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `model_scene` | `PackedScene` | - | キャラクターモデル（GLBシーン） |

### Stats
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `max_health` | `float` | `100.0` | 最大HP |

> **Note:** 移動速度（`walk_speed`, `run_speed`）は`CharacterAnimationController`で一元管理される。

### UI
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `icon` | `Texture2D` | - | 選択UI用アイコン |
| `portrait` | `Texture2D` | - | 詳細表示用ポートレート |

## 使用例

### GDScriptでの作成
```gdscript
var preset = CharacterPreset.new()
preset.id = "bomber"
preset.display_name = "Bomber"
preset.description = "Explosive specialist"
preset.team = GameCharacter.Team.TERRORIST
preset.model_scene = preload("res://assets/characters/bomber.glb")
preset.max_health = 100.0
```

### .tresファイル（エディタで作成）
`res://data/characters/bomber.tres`:
```
[gd_resource type="Resource" script_class="CharacterPreset" ...]

[resource]
id = "bomber"
display_name = "Bomber"
team = 2
model_scene = ExtResource("...")
max_health = 100.0
```

## CharacterRegistryとの連携

1. `data/characters/`に`.tres`ファイルを配置
2. `CharacterRegistry`が自動的に読み込み
3. `CharacterRegistry.create_character("bomber")`で使用
