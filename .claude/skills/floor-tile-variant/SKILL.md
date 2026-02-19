---
name: floor-tile-variant
description: 床タイルのバリアント（縁・角グラデーション）を作成する。プロシージャルノード→ベイクでGLTF互換を保証。
allowed-tools: mcp__blender__execute_blender_code, mcp__blender__get_viewport_screenshot, mcp__blender__get_scene_info, mcp__blender__download_polyhaven_asset, mcp__blender__search_polyhaven_assets
---

# 床タイルバリアント作成

既存の床タイルから縁や角にグラデーション効果を付けたバリアントを作成する。
プロシージャルノードで効果を作成し、テクスチャベイクでGLTF互換にする。

## 前提

- **Blender MCP** 接続済み（`tile_library.blend` を開いた状態）
- ベースとなる床タイルが存在すること（例: `floor_wood_worn`）
- 床タイルの厚みは **0.1m**（統一規格）
- グリッドサイズは **1.5m × 1.5m**

## ワークフロー概要

```
1. ベースタイルを複製
2. ユニークマテリアルを作成
3. プロシージャルノードでグラデーション追加
4. Cyclesでテクスチャベイク
5. マテリアルをベイクテクスチャのみに簡素化
6. tile-exportスキルでエクスポート
```

## Step 1: ベースタイルの複製

```python
import bpy

base_obj = bpy.data.objects.get("floor_wood_worn")

# エッジバリアント（1辺グラデーション）
edge_obj = base_obj.copy()
edge_obj.data = base_obj.data.copy()
edge_obj.name = "floor_wood_worn_edge"
bpy.context.scene.collection.children["floor_wood_worn_edge"].objects.link(edge_obj)
# ※ コレクションは事前に作成するか、既存のものを使用

# コーナーバリアント（L字2辺グラデーション）
corner_obj = base_obj.copy()
corner_obj.data = base_obj.data.copy()
corner_obj.name = "floor_wood_worn_corner"
bpy.context.scene.collection.children["floor_wood_worn_corner"].objects.link(corner_obj)
```

> **重要**: `.data`（メッシュ）もコピーすること。`data`を共有するとマテリアル変更が元オブジェクトに影響する。

## Step 2: ユニークマテリアルの作成

> **絶対禁止**: 共有マテリアルを直接編集しないこと。
> ベースタイルのマテリアルをそのまま変更すると、元タイルが壊れる。

```python
for obj in [edge_obj, corner_obj]:
    for i, slot in enumerate(obj.material_slots):
        if slot.material:
            unique_mat = slot.material.copy()
            unique_mat.name = f"{slot.material.name}_{obj.name}"
            slot.material = unique_mat
```

## Step 3: プロシージャルグラデーションの追加

### エッジパターン（1辺）

Y軸方向の片側にだけ黒いグラデーションを付ける。

```python
obj = bpy.data.objects.get("floor_wood_worn_edge")
mat = obj.material_slots[0].material
tree = mat.node_tree
bsdf = tree.nodes.get("Principled BSDF")

# 既存のBase Color接続元を取得
original_color_link = None
for link in tree.links:
    if link.to_socket == bsdf.inputs["Base Color"]:
        original_color_link = link.from_socket
        break

# Generated座標 → SeparateXYZ → ColorRamp → Mix
tex_coord = tree.nodes.new("ShaderNodeTexCoord")
sep_xyz = tree.nodes.new("ShaderNodeSeparateXYZ")
ramp = tree.nodes.new("ShaderNodeValToRGB")
mix = tree.nodes.new("ShaderNodeMix")
mix.data_type = 'RGBA'

# ColorRamp設定: 60%まで白(影響なし)、100%で黒(暗い縁)
ramp.color_ramp.elements[0].position = 0.6
ramp.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
ramp.color_ramp.elements[1].position = 1.0
ramp.color_ramp.elements[1].color = (0.1, 0.1, 0.1, 1.0)

# 接続
tree.links.new(tex_coord.outputs["Generated"], sep_xyz.inputs["Vector"])
tree.links.new(sep_xyz.outputs["Y"], ramp.inputs["Fac"])

# Mix: 元テクスチャ × グラデーション
mix.blend_type = 'MULTIPLY'
mix.inputs["Factor"].default_value = 1.0
if original_color_link:
    tree.links.new(original_color_link, mix.inputs[6])  # A
tree.links.new(ramp.outputs["Color"], mix.inputs[7])     # B
tree.links.new(mix.outputs[2], bsdf.inputs["Base Color"])  # Result
```

### コーナーパターン（L字2辺）

X軸とY軸の両方にグラデーションを付ける。

```python
obj = bpy.data.objects.get("floor_wood_worn_corner")
mat = obj.material_slots[0].material
tree = mat.node_tree
bsdf = tree.nodes.get("Principled BSDF")

original_color_link = None
for link in tree.links:
    if link.to_socket == bsdf.inputs["Base Color"]:
        original_color_link = link.from_socket
        break

tex_coord = tree.nodes.new("ShaderNodeTexCoord")
sep_xyz = tree.nodes.new("ShaderNodeSeparateXYZ")

# Y方向のグラデーション
ramp_y = tree.nodes.new("ShaderNodeValToRGB")
ramp_y.color_ramp.elements[0].position = 0.6
ramp_y.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
ramp_y.color_ramp.elements[1].position = 1.0
ramp_y.color_ramp.elements[1].color = (0.1, 0.1, 0.1, 1.0)

# X方向のグラデーション
ramp_x = tree.nodes.new("ShaderNodeValToRGB")
ramp_x.color_ramp.elements[0].position = 0.6
ramp_x.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
ramp_x.color_ramp.elements[1].position = 1.0
ramp_x.color_ramp.elements[1].color = (0.1, 0.1, 0.1, 1.0)

# X × Y を掛け合わせてL字に
mix_xy = tree.nodes.new("ShaderNodeMix")
mix_xy.data_type = 'RGBA'
mix_xy.blend_type = 'MULTIPLY'
mix_xy.inputs["Factor"].default_value = 1.0

mix_final = tree.nodes.new("ShaderNodeMix")
mix_final.data_type = 'RGBA'
mix_final.blend_type = 'MULTIPLY'
mix_final.inputs["Factor"].default_value = 1.0

# 接続
tree.links.new(tex_coord.outputs["Generated"], sep_xyz.inputs["Vector"])
tree.links.new(sep_xyz.outputs["Y"], ramp_y.inputs["Fac"])
tree.links.new(sep_xyz.outputs["X"], ramp_x.inputs["Fac"])

# ramp_x × ramp_y → L字グラデーション
tree.links.new(ramp_x.outputs["Color"], mix_xy.inputs[6])
tree.links.new(ramp_y.outputs["Color"], mix_xy.inputs[7])

# 元テクスチャ × L字グラデーション
if original_color_link:
    tree.links.new(original_color_link, mix_final.inputs[6])
tree.links.new(mix_xy.outputs[2], mix_final.inputs[7])
tree.links.new(mix_final.outputs[2], bsdf.inputs["Base Color"])
```

## Step 4: テクスチャベイク

> **重要**: プロシージャルノード（Generated, ColorRamp, SeparateXYZ, Mix等）は
> GLTFエクスポートで保持されない。必ずベイクする。

```python
import bpy

def bake_object_diffuse(obj_name, image_size=1024):
    obj = bpy.data.objects.get(obj_name)
    if not obj:
        print(f"Object not found: {obj_name}")
        return

    # Cyclesに切替
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 32
    bpy.context.scene.cycles.use_denoising = False

    # オブジェクトを選択・アクティブに
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    # ベイクターゲット画像を作成
    img_name = f"bake_{obj_name}"
    if img_name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[img_name])
    bake_img = bpy.data.images.new(img_name, image_size, image_size)

    # 各マテリアルにベイクターゲットノードを追加
    for slot in obj.material_slots:
        tree = slot.material.node_tree
        # 既存のBakeTargetがあれば削除
        for node in list(tree.nodes):
            if node.name == "BakeTarget":
                tree.nodes.remove(node)

        img_node = tree.nodes.new("ShaderNodeTexImage")
        img_node.image = bake_img
        img_node.name = "BakeTarget"
        tree.nodes.active = img_node  # ベイク先はアクティブノード

    # ベイク実行
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})

    # ベイク画像を保存
    import os
    PROJECT_ROOT = "/Users/iwasakishungo/Git/github.com/iwasaki1112/RescueForge"
    output_path = os.path.join(PROJECT_ROOT, "godot", "scenes", "tiles", f"{obj_name}_baked.png")
    bake_img.filepath_raw = output_path
    bake_img.file_format = 'PNG'
    bake_img.save()

    # マテリアルをベイクテクスチャのみに簡素化
    for slot in obj.material_slots:
        tree = slot.material.node_tree
        bsdf = tree.nodes.get("Principled BSDF")
        bake_node = tree.nodes.get("BakeTarget")
        output_node = tree.nodes.get("Material Output")

        # 不要ノードを全削除
        keep_nodes = {bsdf, bake_node, output_node}
        for node in list(tree.nodes):
            if node not in keep_nodes:
                tree.nodes.remove(node)

        # ベイクテクスチャ → BSDF
        tree.links.clear()
        tree.links.new(bake_node.outputs["Color"], bsdf.inputs["Base Color"])
        tree.links.new(bsdf.outputs["BSDF"], output_node.inputs["Surface"])

    print(f"Baked: {obj_name} → {output_path}")

# 各バリアントをベイク
bake_object_diffuse("floor_wood_worn_edge")
bake_object_diffuse("floor_wood_worn_corner")
```

## Step 5: 確認とエクスポート

1. `mcp__blender__get_viewport_screenshot` でベイク結果を視覚確認
2. グラデーションの方向と強さが正しいか確認
3. **tile-export** スキルを実行してGLBエクスポート + MeshLibrary再生成

## 床タイル共通仕様

| 項目 | 値 |
|------|-----|
| グリッドサイズ | 1.5m × 1.5m |
| 厚み | 0.1m |
| 頂点数（フラット） | 8（上面4 + 底面4） |
| Layer | Layer 1（GridMap） |
| 命名規則 | `floor_*` または `ground_*` |

### 厚みが0の場合の修正

ベースタイルの厚みが0（4頂点フラットプレーン）の場合、0.1m厚に修正:

```python
import bpy
import bmesh

obj = bpy.data.objects.get("floor_wood_worn")
bm = bmesh.new()
bm.from_mesh(obj.data)

# 全面を-Z方向に0.1m押し出し
result = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
extruded_verts = [v for v in result['geom'] if isinstance(v, bmesh.types.BMVert)]
bmesh.ops.translate(bm, verts=extruded_verts, vec=(0, 0, -0.1))

bm.to_mesh(obj.data)
bm.free()
```

## よくあるミス

| ミス | 原因 | 対処 |
|------|------|------|
| Godotでグラデーション消失 | プロシージャルノード未ベイク | Step 4でベイク必須 |
| ベースタイルが壊れる | 共有マテリアルを直接編集 | Step 2でユニークコピー作成 |
| ベイク画像が真っ黒 | BakeTargetがアクティブでない | `tree.nodes.active = img_node` |
| 厚みが不揃い | タイルごとに異なる頂点構成 | 全タイル0.1mに統一 |
| Z座標がずれる | タイルの原点位置が不統一 | 上面がZ=0、底面がZ=-0.1 |

## プレビュー画像の生成

Godotエディタでのプレビュー表示には、適切なライティングが必要:

```python
import bpy

# ワールドアンビエント光
world = bpy.context.scene.world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs["Color"].default_value = (0.8, 0.8, 0.85, 1.0)
bg.inputs["Strength"].default_value = 1.5

# キーライト（太陽）
key_light = bpy.data.lights.new("KeySun", 'SUN')
key_light.energy = 5.0
key_obj = bpy.data.objects.new("KeySun", key_light)
bpy.context.scene.collection.objects.link(key_obj)
key_obj.rotation_euler = (0.785, 0.0, 0.785)  # 45度斜め上

# フィルライト
fill_light = bpy.data.lights.new("FillSun", 'SUN')
fill_light.energy = 2.0
fill_obj = bpy.data.objects.new("FillSun", fill_light)
bpy.context.scene.collection.objects.link(fill_obj)
fill_obj.rotation_euler = (-0.785, 0.0, -0.785)
```

> **注意**: ライトなしだとプレビュー画像が真っ黒になる。

## 関連ファイル

| ファイル | 責務 |
|---------|------|
| `blender/tiles/tile_library.blend` | タイルアセットソース |
| `godot/scenes/tiles/*.glb` | エクスポートされたGLBタイル |
| `godot/data/tiles/tile_library_floor.tres` | 床タイルMeshLibrary |

## 関連スキル

- **tile-export**: エクスポートとMeshLibrary再生成
- **wall-texture**: 壁タイルテクスチャ適用
