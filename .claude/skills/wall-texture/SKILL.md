---
name: wall-texture
description: 壁タイルにPolyHavenテクスチャを適用する。内側/外側/上面の3マテリアル構成、GLTF互換のみ使用。
allowed-tools: mcp__blender__execute_blender_code, mcp__blender__get_viewport_screenshot, mcp__blender__get_scene_info, mcp__blender__download_polyhaven_asset, mcp__blender__search_polyhaven_assets, mcp__blender__get_polyhaven_categories
---

# 壁タイルテクスチャ適用

BlenderMCPを使用して壁タイルにPolyHavenテクスチャを適用するワークフロー。
内側（室内）、外側（外壁）、上面（白）の3マテリアル構成。

## 前提

- **Blender MCP** 接続済み（`tile_library.blend` を開いた状態）
- 壁タイルメッシュがシーンに存在すること（`wall_straight-col`, `wall_corner-col` 等）
- タイルは `-col` サフィックス付きの場合あり

## 重要な制約（GLTF互換性）

> **絶対に守ること**: GLTF/GLBエクスポートではBlenderのプロシージャルノードは保持されない。

以下のノードは **使用禁止**（エクスポート後に消える）:
- `Generated` / `Object` テクスチャ座標
- `ColorRamp` (ValToRGB)
- `SeparateXYZ` / `CombineXYZ`
- `Math` ノード
- `Mix` ノード（Color Mix含む）
- `Bright/Contrast` ノード

**使用可能なノード**:
- `Image Texture`（UV座標）
- `Normal Map`
- `Hue/Saturation/Value` (HSV)
- `Mapping` + `Texture Coordinate (UV)`
- `Principled BSDF` の標準入力

プロシージャルな効果（汚れグラデーション等）が必要な場合は、**テクスチャベイクが必須**。
ベイク手順は「テクスチャベイク」セクションを参照。

## Step 1: PolyHavenテクスチャの選定とダウンロード

### 推奨テクスチャ

| 用途 | テクスチャ | 備考 |
|------|-----------|------|
| 室内壁（白系） | `beige_wall_001` | HSVでValue上げて白く調整 |
| 外壁（レンガ） | `brick_wall_02` | Mapping Scaleで大きさ調整 |
| ドアパネル | `dark_wood` | ドアパネルのみ。フレームは壁と同じ |

### ダウンロード

```python
# mcp__blender__download_polyhaven_asset で1kテクスチャをダウンロード
# asset_name: "beige_wall_001", type: "textures", resolution: "1k"
```

ダウンロード後、Blender内のマテリアルにImage Textureノードが自動作成される。

## Step 2: 室内側マテリアル（beige_wall_001）

### HSV調整で白く

> **注意**: `Bright/Contrast` ノードは使わないこと。テクスチャ感が消えて単色に見える。
> HSVノードのみで調整する。

```python
import bpy

mat = bpy.data.materials.get("beige_wall_001")
tree = mat.node_tree
bsdf = tree.nodes.get("Principled BSDF")

# Diffuseテクスチャノードを探す
diffuse_tex = None
for node in tree.nodes:
    if node.type == 'TEX_IMAGE' and node.image and 'diff' in node.image.name.lower():
        diffuse_tex = node
        break

# HSVノードを挿入（テクスチャ → HSV → BSDF）
hsv = tree.nodes.new("ShaderNodeHueSaturation")
hsv.inputs["Hue"].default_value = 0.5        # デフォルト
hsv.inputs["Saturation"].default_value = 0.4  # 彩度を下げて白っぽく
hsv.inputs["Value"].default_value = 1.45      # 明度を上げる
tree.links.new(diffuse_tex.outputs["Color"], hsv.inputs["Color"])
tree.links.new(hsv.outputs["Color"], bsdf.inputs["Base Color"])
```

### ノーマルマップ

```python
# nor_gl（OpenGL形式）のテクスチャノードを探す
nor_tex = None
for node in tree.nodes:
    if node.type == 'TEX_IMAGE' and node.image and 'nor_gl' in node.image.name.lower():
        nor_tex = node
        break

if nor_tex:
    nor_tex.image.colorspace_settings.name = "Non-Color"
    normal_map = tree.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 1.5
    tree.links.new(nor_tex.outputs["Color"], normal_map.inputs["Color"])
    tree.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
```

## Step 3: 外壁マテリアル（brick_wall_02）

### Mapping Scaleの注意

> **重要**: Blender Mapping ノードの Scale は **値が大きいほどテクスチャパターンが大きく** なる。
> 直感に反するので注意。小さくするとパターンが細かくなる。

```python
mat = bpy.data.materials.get("brick_wall_02")
tree = mat.node_tree

# テクスチャ座標は必ずUVを使う（Objectは壁で縞模様になる）
tex_coord = tree.nodes.new("ShaderNodeTexCoord")
mapping = tree.nodes.new("ShaderNodeMapping")

# レンガの大きさ調整: (3.0, 1.5, 1.0) = 横長に引き伸ばし
mapping.inputs["Scale"].default_value = (3.0, 1.5, 1.0)

tree.links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

# 全Image Textureノードにマッピングを接続
for node in tree.nodes:
    if node.type == 'TEX_IMAGE':
        tree.links.new(mapping.outputs["Vector"], node.inputs["Vector"])
```

> **注意**: テクスチャ座標は必ず `UV` を使う。`Object` 座標は壁の面が座標軸と平行でない場合に
> 縦縞のアーティファクトが出る。

### ノーマルマップ

beige_wall_001と同様にnor_glテクスチャにNormal Mapノードを接続する。

## Step 4: 上面マテリアル（白プレーン）

```python
white_mat = bpy.data.materials.new(name="wall_top_white")
white_mat.use_nodes = True
tree = white_mat.node_tree
bsdf = tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
bsdf.inputs["Roughness"].default_value = 0.8
```

## Step 5: 面法線によるマテリアル割り当て

壁タイルの面を法線方向で分類し、3つのマテリアルを割り当てる。

```python
import bpy
import bmesh

WALL_OBJECTS = ["wall_straight-col", "wall_corner-col", "wall_end-col", "wall_t-col", "wall_window-col"]

# マテリアル名
OUTSIDE_MAT = "brick_wall_02"    # index 0: 外側
INSIDE_MAT = "beige_wall_001"    # index 1: 内側
TOP_MAT = "wall_top_white"       # index 2: 上面

for obj_name in WALL_OBJECTS:
    obj = bpy.data.objects.get(obj_name)
    if not obj:
        continue

    # マテリアルスロット設定
    obj.data.materials.clear()
    obj.data.materials.append(bpy.data.materials.get(OUTSIDE_MAT))
    obj.data.materials.append(bpy.data.materials.get(INSIDE_MAT))
    obj.data.materials.append(bpy.data.materials.get(TOP_MAT))

    bm = bmesh.new()
    bm.from_mesh(obj.data)

    for face in bm.faces:
        n = face.normal
        area = face.calc_area()

        if n.z > 0.5:
            # 上面 → 白
            face.material_index = 2
        elif area >= 0.5 and (n.y > 0.5 or n.x > 0.5):
            # 外側（+Y / +X方向）→ レンガ
            face.material_index = 0
        elif area >= 0.5 and (n.y < -0.5 or n.x < -0.5):
            # 内側（-Y / -X方向）→ 白壁
            face.material_index = 1
        else:
            # その他（側面、底面等）→ 外側マテリアル
            face.material_index = 0

    bm.to_mesh(obj.data)
    bm.free()
```

> **注意**: 内側/外側の法線方向はタイルのモデリングに依存する。
> 適用後に必ずスクリーンショットで確認し、逆の場合はインデックス0と1を入れ替える。

## Step 6: ドアの特殊処理

ドアは2パーツ構成:
- **ドアフレーム** (`door_straight-col`): 壁と同じ3マテリアル構成
- **ドアパネル** (`door_straight_panel`): 木目テクスチャ（`dark_wood`）のみ

```python
# ドアパネルに木目テクスチャを適用
panel = bpy.data.objects.get("door_straight_panel")
if panel:
    panel.data.materials.clear()
    panel.data.materials.append(bpy.data.materials.get("dark_wood"))

# ドアフレームは壁と同じ処理（WALL_OBJECTSリストに含める）
```

> **注意**: ドアフレームにも木目を適用しないこと。フレームは壁と同じマテリアル構成にする。

## テクスチャベイク（プロシージャルエフェクト用）

汚れグラデーションなどプロシージャルノードを使う場合、GLTFエクスポート前にベイクが必要。

### 共有マテリアルのベイクに関する重大な注意

> **絶対禁止**: 共有マテリアルを直接ベイクしないこと。
> ベイクはマテリアルのノードツリーを破壊的に変更する。
> 共有マテリアルをベイクすると、そのマテリアルを使用する全オブジェクトが壊れる。

正しい手順:
1. ベイクするオブジェクトごとにマテリアルの **ユニークコピー** を作成
2. コピーしたマテリアルでベイク
3. ベイク後、ノードツリーをベイクテクスチャのみに簡素化

```python
import bpy

obj = bpy.data.objects.get("wall_straight-col")
bpy.context.view_layer.objects.active = obj

# マテリアルスロットごとにユニークコピーを作成
for i, slot in enumerate(obj.material_slots):
    if slot.material:
        unique_mat = slot.material.copy()
        unique_mat.name = f"{slot.material.name}_{obj.name}"
        slot.material = unique_mat

# ベイクターゲット画像を作成
bake_img = bpy.data.images.new("bake_target", 1024, 1024)

# 各マテリアルにベイクターゲットノードを追加
for slot in obj.material_slots:
    tree = slot.material.node_tree
    img_node = tree.nodes.new("ShaderNodeTexImage")
    img_node.image = bake_img
    img_node.name = "BakeTarget"
    tree.nodes.active = img_node  # アクティブにする（ベイク先）

# Cyclesでベイク
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})

# ベイク画像を保存
bake_img.filepath_raw = "/path/to/output/baked_texture.png"
bake_img.file_format = 'PNG'
bake_img.save()

# マテリアルをベイクテクスチャのみに簡素化
for slot in obj.material_slots:
    tree = slot.material.node_tree
    # 不要ノードを削除
    for node in list(tree.nodes):
        if node.type not in ('OUTPUT_MATERIAL', 'BSDF_PRINCIPLED', 'TEX_IMAGE'):
            tree.nodes.remove(node)
        elif node.type == 'TEX_IMAGE' and node.name != 'BakeTarget':
            tree.nodes.remove(node)
    # ベイクテクスチャ → BSDF接続
    bsdf = tree.nodes.get("Principled BSDF")
    bake_node = tree.nodes.get("BakeTarget")
    tree.links.new(bake_node.outputs["Color"], bsdf.inputs["Base Color"])
```

## よくあるミス

| ミス | 原因 | 対処 |
|------|------|------|
| テクスチャが単色に見える | Bright/Contrastノード使用 | HSVのみで調整 |
| レンガが細かすぎる | Mapping Scaleが小さい | Scaleを大きくする（3.0程度） |
| 壁に縦縞が出る | Object座標を使用 | UV座標に変更 |
| 内外テクスチャが逆 | 法線方向の判定ミス | スクリーンショットで確認、インデックス入替 |
| エクスポート後テクスチャ消失 | プロシージャルノード使用 | ベイクするかUVベースに変更 |
| 全壁が黒くなる | 共有マテリアルをベイク | ユニークコピー作成後にベイク |
| ドアフレームが木目 | パネルとフレーム未分離 | パネルのみ木目、フレームは壁マテリアル |

## 確認手順

1. マテリアル適用後、`mcp__blender__get_viewport_screenshot` でプレビュー確認
2. 内側/外側/上面が正しいか視覚的に検証
3. **エクスポート前に** tile-export スキルで書き出し → Godotで表示確認
4. テクスチャが正しく表示されない場合はプロシージャルノード使用を疑う

## 関連ファイル

| ファイル | 責務 |
|---------|------|
| `blender/tiles/tile_library.blend` | タイルアセットソース |
| `godot/scenes/tiles/*.glb` | エクスポートされたGLBタイル |
| `godot/data/tiles/tile_library_wall.tres` | 壁タイルMeshLibrary |

## 関連スキル

- **tile-export**: エクスポートとMeshLibrary再生成
- **floor-tile-variant**: 床タイルバリアント作成
