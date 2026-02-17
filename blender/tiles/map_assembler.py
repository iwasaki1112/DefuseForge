"""
map_assembler.py — タイルライブラリからマップを組み立てるヘルパー

tile_library.blend のコレクションをAppendしてグリッド配置する。

使い方 (Blender MCP経由、1コールにまとめて実行):

    import bpy, math, os, sys

    # --- 定数 ---
    FLOOR_TILE_SIZE = 1.0   # 1m Godot = 1.0 BU（床/地面）
    WALL_TILE_SIZE = 2.0    # 2m Godot = 2.0 BU（壁/ドア）
    LIB_PATH = "/Users/.../blender/tiles/tile_library.blend"

    # --- clear_scene ---
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)

    # --- place_tile: ライブラリからコレクションをAppendしてグリッド配置 ---
    def place_tile(tile_name, gx, gy, rotation_deg=0):
        # Append collection from library
        col_path = os.path.join(LIB_PATH, "Collection", tile_name)
        bpy.ops.wm.append(
            filepath=col_path,
            directory=os.path.join(LIB_PATH, "Collection") + os.sep,
            filename=tile_name,
            link=False,
        )
        col = bpy.data.collections.get(tile_name)
        if not col:
            print(f"ERROR: Collection '{tile_name}' not found")
            return

        # グリッド座標 → ワールド座標
        wx, wy = gx * TILE_SIZE, gy * TILE_SIZE
        rot_rad = math.radians(rotation_deg)

        # 命名にグリッド座標を付与 & 移動
        suffix = f"_T{gx}_{gy}"
        for obj in col.objects:
            obj.name = obj.name.split(".")[0] + suffix
            obj.location.x += wx
            obj.location.y += wy
            obj.rotation_euler.z += rot_rad

        # コレクション名もリネーム (重複Append対応)
        col.name = f"{tile_name}_T{gx}_{gy}"
        print(f"Placed '{tile_name}' at grid ({gx},{gy})")

    # --- 使用例 ---
    # place_tile("floor_concrete", 0, 0)
    # place_tile("floor_concrete", 1, 0)
    # place_tile("wall_exterior", 0, 1, rotation_deg=0)    # 北壁
    # place_tile("wall_exterior", 0, 0, rotation_deg=90)   # 東壁 (90°回転)
    # place_tile("door_frame", 1, 1, rotation_deg=0)       # ドア付き壁

タイルライブラリの構成:
  - floor_concrete  : テクスチャ付き床タイル (Ground_Floor-col)
  - wall_exterior   : 外壁タイル (Wall_N-col)
  - wall_interior   : 内壁タイル (Wall_N-col)
  - door_frame      : ドア付き壁 (Wall_DoorL-col, Wall_DoorR-col, Door_N-col)

命名規則 (Godot MapBase互換):
  - Ground_*-col  → 歩行可能エリア (collision layer自動設定)
  - Wall_*-col    → FoW遮蔽壁
  - Door_*-col    → ドア
  - Glass_*-col   → 窓ガラス (vision through)
  - Frame_*-col   → 構造フレーム (no FoW)
"""

import bpy
import math
import os

# === 設定 ===
FLOOR_TILE_SIZE = 1.0   # 1m Godot = 1.0 BU（床/地面タイル）
WALL_TILE_SIZE = 2.0    # 2m Godot = 2.0 BU（壁/ドア/ガラスタイル）
TILE_LIBRARY_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "tile_library.blend",
)

_WALL_PREFIXES = ("wall", "door", "glass", "frame")


def clear_scene() -> None:
    """シーン内の全オブジェクトとコレクションを削除。"""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)

    for block_type in [bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights]:
        for block in block_type:
            if block.users == 0:
                block_type.remove(block)


def place_tile(
    tile_name: str,
    gx: int,
    gy: int,
    rotation_deg: float = 0,
    lib_path: str = None,
) -> None:
    """
    タイルライブラリからコレクションをAppendしてグリッド配置。

    Args:
        tile_name: コレクション名 (例: "floor_concrete", "wall_exterior")
        gx: グリッドX座標
        gy: グリッドY座標
        rotation_deg: Z軸回転 (度数、0=北向き, 90=東向き, 180=南向き, 270=西向き)
        lib_path: ライブラリ.blendパス (省略時はtile_library.blend)
    """
    if lib_path is None:
        lib_path = TILE_LIBRARY_PATH

    bpy.ops.wm.append(
        filepath=os.path.join(lib_path, "Collection", tile_name),
        directory=os.path.join(lib_path, "Collection") + os.sep,
        filename=tile_name,
        link=False,
    )

    col = bpy.data.collections.get(tile_name)
    if not col:
        print(f"ERROR: Collection '{tile_name}' not found in library")
        return

    # タイル名プレフィックスからグリッドサイズを自動判別
    name_lower = tile_name.lower()
    tile_size = WALL_TILE_SIZE if any(name_lower.startswith(p) for p in _WALL_PREFIXES) else FLOOR_TILE_SIZE
    wx, wy = gx * tile_size, gy * tile_size
    rot_rad = math.radians(rotation_deg)

    suffix = f"_T{gx}_{gy}"
    for obj in col.objects:
        base_name = obj.name.split(".")[0]
        obj.name = base_name + suffix
        obj.location.x += wx
        obj.location.y += wy
        obj.rotation_euler.z += rot_rad

    col.name = f"{tile_name}_T{gx}_{gy}"
    print(f"Placed '{tile_name}' at grid ({gx},{gy}) rot={rotation_deg}°")


def create_spawn_points(
    ct_list: list[tuple] = None,
    t_list: list[tuple] = None,
) -> None:
    """
    スポーンポイント用Emptyを作成。

    Args:
        ct_list: CTスポーン座標リスト [(x, y, z_rotation_deg), ...]
        t_list: Tスポーン座標リスト [(x, y, z_rotation_deg), ...]
    """
    if ct_list is None:
        ct_list = []
    if t_list is None:
        t_list = []

    for i, (x, y, rot_z) in enumerate(ct_list):
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=(x, y, 0))
        obj = bpy.context.active_object
        obj.name = f"spawn_ct_{i}"
        obj.rotation_euler[2] = math.radians(rot_z)
        obj.empty_display_size = 0.5

    for i, (x, y, rot_z) in enumerate(t_list):
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=(x, y, 0))
        obj = bpy.context.active_object
        obj.name = f"spawn_t_{i}"
        obj.rotation_euler[2] = math.radians(rot_z)
        obj.empty_display_size = 0.5


def export_gltf(output_path: str) -> None:
    """
    シーン全体をGLTFとしてエクスポート。

    Args:
        output_path: 出力ファイルパス (.gltf)
    """
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLTF_SEPARATE",
        use_active_scene=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"Exported: {output_path}")


def export_tiles(output_dir: str) -> None:
    """
    tile_library.blend の全オブジェクトを個別GLBとしてエクスポート。
    1オブジェクト = 1 GLB。オブジェクト名からGLBファイル名を生成。

    命名変換: "Ground_Wasteland-col" → "ground_wasteland.glb"
              "Ground_WastelandGrass-col" → "ground_wasteland_grass.glb"

    Args:
        output_dir: GLB出力先ディレクトリ
    """
    import re

    results = []
    for col in bpy.data.collections:
        for obj in col.objects:
            if obj.type != "MESH":
                continue

            # Save original state
            orig_loc = obj.location.copy()
            orig_hide = obj.hide_get()
            obj.location = (0, 0, 0)
            obj.hide_set(False)

            # Deselect all, select only this object
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj

            # Generate filename from object name
            # "Ground_Wasteland-col" → "ground_wasteland"
            name = obj.name
            name = re.sub(r"-col$", "", name)  # Remove -col suffix
            # CamelCase → snake_case
            name = re.sub(r"([a-z])([A-Z])", r"\1_\2", name)
            name = name.lower()
            # Remove prefix like "ground_" for the filename
            # Actually keep it for clarity: ground_wasteland, wall_north, etc.
            # But remove the Godot collision prefix pattern
            # "ground_wasteland" is already good
            glb_name = f"{name}.glb"
            filepath = os.path.join(output_dir, glb_name)

            bpy.ops.export_scene.gltf(
                filepath=filepath,
                export_format="GLB",
                use_selection=True,
                export_apply=True,
                export_yup=True,
                export_texcoords=True,
                export_normals=True,
                export_materials="EXPORT",
                export_image_format="AUTO",
            )

            # Restore
            obj.location = orig_loc
            obj.hide_set(orig_hide)

            file_size = os.path.getsize(filepath)
            results.append(f"OK: {glb_name} ({file_size} bytes)")

    for r in results:
        print(r)
    print(f"Exported {len(results)} tiles to {output_dir}")
