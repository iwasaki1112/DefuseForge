# MapPreset

マッププリセットリソース。マップのメタデータ、シーン参照、スポーン位置を定義する。

## 基本情報

| 項目 | 内容 |
|------|------|
| スクリプト | `res://scripts/resources/map_preset.gd` |
| 基底クラス | Resource |
| プリセット配置 | `res://data/maps/` |

## プロパティ

### Basic Info

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `id` | String | `""` | ユニークID（例: "test_map", "warehouse"） |
| `display_name` | String | `""` | UI表示用の名前 |
| `description` | String | `""` | マップの説明文 |

### Scene

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `map_scene` | PackedScene | `null` | マップシーン（.tscn） |

### Map Settings

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `map_size` | Vector2 | `(50, 50)` | FogOfWarSystem用のマップサイズ |

### Spawn Points

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `spawn_points_ct` | Array[Vector3] | `[]` | Counter-Terroristスポーン位置 |
| `spawn_points_t` | Array[Vector3] | `[]` | Terroristスポーン位置 |

### UI

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `thumbnail` | Texture2D | `null` | マップ選択UI用サムネイル |

## 使用例

### プリセット作成（.tres）

```gdscript
[gd_resource type="Resource" script_class="MapPreset" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/map_preset.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://scenes/maps/my_map.tscn" id="2_scene"]

[resource]
script = ExtResource("1_script")
id = "my_map"
display_name = "My Custom Map"
description = "A custom tactical map"
map_scene = ExtResource("2_scene")
map_size = Vector2(60, 60)
spawn_points_ct = Array[Vector3]([Vector3(-20, 0, -20), Vector3(-18, 0, -20)])
spawn_points_t = Array[Vector3]([Vector3(20, 0, 20), Vector3(18, 0, 20)])
```

### コードから取得

```gdscript
# MapRegistryからプリセット取得
var preset = MapRegistry.get_preset("test_map")
print(preset.display_name)  # "Test Map"
print(preset.map_size)      # Vector2(50, 50)

# スポーン位置を取得
for pos in preset.spawn_points_ct:
    print("CT spawn: ", pos)
```

## マップシーン構造

MapPresetが参照するマップシーン（.tscn）の推奨構造:

```
MapRoot (Node3D)
├── Environment (Node3D)
│   ├── DirectionalLight3D
│   └── WorldEnvironment
├── Floor (StaticBody3D) [collision_layer=1]
│   ├── CSGBox3D / MeshInstance3D
│   └── CollisionShape3D
├── Walls (Node3D)
│   └── Wall_* (StaticBody3D) [collision_layer=2]
│       └── CSGBox3D / GridMap
├── SpawnPoints (Node3D)
│   ├── CT_Spawns (Node3D)
│   │   └── Spawn* (Marker3D)
│   └── T_Spawns (Node3D)
│       └── Spawn* (Marker3D)
└── Navigation (NavigationRegion3D) [オプション]
```

## コリジョンレイヤー

| Layer | Bit | 用途 |
|-------|-----|------|
| 1 | `1` | キャラクター、床 |
| 2 | `2` | 壁・障害物（VisionComponent用） |

壁（collision_layer=2）は自動的に"walls"グループに追加され、VisionComponentの視界計算で使用される。

## 関連クラス

- [MapRegistry](MapRegistry.md) - プリセット管理・マップインスタンス化
- [GameManager](GameManager.md) - load_map()でマップロード
- [VisionComponent](VisionComponent.md) - 壁グループを使用した視界計算
- [FogOfWarSystem](FogOfWarSystem.md) - map_sizeを使用
