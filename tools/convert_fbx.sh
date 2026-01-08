#!/bin/bash
# FBX to glTF/GLB 変換スクリプト
# Usage: ./convert_fbx.sh input.fbx [output.glb] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FBX2GLTF="$SCRIPT_DIR/FBX2glTF"

# FBX2glTFが存在しない場合はセットアップを促す
if [ ! -f "$FBX2GLTF" ]; then
    echo "Error: FBX2glTF not found at: $FBX2GLTF"
    echo "Run: ./tools/setup_fbx2gltf.sh"
    exit 1
fi

# ヘルプ表示
show_help() {
    echo "FBX to glTF/GLB Converter"
    echo ""
    echo "Usage: $0 <input.fbx> [output] [options]"
    echo ""
    echo "Arguments:"
    echo "  input.fbx    Input FBX file"
    echo "  output       Output file (default: input name with .glb extension)"
    echo ""
    echo "Options:"
    echo "  --gltf       Output as .gltf instead of .glb"
    echo "  --draco      Enable Draco mesh compression"
    echo "  --no-flip-v  Don't flip V texture coordinates"
    echo "  --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 character.fbx"
    echo "  $0 character.fbx character_exported.glb"
    echo "  $0 character.fbx --gltf --draco"
    echo ""
    echo "Batch conversion:"
    echo "  find . -name '*.fbx' -exec $0 {} \\;"
}

# 引数がない場合
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# 引数パース
INPUT_FILE=""
OUTPUT_FILE=""
EXTRA_ARGS=""
USE_GLTF=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --gltf)
            USE_GLTF=true
            EXTRA_ARGS="$EXTRA_ARGS --gltf-output"
            shift
            ;;
        --draco)
            EXTRA_ARGS="$EXTRA_ARGS --draco"
            shift
            ;;
        --no-flip-v)
            EXTRA_ARGS="$EXTRA_ARGS --no-flip-v"
            shift
            ;;
        -*)
            # その他のオプションはそのまま渡す
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
        *)
            if [ -z "$INPUT_FILE" ]; then
                INPUT_FILE="$1"
            elif [ -z "$OUTPUT_FILE" ]; then
                OUTPUT_FILE="$1"
            fi
            shift
            ;;
    esac
done

# 入力ファイルチェック
if [ -z "$INPUT_FILE" ]; then
    echo "Error: No input file specified"
    show_help
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# 出力ファイル名の決定
if [ -z "$OUTPUT_FILE" ]; then
    BASE_NAME="${INPUT_FILE%.*}"
    if [ "$USE_GLTF" = true ]; then
        OUTPUT_FILE="${BASE_NAME}.gltf"
    else
        OUTPUT_FILE="${BASE_NAME}.glb"
    fi
fi

echo "=== FBX to glTF/GLB Conversion ==="
echo "Input:  $INPUT_FILE"
echo "Output: $OUTPUT_FILE"
echo ""

# 変換実行
"$FBX2GLTF" -i "$INPUT_FILE" -o "$OUTPUT_FILE" $EXTRA_ARGS

echo ""
echo "=== Conversion Complete ==="
echo "Output: $OUTPUT_FILE"

# ファイルサイズ表示
if [ -f "$OUTPUT_FILE" ]; then
    SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
    echo "Size: $SIZE"
fi
