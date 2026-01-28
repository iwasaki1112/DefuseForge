#!/bin/bash
# iOS USB Deploy Script
# Usage: ./scripts/ios-deploy.sh

set -e

IPA_PATH="godot/builds/ios/godot.ipa"

if [ ! -f "$IPA_PATH" ]; then
    echo "Error: IPA file not found at $IPA_PATH"
    echo "Run 'godot --headless --path godot --export-debug \"iOS\" builds/ios/godot.xcodeproj' first"
    exit 1
fi

echo "Deploying $IPA_PATH to iPhone via USB..."
echo "Make sure your iPhone is connected via USB cable."
echo ""

xcrun ios-deploy -b "$IPA_PATH" --no-wifi

echo ""
echo "Done!"
