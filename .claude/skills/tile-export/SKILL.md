---
name: tile-export
description: Blenderタイルをエクスポートし、不要ファイルのクリーンアップとGodot MeshLibrary再生成を自動実行する。
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, mcp__blender__get_scene_info, mcp__blender__execute_blender_code, mcp__blender__get_viewport_screenshot
---

# タイルエクスポート自動化

Blenderの `tile_library.blend` からタイルをエクスポートし、
古いファイルのクリーンアップとGodot MeshLibrary再生成を一括実行する。

## 前提

- **Blender MCP** が接続済みであること（`tile_library.blend` を開いた状態）
- **Godot** がインストール済み（`/Applications/Godot.app`）

## 自動実行フロー

以下を **この順番で全自動実行** する。ユーザーに途中確認は不要。

### Step 1: Blender接続確認 & シーン情報取得

`mcp__blender__get_scene_info` でBlender接続を確認。
失敗した場合は「Blenderを起動してMCPアドオンを有効にしてください」と伝えて終了。

成功したら、シーン内の全オブジェクト名を記録する。
これが「Blenderに存在するタイル」のソースオブトゥルースとなる。

### Step 2: Blenderからタイルをエクスポート

Blender MCPで以下のPythonコードを実行:

```python
import bpy
import os

PROJECT_ROOT = "/Users/iwasakishungo/Git/github.com/iwasaki1112/RescueForge"
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "godot", "scenes", "tiles")

def _export_glb(filepath):
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_yup=True,
    )

def _export_single_object(obj, tile_name):
    orig_loc = obj.location.copy()
    obj.location = (0, 0, 0)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    output_path = os.path.join(OUTPUT_DIR, f"{tile_name}.glb")
    _export_glb(output_path)
    obj.location = orig_loc
    return tile_name

os.makedirs(OUTPUT_DIR, exist_ok=True)
exported_names = []

for col in bpy.context.scene.collection.children:
    objects = list(col.objects)
    if not objects:
        continue
    if len(objects) == 1:
        exported_names.append(_export_single_object(objects[0], col.name))
        print(f"Exported: {col.name}.glb")
    else:
        for obj in objects:
            tile_name = obj.name.replace("-col", "")
            exported_names.append(_export_single_object(obj, tile_name))
            print(f"Exported: {tile_name}.glb")

print(f"\nEXPORTED_TILES={','.join(sorted(exported_names))}")
```

出力の `EXPORTED_TILES=` 行からエクスポートされたタイル名リストを取得する。

### Step 3: 不要ファイルのクリーンアップ

`godot/scenes/tiles/` にある `.glb` ファイルを走査し、
**Step 2でエクスポートされなかったGLBとその関連ファイルを削除** する。

**重要**: エクスポート済みタイルのファイルは絶対に削除しないこと。

クリーンアップは以下の手順で行う:

1. `Glob` ツールで `godot/scenes/tiles/*.glb` を取得
2. 各GLBファイル名（拡張子除去）がStep 2のエクスポートリストに含まれるか判定
3. **含まれないもののみ** を孤立ファイルとしてリストアップ
4. 孤立タイルごとに、以下のパターンでファイルを `rm -f` で削除:
   - `<tile_name>.glb` と `<tile_name>.glb.import`
   - `<tile_name>_*.jpg` / `<tile_name>_*.png` とそれぞれの `.import`

```bash
# 例: ground_alley_2 が孤立している場合
TILES_DIR="godot/scenes/tiles"
ORPHAN="ground_alley_2"
rm -f "${TILES_DIR}/${ORPHAN}.glb" "${TILES_DIR}/${ORPHAN}.glb.import"
rm -f ${TILES_DIR}/${ORPHAN}_*.jpg ${TILES_DIR}/${ORPHAN}_*.jpg.import
rm -f ${TILES_DIR}/${ORPHAN}_*.png ${TILES_DIR}/${ORPHAN}_*.png.import
```

孤立タイルが0件の場合は「不要ファイルなし」と報告してStep 4へ進む。
削除した場合はファイル数を報告する。

### Step 4: プレビュー画像の確認・生成

`godot/data/tiles/previews/` に各タイルのプレビューPNG（256x256 RGBA透明背景）が必要。
MeshLibrary生成スクリプトがこのディレクトリからプレビューを読み込む。

1. Step 2のエクスポートリストと `godot/data/tiles/previews/*.png` を比較
2. PNGが存在しないタイルがあれば、**全タイルを一括レンダリング**する（統一性のため）

#### プレビューカメラ仕様（必ずこの設定を使うこと）

| パラメータ | 値 | 説明 |
|-----------|-----|------|
| カメラタイプ | Orthographic | 正投影（パースなし） |
| 方位角 (Azimuth) | **35°** | 右前方から撮影 |
| 仰角 (Elevation) | **25°** | やや上から見下ろし |
| カメラ距離 | 10.0 | 正投影なので画角に影響しない |
| ortho_scale | **bbox対角線 × 1.5** | オブジェクトサイズに応じて自動計算 |
| ライト | Sun, energy=3.0 | rotation=(50°, 10°, 25°) |
| 解像度 | 256×256 | RGBA透明背景 |
| エンジン | EEVEE Next | |

カメラ位置の計算式:
```
cam.x = center_x + 10 * sin(35°) * cos(25°)
cam.y = center_y - 10 * cos(35°) * cos(25°)
cam.z = center_z + 10 * sin(25°)
```

#### 一括レンダリングスクリプト

```python
import bpy, math, mathutils, os

PREVIEW_DIR = "/Users/iwasakishungo/Git/github.com/iwasaki1112/RescueForge/godot/data/tiles/previews/"
AZIMUTH   = math.radians(35)
ELEVATION = math.radians(25)
CAM_DIST  = 10.0
FILL_RATIO = 1.5  # ortho_scale = bbox_diagonal * FILL_RATIO

# Collect tiles
tiles = []
for col in bpy.context.scene.collection.children:
    for obj in col.objects:
        if obj.type == 'MESH':
            tiles.append((obj.name, obj.name.replace("-col", "")))

scene = bpy.context.scene
orig_cam = scene.camera
# (save/restore other render settings as needed)

light_data = bpy.data.lights.new("_prev_light", 'SUN')
light_data.energy = 3.0
light_obj = bpy.data.objects.new("_prev_light", light_data)
scene.collection.objects.link(light_obj)
light_obj.rotation_euler = (math.radians(50), math.radians(10), math.radians(25))

scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 256
scene.render.resolution_y = 256
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'

for obj_name, tile_name in sorted(tiles, key=lambda x: x[1]):
    obj = bpy.data.objects[obj_name]
    bb = obj.bound_box
    cx = obj.location.x + sum(v[0] for v in bb) / 8
    cy = obj.location.y + sum(v[1] for v in bb) / 8
    cz = obj.location.z + sum(v[2] for v in bb) / 8
    sx = max(v[0] for v in bb) - min(v[0] for v in bb)
    sy = max(v[1] for v in bb) - min(v[1] for v in bb)
    sz = max(v[2] for v in bb) - min(v[2] for v in bb)
    ortho_scale = math.sqrt(sx*sx + sy*sy + sz*sz) * FILL_RATIO

    cam_data = bpy.data.cameras.new("_prev_cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new("_prev_cam", cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (
        cx + CAM_DIST * math.sin(AZIMUTH) * math.cos(ELEVATION),
        cy - CAM_DIST * math.cos(AZIMUTH) * math.cos(ELEVATION),
        cz + CAM_DIST * math.sin(ELEVATION))
    d = mathutils.Vector((cx - cam_obj.location.x, cy - cam_obj.location.y, cz - cam_obj.location.z))
    cam_obj.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

    scene.camera = cam_obj
    scene.render.filepath = os.path.join(PREVIEW_DIR, f"{tile_name}.png")
    hidden = {}
    for o in scene.objects:
        if o not in (obj, cam_obj, light_obj):
            hidden[o.name] = o.hide_render; o.hide_render = True
    bpy.ops.render.render(write_still=True)
    for n, s in hidden.items():
        o = bpy.data.objects.get(n)
        if o: o.hide_render = s
    bpy.data.objects.remove(cam_obj, do_unlink=True)
    bpy.data.cameras.remove(cam_data)

bpy.data.objects.remove(light_obj, do_unlink=True)
bpy.data.lights.remove(light_data)
scene.camera = orig_cam
# (restore other render settings)
```

**重要**: 新規タイルが追加された場合でも、常に全タイルを一括レンダリングして統一性を保つこと。
プレビュー不足がない場合でも、新規タイルがある場合は全件再レンダリングを推奨。

### Step 5: Godot MeshLibrary再生成

**新規GLBがある場合（Step 3でクリーンアップ対象が変わった or 新しいタイルがある場合）、先にインポートを実行する:**

```bash
cd /Users/iwasakishungo/Git/github.com/iwasaki1112/RescueForge/godot
/Applications/Godot.app/Contents/MacOS/Godot --headless --import
```

> **注意**: 新規GLBファイルは `--import` なしでは「No loader found for resource」エラーになる。
> 既存タイルのみの再エクスポートであれば `--import` はスキップ可。

その後、MeshLibrary生成:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://scripts/editor/generate_tile_library_cli.gd
```

出力で各タイルの `Preview: loaded` を確認する。`Preview: not found` があれば Step 4 に戻る。

### Step 6: 結果報告

以下の情報を表形式でユーザーに報告:

| 項目 | 内容 |
|------|------|
| エクスポートしたタイル数 | N個 |
| 削除した不要ファイル数 | N個 |
| Floor MeshLibrary | N タイル |
| Wall MeshLibrary | N タイル |

最後に「Godotエディタでプロジェクトをリロードしてください」と伝える。

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| Blender MCP接続エラー | Blenderを起動し、MCPアドオンを有効にする |
| エクスポート0件 | Blenderシーンにコレクションがあるか確認 |
| Godot CLIエラー | Godotパスが正しいか確認。`which godot` や `/Applications/Godot.app` |
| UID warningが出る | MeshLibrary再生成で正常。次回エディタリロード時に解消 |
| No loader found for resource | 新規GLBファイル。`--import` を先に実行する |
| Preview: not found | `godot/data/tiles/previews/<tile_name>.png` が未生成。Step 4でレンダリング |

## 関連ファイル

| ファイル | 責務 |
|---------|------|
| `blender/tiles/tile_library.blend` | タイルアセットソース（Blenderファイル） |
| `blender/tiles/export_tiles.py` | Blenderエクスポートスクリプト（参考用） |
| `godot/scenes/tiles/*.glb` | エクスポートされたGLBタイル |
| `godot/data/tiles/tile_library_floor.tres` | 床タイルMeshLibrary |
| `godot/data/tiles/tile_library_wall.tres` | 壁タイルMeshLibrary |
| `godot/data/tiles/previews/*.png` | タイルプレビュー画像（256x256 RGBA透明背景） |
| `godot/scripts/editor/generate_tile_library_cli.gd` | MeshLibrary生成CLI |
