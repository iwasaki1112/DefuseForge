#!/bin/bash

# Blenderマップエクスポートスクリプト
# 使用方法: ./scripts/export_blender_map.sh [blendファイルパス]
#
# blendファイルを指定しない場合、デフォルトの map.blend を使用

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$ROOT_DIR/SupportRateGame"
OUTPUT_DIR="$PROJECT_DIR/resources/maps"

# Blenderパス
BLENDER="/Applications/Blender.app/Contents/MacOS/Blender"

# デフォルトのblendファイル
DEFAULT_BLEND="$OUTPUT_DIR/map.blend"
BLEND_FILE="${1:-$DEFAULT_BLEND}"

# 出力ファイル
WALL_OUTPUT="$OUTPUT_DIR/wall.glb"

echo "=== Blender Map Export ==="

# Blenderが存在するか確認
if [ ! -f "$BLENDER" ]; then
    echo "ERROR: Blender not found at $BLENDER"
    exit 1
fi

# blendファイルが存在するか確認
if [ ! -f "$BLEND_FILE" ]; then
    echo "ERROR: Blend file not found: $BLEND_FILE"
    echo ""
    echo "最初にBlenderでマップを作成し、以下に保存してください:"
    echo "  $DEFAULT_BLEND"
    echo ""
    echo "または、パスを指定して実行:"
    echo "  ./scripts/export_blender_map.sh /path/to/your/map.blend"
    exit 1
fi

echo "Input:  $BLEND_FILE"
echo "Output: $WALL_OUTPUT"
echo ""

# エクスポート実行
"$BLENDER" "$BLEND_FILE" --background --python-expr "
import bpy

output_path = '$WALL_OUTPUT'
print(f'Exporting to: {output_path}')

# GLBエクスポート（トランスフォームを保持）
bpy.ops.export_scene.gltf(
    filepath=output_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False,
    export_materials='EXPORT'
)
print('Export complete!')
"

# エクスポート成功確認
if [ $? -ne 0 ]; then
    echo "ERROR: Export failed"
    exit 1
fi

# Godotのインポートキャッシュをクリア
echo ""
echo "Clearing Godot import cache..."
rm -f "$PROJECT_DIR/.godot/imported/"*wall* 2>/dev/null
rm -f "$OUTPUT_DIR/wall.glb.import" 2>/dev/null

echo ""
echo "=== Export Complete ==="
echo "Godotでプロジェクトを再起動すると反映されます"
