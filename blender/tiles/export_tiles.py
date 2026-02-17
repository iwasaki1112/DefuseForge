"""
tile_library.blend の各コレクションを個別GLBとしてエクスポートする。

使い方:
  Blender MCP経由:
    exec(open("blender/tiles/export_tiles.py").read())

  コマンドライン:
    blender tile_library.blend --background --python export_tiles.py

コレクション名 = タイル名 = GLBファイル名（例: floor_concrete → floor_concrete.glb）
複数オブジェクトのコレクション: オブジェクト名(-col除去) = GLBファイル名
出力先: godot/scenes/tiles/
"""

import bpy
import os

# プロジェクトルートを自動検出（.blendファイルの2階層上、またはカレントディレクトリ）
blend_path = bpy.data.filepath
if blend_path:
    PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(blend_path)))
else:
    # MCP経由の場合はカレントディレクトリから推定
    cwd = os.getcwd()
    if os.path.exists(os.path.join(cwd, "godot")):
        PROJECT_ROOT = cwd
    else:
        PROJECT_ROOT = os.path.dirname(os.path.dirname(cwd))

OUTPUT_DIR = os.path.join(PROJECT_ROOT, "godot", "scenes", "tiles")


def _export_glb(filepath):
    """共通GLBエクスポート処理"""
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
    """単一オブジェクトをGLBエクスポート（位置を一時リセット）"""
    orig_loc = obj.location.copy()
    obj.location = (0, 0, 0)

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)

    output_path = os.path.join(OUTPUT_DIR, f"{tile_name}.glb")
    _export_glb(output_path)

    obj.location = orig_loc
    return output_path


def export_tiles():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    scene_collections = list(bpy.context.scene.collection.children)
    if not scene_collections:
        print("ERROR: No collections found in scene")
        return

    exported = 0
    for col in scene_collections:
        objects = list(col.objects)
        if not objects:
            print(f"  SKIP: '{col.name}' (empty)")
            continue

        if len(objects) == 1:
            # 単一オブジェクト → コレクション名でエクスポート
            _export_single_object(objects[0], col.name)
            print(f"  Exported: {col.name}.glb (1 object)")
            exported += 1
        else:
            # 複数オブジェクト → 各オブジェクトを個別エクスポート
            for obj in objects:
                tile_name = obj.name.replace("-col", "")
                _export_single_object(obj, tile_name)
                print(f"  Exported: {tile_name}.glb (from '{col.name}')")
                exported += 1

    print(f"\n=== {exported} tiles exported to {OUTPUT_DIR} ===")


export_tiles()
