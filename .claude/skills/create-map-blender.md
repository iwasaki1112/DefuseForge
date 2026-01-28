# Blender Map Creation Skill

Blenderでマップを作成し、Godotにインポートする手順。

## 概要

RescueForgeのマップはBlenderで作成し、GLTFとしてエクスポートしてGodotにインポートする。コリジョンと視界遮蔽を正しく動作させるには、命名規則とレイヤー設定が重要。

## 命名規則

### プレフィックス（種類識別）

| プレフィックス | 用途 | 例 |
|--------------|------|-----|
| `wall_` | 壁（視界遮蔽・パス遮断） | `wall_01-col` |
| `door_` | ドア（開閉可能、視界遮蔽・パス遮断） | `door_01-col` |
| `spawn_` | スポーンポイント | `spawn_ct_1`, `spawn_t_1` |

### サフィックス（コリジョン自動生成）

Godotはメッシュ名のサフィックスでコリジョンを自動生成する：

| サフィックス | 生成されるコリジョン | 用途 |
|-------------|---------------------|------|
| `-col` | ConvexPolygonShape3D + メッシュ表示 | 床、壁、ドア |
| `-colonly` | ConvexPolygonShape3D（メッシュ非表示） | 不可視コリジョン |
| `-trimesh` | ConcavePolygonShape3D | 複雑な形状 |

### 命名例

```
wall_01-col      # 壁1（コリジョン付き）
wall_02-col      # 壁2
door_01-col      # ドア1（コリジョン付き、コードで開閉可能）
door_vault-col   # 金庫室ドア
Map_Ground-col   # 床
spawn_ct_1       # CTスポーン1
spawn_t_1        # Tスポーン1
```

## マップ作成手順

### 1. 床を作成

```python
import bpy

# 床を作成
bpy.ops.mesh.primitive_plane_add(size=15, location=(0, 0, 0))
floor = bpy.context.active_object
floor.name = "Map_Ground-col"  # コリジョン用サフィックス

# マテリアル追加
mat = bpy.data.materials.new(name="Ground_Material")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.35, 0.35, 0.35, 1)
bsdf.inputs["Roughness"].default_value = 0.9
floor.data.materials.append(mat)

print(f"Created floor: {floor.name}")
```

### 2. 壁を作成

```python
import bpy

# 壁を作成
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1))
wall = bpy.context.active_object
wall.name = "wall_01-col"  # 重要: wall_プレフィックス + -colサフィックス
wall.scale = (0.2, 6, 2)  # 厚さ0.2m、長さ6m、高さ2m

# スケールを適用
bpy.ops.object.transform_apply(scale=True)

# マテリアル追加
mat = bpy.data.materials.new(name="Wall_Material")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.5, 0.4, 0.35, 1)
bsdf.inputs["Roughness"].default_value = 0.8
wall.data.materials.append(mat)

print(f"Created wall: {wall.name}")
```

### 3. ドアを作成

ドアは開閉アニメーション用に回転軸（原点）をヒンジ位置に設定する。

```python
import bpy
from mathutils import Vector

# ドアを作成（幅0.9m、高さ2m、厚さ0.05m）
bpy.ops.mesh.primitive_cube_add(size=1, location=(2, 0, 1))
door = bpy.context.active_object
door.name = "door_01-col"  # door_プレフィックス + -colサフィックス
door.scale = (0.9, 0.05, 2)

# スケールを適用
bpy.ops.object.transform_apply(scale=True)

# 原点を右端（ヒンジ位置）に移動
bpy.ops.object.select_all(action='DESELECT')
door.select_set(True)
bpy.context.view_layer.objects.active = door

# まず原点をジオメトリ中心に
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')

# バウンディングボックスから右端を計算
bbox = [door.matrix_world @ Vector(corner) for corner in door.bound_box]
max_x = max(v.x for v in bbox)
min_z = min(v.z for v in bbox)
center_y = (min(v.y for v in bbox) + max(v.y for v in bbox)) / 2

# 3Dカーソルを右端下部に移動し、原点を設定
bpy.context.scene.cursor.location = (max_x, center_y, min_z)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
bpy.context.scene.cursor.location = (0, 0, 0)  # カーソルをリセット

# マテリアル追加
mat = bpy.data.materials.new(name="Door_Material")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.4, 0.25, 0.15, 1)  # 茶色
bsdf.inputs["Roughness"].default_value = 0.7
door.data.materials.append(mat)

print(f"Created door: {door.name}")
print(f"Origin (hinge): {door.location}")
```

### 4. スポーンポイントを作成

```python
import bpy
from mathutils import Euler
import math

# CTスポーン（マップの一方の端）
for i, pos in enumerate([(-4.5, -5.25, 0), (-1.5, -5.25, 0)]):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=pos)
    spawn = bpy.context.active_object
    spawn.name = f"spawn_ct_{i+1}"
    # 敵の方向（+Y）を向く
    spawn.rotation_euler = Euler((0, 0, math.radians(180)), 'XYZ')

# Tスポーン（マップの反対側）
for i, pos in enumerate([(4.5, 5.25, 0), (1.5, 5.25, 0)]):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=pos)
    spawn = bpy.context.active_object
    spawn.name = f"spawn_t_{i+1}"
    # デフォルトで-Y方向を向く

print("Spawn points created")
```

### 5. GLTFエクスポート

```python
import bpy

export_path = "/path/to/godot/scenes/maps/my_map.gltf"

bpy.ops.export_scene.gltf(
    filepath=export_path,
    export_format='GLTF_SEPARATE',  # .gltf + .bin
    export_apply=True  # モディファイアを適用
)

print(f"Exported to: {export_path}")
```

## Godot側の設定

### 1. シーンファイル作成（.tscn）

GLTFをインスタンス化し、スクリプトをアタッチする：

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/maps/my_map.gltf" id="1_gltf"]
[ext_resource type="Script" path="res://scripts/maps/my_map.gd" id="2_script"]

[node name="MyMap" instance=ExtResource("1_gltf")]
script = ExtResource("2_script")
```

### 2. マップスクリプト作成

壁・ドアの`collision_layer`を2に設定（視界遮蔽・パス遮断に必要）：

```gdscript
# scripts/maps/my_map.gd
extends Node3D

const WALL_COLLISION_LAYER: int = 2

func _ready() -> void:
    _setup_collisions(self)
    VisionComponent.invalidate_wall_cache()

func _setup_collisions(node: Node) -> void:
    if node is StaticBody3D:
        var parent = node.get_parent()
        if parent:
            var parent_name_lower = parent.name.to_lower()
            # wall_ または door_ プレフィックスはレイヤー2に設定
            if parent_name_lower.begins_with("wall_") or parent_name_lower.begins_with("door_"):
                node.collision_layer = WALL_COLLISION_LAYER
    for child in node.get_children():
        _setup_collisions(child)
```

### 3. MapPreset作成（.tres）

```
[gd_resource type="Resource" script_class="MapPreset" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/resources/map_preset.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://scenes/maps/my_map.tscn" id="2_scene"]

[resource]
script = ExtResource("1_script")
id = "my_map"
display_name = "My Map"
description = "Custom tactical map"
map_scene = ExtResource("2_scene")
map_size = Vector2(15, 15)
spawn_points_ct = Array[Vector3]([])
spawn_points_t = Array[Vector3]([])
```

### 4. MapRegistryに登録

`godot/scripts/registries/map_registry.gd`の`_presets_paths`に追加：

```gdscript
const _presets_paths: Array[String] = [
    "res://data/maps/test.tres",
    "res://data/maps/my_map.tres",  # 追加
]
```

## チェックリスト

- [ ] 床メッシュに`-col`サフィックスを付けた
- [ ] 壁メッシュに`wall_`プレフィックスと`-col`サフィックスを付けた
- [ ] ドアメッシュに`door_`プレフィックスと`-col`サフィックスを付けた
- [ ] ドアの原点をヒンジ位置（右端または左端）に設定した
- [ ] スポーンポイント（Empty）を作成した（`spawn_ct_*`、`spawn_t_*`）
- [ ] GLTFとしてエクスポートした
- [ ] マップスクリプトで壁・ドアの`collision_layer = 2`を設定した
- [ ] MapPresetを作成してMapRegistryに登録した

## トラブルシューティング

### キャラクターが床を突き抜ける
- 床メッシュ名に`-col`サフィックスがあるか確認
- Godotでリインポート（右クリック→再インポート）

### 壁・ドアで視界が遮られない
- メッシュ名が`wall_`または`door_`で始まり、`-col`で終わるか確認
- マップスクリプトで`collision_layer = 2`を設定しているか確認
- `VisionComponent.invalidate_wall_cache()`を呼んでいるか確認

### パスがドアを貫通する
- ドアメッシュ名が`door_`プレフィックスで始まるか確認
- マップスクリプトでドアも`collision_layer = 2`に設定されているか確認

### 移動中に視界が追従しない
- `PathFollowingController`が`_facing_direction`を更新しているか確認
- 詳細は`docs/godot/api/PathFollowingController.md`を参照

## 関連ドキュメント

- `docs/godot/api/MapPreset.md` - マッププリセット詳細
- `docs/godot/api/VisionComponent.md` - 視界システム詳細
- `docs/godot/api/MapRegistry.md` - マップ登録
- `docs/godot/api/CharacterAnimationController.md` - ドアキックアニメーション
