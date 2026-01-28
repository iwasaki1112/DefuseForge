#!/bin/bash
# iOS Build & Deploy Script
# Usage: ./scripts/ios-deploy.sh

set -e

IPA_PATH="godot/builds/ios/godot.ipa"
BUILD_DIR="godot/builds/ios"

# ビルドディレクトリ作成
mkdir -p "$BUILD_DIR"

# Godotでビルド
echo "Building iOS IPA..."
godot --headless --path godot --export-debug "iOS" "builds/ios/godot.ipa"

if [ ! -f "$IPA_PATH" ]; then
    echo "Error: Build failed. IPA file not found at $IPA_PATH"
    exit 1
fi

echo ""
echo "Build complete: $IPA_PATH"
echo ""

# デプロイ
echo "Deploying to iPhone via USB..."
echo "Make sure your iPhone is connected via USB cable."
echo ""

xcrun ios-deploy -b "$IPA_PATH" --no-wifi

echo ""
echo "Done!"
