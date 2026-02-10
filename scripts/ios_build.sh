#!/bin/bash
# iOS実機ビルド完全自動化スクリプト
# 使用方法: ./scripts/ios_build.sh [--export] [--run]
#   --export: Godotからエクスポート（変更がある場合のみ必要）
#   --run: ビルド後にアプリを自動起動

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_PATH="/opt/homebrew/bin/godot"
XCODE_PROJECT="$PROJECT_ROOT/godot/builds/ios/RescueForge.xcodeproj"
PBXPROJ="$XCODE_PROJECT/project.pbxproj"
INFO_PLIST="$PROJECT_ROOT/godot/builds/ios/RescueForge/RescueForge-Info.plist"

# === 設定 ===
TEAM_ID="NSB57DVW9V"
DEVICE_ID="7C46939D-68A2-58E9-8850-FDA526502428"  # iwasaki (iPhone 12 mini)
BUNDLE_ID="jp.kater.rescue-forge"
SCHEME="RescueForge"
CONFIGURATION="Debug"

# 引数解析
DO_EXPORT=false
DO_RUN=false
for arg in "$@"; do
    case $arg in
        --export) DO_EXPORT=true ;;
        --run) DO_RUN=true ;;
    esac
done

echo "=== iOS実機ビルド自動化 ==="
echo "デバイス: $DEVICE_ID"
echo "Team ID: $TEAM_ID"
echo ""

# 1. Godotエクスポート（オプション）
if $DO_EXPORT; then
    echo "[1/6] Godotプロジェクトをエクスポート中..."
    "$GODOT_PATH" --headless --path "$PROJECT_ROOT/godot" --export-release "iOS" "builds/ios/RescueForge.xcodeproj" 2>&1 | grep -v "^ERROR\|ARCHIVE FAILED" || true
    echo "  完了"
else
    echo "[1/6] エクスポートをスキップ（--exportで有効化）"
fi

# 2. Info.plist修正
echo "[2/6] Info.plistを修正中..."
if [ -f "$INFO_PLIST" ]; then
    python3 -c "
import re
with open('$INFO_PLIST', 'r') as f:
    content = f.read()
content = re.sub(r'(<key>NSCameraUsageDescription</key>\s*<string>)</string>', r'\1This app does not use the camera.</string>', content)
content = re.sub(r'(<key>NSPhotoLibraryUsageDescription</key>\s*<string>)</string>', r'\1This app does not access photos.</string>', content)
content = re.sub(r'(<key>NSMicrophoneUsageDescription</key>\s*<string>)</string>', r'\1This app does not use the microphone.</string>', content)
with open('$INFO_PLIST', 'w') as f:
    f.write(content)
"
    echo "  完了"
fi

# 3. 署名設定を自動修正
echo "[3/6] 署名設定を自動修正中..."
if [ -f "$PBXPROJ" ]; then
    # CODE_SIGN_STYLE を Automatic に変更
    sed -i '' 's/CODE_SIGN_STYLE = "Manual";/CODE_SIGN_STYLE = Automatic;/g' "$PBXPROJ"
    sed -i '' 's/CODE_SIGN_STYLE = Manual;/CODE_SIGN_STYLE = Automatic;/g' "$PBXPROJ"

    # DEVELOPMENT_TEAM を設定
    sed -i '' "s/DEVELOPMENT_TEAM = \"[^\"]*\";/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"
    sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"
    sed -i '' "s/DEVELOPMENT_TEAM = \"\";/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"

    # 空のDEVELOPMENT_TEAMを追加（存在しない場合）
    if ! grep -q "DEVELOPMENT_TEAM = $TEAM_ID" "$PBXPROJ"; then
        sed -i '' "s/CODE_SIGN_STYLE = Automatic;/CODE_SIGN_STYLE = Automatic;\n\t\t\t\tDEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"
    fi
    echo "  完了"
fi

# 4. 既存アプリをアンインストール
echo "[4/6] 既存アプリをアンインストール中..."
xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
echo "  完了"

# 5. ビルド
echo "[5/6] Xcodeビルド中..."
xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    build 2>&1 | grep -E "^(Build |Compiling|Linking|\*\*|error:|warning:)" || true

# ビルド成果物のパスを取得（Debug用、Index.noindexを除外）
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
APP_PATH=$(find "$DERIVED_DATA" -path "*/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app" -not -path "*/Index.noindex/*" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "  エラー: ビルド成果物が見つかりません"
    exit 1
fi
echo "  完了: $APP_PATH"

# 6. インストール＆起動
echo "[6/6] 実機にインストール中..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
echo "  インストール完了"

if $DO_RUN; then
    echo ""
    echo "アプリを起動中..."
    xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || true
    echo "  起動完了"
fi

echo ""
echo "=== 完了 ==="
echo ""
echo "使用方法:"
echo "  ./scripts/ios_build.sh          # ビルド＆インストールのみ"
echo "  ./scripts/ios_build.sh --run    # ビルド＆インストール＆起動"
echo "  ./scripts/ios_build.sh --export # Godotエクスポートから実行"
echo "  ./scripts/ios_build.sh --export --run # フルビルド＆起動"
