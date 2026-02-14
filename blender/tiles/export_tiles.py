"""
tile_library.blend の各コレクションを個別GLBとしてエクスポートする。

使い方:
  Blender MCP経由:
    exec(open("blender/tiles/export_tiles.py").read())

  コマンドライン:
    blender tile_library.blend --background --python export_tiles.py

コレクション名 = タイル名 = GLBファイル名（例: floor_concrete → floor_concrete.glb）
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


def export_tiles():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    scene_collections = list(bpy.context.scene.collection.children)
    if not scene_collections:
        print("ERROR: No collections found in scene")
        return

    exported = 0
    for col in scene_collections:
        if not col.objects:
            print(f"  SKIP: '{col.name}' (empty)")
            continue

        tile_name = col.name
        output_path = os.path.join(OUTPUT_DIR, f"{tile_name}.glb")

        # 全選択解除 → コレクション内のオブジェクトだけ選択
        bpy.ops.object.select_all(action='DESELECT')
        for obj in col.objects:
            obj.select_set(True)

        # 選択オブジェクトをGLBエクスポート
        bpy.ops.export_scene.gltf(
            filepath=output_path,
            export_format='GLB',
            use_selection=True,
            export_apply=True,
            export_texcoords=True,
            export_normals=True,
            export_materials='EXPORT',
            export_image_format='AUTO',
            export_yup=True,
        )

        print(f"  Exported: {tile_name}.glb ({len(col.objects)} objects)")
        exported += 1

    print(f"\n=== {exported} tiles exported to {OUTPUT_DIR} ===")


export_tiles()
