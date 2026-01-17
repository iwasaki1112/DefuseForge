# Blender内で実行するエクスポートスクリプト
# 使い方:
#   1. Blenderでこのスクリプトを開く (Scripting タブ)
#   2. 「Run Script」ボタンをクリック
#
# または、Blenderのテキストエディタに貼り付けて実行

import bpy
import os

# 出力先パス（プロジェクトに合わせて変更）
OUTPUT_PATH = "/Users/iwasakishungo/Git/github.com/iwasaki1112/3d-game/godot/resources/maps/wall.glb"

# GLBエクスポート
bpy.ops.export_scene.gltf(
    filepath=OUTPUT_PATH,
    export_format='GLB',
    use_selection=False,
    export_apply=False,  # トランスフォームを保持
    export_materials='EXPORT'
)

print(f"✓ Exported to: {OUTPUT_PATH}")
print("Godotでプロジェクトを再起動すると反映されます")
