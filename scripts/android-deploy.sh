#!/bin/bash
# Android Build & Deploy Script
# Usage: ./scripts/android-deploy.sh

set -e

APK_PATH="godot/builds/android/godot.apk"
BUILD_DIR="godot/builds/android"

# ビルドディレクトリ作成
mkdir -p "$BUILD_DIR"

# Godotでビルド
echo "Building Android APK..."
godot --headless --path godot --export-debug "Android" "builds/android/godot.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "Error: Build failed. APK file not found at $APK_PATH"
    exit 1
fi

echo ""
echo "Build complete: $APK_PATH"
echo ""

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "Error: adb not found"
    echo "Install Android SDK Platform Tools or add adb to PATH"
    exit 1
fi

# Check if device is connected
DEVICE_COUNT=$(adb devices | grep -v "^List" | grep -v "^$" | wc -l | tr -d ' ')
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "Error: No Android device connected"
    echo "Connect your device via USB and enable USB debugging"
    exit 1
fi

echo "Deploying $APK_PATH to Android device via USB..."
echo "Connected devices:"
adb devices
echo ""

adb install -r "$APK_PATH"

echo ""
echo "Done! Starting app..."
# Get package name from APK and launch it
PACKAGE_NAME=$(adb shell pm list packages | grep -i rescueforge | head -1 | cut -d: -f2 | tr -d '\r')
if [ -n "$PACKAGE_NAME" ]; then
    adb shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1
fi
