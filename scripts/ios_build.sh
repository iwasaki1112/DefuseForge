#!/bin/bash
# iOS実機ビルド自動化スクリプト
# 使用方法: ./scripts/ios_build.sh [--export]

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_PATH="/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot"
XCODE_PROJECT="$PROJECT_ROOT/SupportRateGame/builds/ios/SupportRateGame.xcodeproj"
PBXPROJ="$XCODE_PROJECT/project.pbxproj"
TEAM_ID="NSB57DVW9V"
DEVICE_ID="00008101-000958903C46001E"
DEVICE_NAME="iwasaki"

echo "=== iOS実機ビルドスクリプト ==="

# Godotエクスポートオプション
if [[ "$1" == "--export" ]]; then
    echo "1. Godotプロジェクトをエクスポート中..."
    "$GODOT_PATH" --headless --path "$PROJECT_ROOT/SupportRateGame" --export-debug "iOS" "builds/ios/SupportRateGame.xcodeproj"
    echo "   エクスポート完了"
fi

# 署名設定を自動的に修正
echo "2. 署名設定を自動修正中..."
if [ -f "$PBXPROJ" ]; then
    # CODE_SIGN_STYLE を Automatic に変更（クォート有無両方に対応）
    sed -i '' 's/CODE_SIGN_STYLE = "Manual";/CODE_SIGN_STYLE = Automatic;/g' "$PBXPROJ"
    sed -i '' 's/CODE_SIGN_STYLE = Manual;/CODE_SIGN_STYLE = Automatic;/g' "$PBXPROJ"

    # DEVELOPMENT_TEAM を正しいTeam IDに置換（既存値も含む）
    sed -i '' "s/DEVELOPMENT_TEAM = \"[^\"]*\";/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"
    sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"

    echo "   署名設定を修正しました (Automatic signing有効化, Team ID: $TEAM_ID)"
else
    echo "   エラー: project.pbxprojが見つかりません"
    exit 1
fi

# 実機の接続確認
echo "3. 実機の接続を確認中..."
if xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE_NAME"; then
    echo "   デバイス '$DEVICE_NAME' が接続されています"
else
    echo "   警告: デバイス '$DEVICE_NAME' が見つかりません"
    echo "   利用可能なデバイス:"
    xcrun devicectl list devices 2>/dev/null | grep "available"
fi

# ビルド
echo "4. Xcodeビルド中..."
xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "SupportRateGame" \
    -configuration Debug \
    -destination "id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    build 2>&1 | xcbeautify 2>/dev/null || xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "SupportRateGame" \
    -configuration Debug \
    -destination "id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    build

echo "5. 実機にインストール中..."
# ビルド成果物のパスを取得
BUILD_DIR=$(xcodebuild -project "$XCODE_PROJECT" -scheme "SupportRateGame" -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
APP_PATH="$BUILD_DIR/SupportRateGame.app"

if [ -d "$APP_PATH" ]; then
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>/dev/null || \
    ios-deploy --bundle "$APP_PATH" --id "$DEVICE_ID" 2>/dev/null || \
    echo "   手動でXcodeから実行してください"
else
    echo "   ビルド成果物が見つかりません: $APP_PATH"
    echo "   Xcodeから直接実行することをお勧めします"
fi

echo ""
echo "=== 完了 ==="
echo "Xcodeを開く場合: open \"$XCODE_PROJECT\""
