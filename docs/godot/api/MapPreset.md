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
├── Floor (CSGBox3D / MeshInstance3D) [use_collision=true]
├── Walls (Node3D)
│   └── Wall_* (CSGBox3D / StaticBody3D) [collision_layer=2]
├── SpawnPoints (Node3D) [オプション - MapPresetで座標指定も可]
│   ├── CT_Spawns (Node3D)
│   │   └── Spawn* (Marker3D)
│   └── T_Spawns (Node3D)
│       └── Spawn* (Marker3D)
└── Navigation (NavigationRegion3D) [オプション]
```

**重要: 環境設定について**

マップシーンにDirectionalLight3DやWorldEnvironmentを含めないこと。
環境設定（ライティング・影・レンダリング品質）はGameScreenの`EnvironmentSetup`が自動的に適用する。
詳細は [EnvironmentSetup](EnvironmentSetup.md) を参照。

## コリジョンレイヤー

| Layer | Bit | 用途 |
|-------|-----|------|
| 1 | `1` | キャラクター、床 |
| 2 | `2` | 壁・障害物（VisionComponent用） |

壁（collision_layer=2）はVisionComponentの視界計算で遮蔽物として検出される。

## GLTFマップの作成

BlenderでGLTFマップを作成する際の注意点：

### コリジョン自動生成

Godotはメッシュ名のサフィックスでコリジョンを自動生成する：

| サフィックス | 生成されるコリジョン | 用途 |
|-------------|---------------------|------|
| `-col` | ConvexPolygonShape3D | 壁、障害物 |
| `-colonly` | ConvexPolygonShape3D（メッシュ非表示） | 不可視コリジョン |
| `-trimesh` | ConcavePolygonShape3D | 複雑な形状 |

**例:**
```
Map_Ground-col    → 床メッシュ + コリジョン
Wall_Center-col   → 壁メッシュ + コリジョン
```

### 壁のcollision_layer設定

**重要**: GLTFインポート時に生成されるStaticBody3Dの`collision_layer`はデフォルト（1）。
VisionComponentで壁として検出するには`collision_layer = 2`に変更が必要。

マップシーン（.tscn）にスクリプトをアタッチして設定する：

```gdscript
# scripts/maps/my_map.gd
extends Node3D

const WALL_COLLISION_LAYER: int = 2

func _ready() -> void:
    _setup_wall_collisions(self)
    VisionComponent.invalidate_wall_cache()

func _setup_wall_collisions(node: Node) -> void:
    if node is StaticBody3D:
        var parent = node.get_parent()
        # 親ノード名に"wall"を含むStaticBody3Dを壁として扱う
        if parent and "wall" in parent.name.to_lower():
            node.collision_layer = WALL_COLLISION_LAYER
    for child in node.get_children():
        _setup_wall_collisions(child)
```

### GLTFマップのシーン構造例

```
scenes/maps/my_map.tscn
├── [instance: my_map.gltf]
└── script: scripts/maps/my_map.gd

my_map.gltf (Blenderからエクスポート)
├── Map_Ground-col (床 + コリジョン)
├── Wall_North-col (壁 + コリジョン)
├── Wall_South-col (壁 + コリジョン)
├── spawn_ct_1 (Empty → スポーン位置)
├── spawn_ct_2
├── spawn_t_1
└── spawn_t_2
```

## 関連クラス

- [MapRegistry](MapRegistry.md) - プリセット管理・マップインスタンス化
- [GameManager](GameManager.md) - load_map()でマップロード
- [VisionComponent](VisionComponent.md) - 壁グループを使用した視界計算
- [FogOfWarSystem](FogOfWarSystem.md) - map_sizeを使用
- [EnvironmentSetup](EnvironmentSetup.md) - 環境設定の自動適用
