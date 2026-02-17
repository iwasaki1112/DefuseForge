#!/bin/bash
# iOS Build & Deploy Script (ワンコマンドでエクスポート→デプロイ)
# Godot 4.6の--export-debugは内部でarchive+IPA生成まで行うため、
# 別途xcodebuildを実行する必要はない
#
# Usage: ./scripts/ios-deploy.sh [--no-export] [--no-run]
#   --no-export: Godotエクスポートをスキップ（IPAが既にある場合）
#   --no-run: インストール後にアプリを起動しない

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_PATH="/opt/homebrew/bin/godot"
BUILD_DIR="$PROJECT_ROOT/godot/builds/ios"
IPA_PATH="$BUILD_DIR/RescueForge.ipa"

# === 設定 ===
DEVICE_ID="7C46939D-68A2-58E9-8850-FDA526502428"
BUNDLE_ID="jp.kater.rescue-forge"

# 引数解析
DO_EXPORT=true
DO_RUN=true
for arg in "$@"; do
    case $arg in
        --no-export) DO_EXPORT=false ;;
        --no-run) DO_RUN=false ;;
    esac
done

echo "=== iOS Build & Deploy ==="
echo "デバイス: $DEVICE_ID"
echo ""

# 1. Godotエクスポート（archive + IPA生成まで自動実行される）
if $DO_EXPORT; then
    echo "[1/3] Godotエクスポート中（archive + IPA生成）..."
    mkdir -p "$BUILD_DIR"
    "$GODOT_PATH" --headless --path "$PROJECT_ROOT/godot" --export-debug "iOS" "builds/ios/RescueForge.xcodeproj" 2>&1 | grep -v "^ERROR\|ARCHIVE FAILED" || true

    if [ ! -f "$IPA_PATH" ]; then
        echo "  エラー: エクスポート失敗。IPAが見つかりません: $IPA_PATH"
        exit 1
    fi
    echo "  完了: $IPA_PATH ($(du -h "$IPA_PATH" | cut -f1))"
else
    echo "[1/3] エクスポートをスキップ（--no-export）"
    if [ ! -f "$IPA_PATH" ]; then
        echo "  エラー: IPAが見つかりません: $IPA_PATH"
        echo "  --no-export を外して再実行してください"
        exit 1
    fi
    echo "  既存IPA: $IPA_PATH ($(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$IPA_PATH"))"
fi

# 2. 既存アプリをアンインストール
echo "[2/3] 既存アプリをアンインストール中..."
xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
echo "  完了"

# 3. IPAをインストール＆起動
echo "[3/3] IPAを実機にインストール中..."
xcrun devicectl device install app --device "$DEVICE_ID" "$IPA_PATH"
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
echo "  ./scripts/ios-deploy.sh              # フルビルド＆デプロイ＆起動"
echo "  ./scripts/ios-deploy.sh --no-export  # エクスポートスキップ（既存IPAをデプロイ）"
echo "  ./scripts/ios-deploy.sh --no-run     # インストールのみ（起動なし）"
