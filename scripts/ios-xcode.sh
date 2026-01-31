#!/bin/bash
# iOS Build & Open in Xcode Script
# Usage: ./scripts/ios-xcode.sh

set -e

XCODE_PROJECT="godot/builds/ios/godot.xcodeproj"
BUILD_DIR="godot/builds/ios"

# ビルドディレクトリ作成
mkdir -p "$BUILD_DIR"

# GodotでXcodeプロジェクトをエクスポート
echo "Exporting iOS Xcode project..."
godot --headless --path godot --export-debug "iOS" "builds/ios/godot.xcodeproj"

if [ ! -d "$XCODE_PROJECT" ]; then
    echo "Error: Export failed. Xcode project not found at $XCODE_PROJECT"
    exit 1
fi

echo ""
echo "Export complete: $XCODE_PROJECT"
echo ""

# Xcodeで開く
echo "Opening Xcode..."
open "$XCODE_PROJECT"

echo ""
echo "Done! Xcode should now be open with the project."
