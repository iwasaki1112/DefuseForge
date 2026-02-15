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

### Step 4: Godot MeshLibrary再生成

```bash
cd /Users/iwasakishungo/Git/github.com/iwasaki1112/RescueForge/godot
/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://scripts/editor/generate_tile_library_cli.gd
```

出力からFloor/Wallタイル数を確認する。

### Step 5: 結果報告

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

## 関連ファイル

| ファイル | 責務 |
|---------|------|
| `blender/tiles/tile_library.blend` | タイルアセットソース（Blenderファイル） |
| `blender/tiles/export_tiles.py` | Blenderエクスポートスクリプト（参考用） |
| `godot/scenes/tiles/*.glb` | エクスポートされたGLBタイル |
| `godot/data/tiles/tile_library_floor.tres` | 床タイルMeshLibrary |
| `godot/data/tiles/tile_library_wall.tres` | 壁タイルMeshLibrary |
| `godot/scripts/editor/generate_tile_library_cli.gd` | MeshLibrary生成CLI |
