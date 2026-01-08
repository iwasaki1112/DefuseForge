#!/bin/bash
# FBX2glTF セットアップスクリプト
# FBXファイルをglTF/GLB形式に変換するツールをダウンロード

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR"

# FBX2glTF バージョン (Godot公式フォーク)
VERSION="0.13.1"

# OS検出
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Darwin)
        if [ "$ARCH" = "arm64" ]; then
            DOWNLOAD_FILE="FBX2glTF-macos-arm64.zip"
            BINARY_NAME="FBX2glTF-macos-arm64"
        else
            DOWNLOAD_FILE="FBX2glTF-macos-x86_64.zip"
            BINARY_NAME="FBX2glTF-macos-x86_64"
        fi
        ;;
    Linux)
        DOWNLOAD_FILE="FBX2glTF-linux-x86_64.zip"
        BINARY_NAME="FBX2glTF-linux-x86_64"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        DOWNLOAD_FILE="FBX2glTF-windows-x86_64.zip"
        BINARY_NAME="FBX2glTF-windows-x86_64.exe"
        ;;
    *)
        echo "Error: Unsupported OS: $OS"
        exit 1
        ;;
esac

DOWNLOAD_URL="https://github.com/godotengine/FBX2glTF/releases/download/v${VERSION}/${DOWNLOAD_FILE}"
OUTPUT_PATH="$TOOLS_DIR/FBX2glTF"

echo "=== FBX2glTF Setup ==="
echo "Version: $VERSION"
echo "OS: $OS ($ARCH)"
echo "Download URL: $DOWNLOAD_URL"
echo ""

# 既存ファイルチェック
if [ -f "$OUTPUT_PATH" ]; then
    CURRENT_VERSION=$("$OUTPUT_PATH" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo "FBX2glTF already exists (version: $CURRENT_VERSION)"
    read -p "Re-download? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Skipped."
        exit 0
    fi
fi

# ダウンロード
echo "Downloading FBX2glTF..."
TEMP_ZIP="$TOOLS_DIR/fbx2gltf_temp.zip"

if command -v curl &> /dev/null; then
    curl -L -o "$TEMP_ZIP" "$DOWNLOAD_URL"
elif command -v wget &> /dev/null; then
    wget -O "$TEMP_ZIP" "$DOWNLOAD_URL"
else
    echo "Error: curl or wget is required"
    exit 1
fi

# 展開
echo "Extracting..."
TEMP_DIR="$TOOLS_DIR/fbx2gltf_temp"
mkdir -p "$TEMP_DIR"
unzip -o "$TEMP_ZIP" -d "$TEMP_DIR"

# バイナリを配置
EXTRACTED_DIR=$(find "$TEMP_DIR" -type d -name "FBX2glTF-*" | head -1)
if [ -n "$EXTRACTED_DIR" ]; then
    mv "$EXTRACTED_DIR/$BINARY_NAME" "$OUTPUT_PATH"
    # ライセンスファイルもコピー
    cp "$EXTRACTED_DIR"/*.txt "$TOOLS_DIR/" 2>/dev/null || true
    cp "$EXTRACTED_DIR"/*.rtf "$TOOLS_DIR/" 2>/dev/null || true
fi

# クリーンアップ
rm -rf "$TEMP_DIR" "$TEMP_ZIP"

# 実行権限付与
chmod +x "$OUTPUT_PATH"

echo ""
echo "=== Setup Complete ==="
echo "FBX2glTF installed at: $OUTPUT_PATH"
"$OUTPUT_PATH" --version
echo ""
echo "Usage:"
echo "  $OUTPUT_PATH -i input.fbx -o output.glb"
echo "  $OUTPUT_PATH -i input.fbx -o output.gltf --gltf-output"
echo ""
echo "For Godot import, set the binary path in:"
echo "  Editor Settings > FileSystem > Import > Blender > FBX2glTF Path"
