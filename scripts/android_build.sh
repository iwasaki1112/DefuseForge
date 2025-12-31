#!/bin/bash
# Android APKビルド自動化スクリプト
# 使用方法: ./scripts/android_build.sh [--install]

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_PATH="/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot"
APK_OUTPUT="$PROJECT_ROOT/SupportRateGame/builds/android/SupportRateGame.apk"
ANDROID_SDK_ROOT="/opt/homebrew/share/android-commandlinetools"

echo "=== Android APKビルドスクリプト ==="

# Android SDK環境変数を設定
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"

# ビルドディレクトリを作成
mkdir -p "$PROJECT_ROOT/SupportRateGame/builds/android"

# APKをエクスポート
echo "1. APKをエクスポート中..."
"$GODOT_PATH" --headless --path "$PROJECT_ROOT/SupportRateGame" --export-debug "Android" "builds/android/SupportRateGame.apk"

if [ -f "$APK_OUTPUT" ]; then
    echo "   エクスポート完了: $APK_OUTPUT"
    ls -lh "$APK_OUTPUT"
else
    echo "   エラー: APKの作成に失敗しました"
    exit 1
fi

# インストールオプション
if [[ "$1" == "--install" ]]; then
    echo ""
    echo "2. デバイスを確認中..."

    # adbサーバーを起動
    adb start-server 2>/dev/null || true

    # 接続デバイスを確認
    DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l | tr -d ' ')

    if [ "$DEVICES" -eq "0" ]; then
        echo "   警告: Androidデバイスが接続されていません"
        echo "   USBデバッグを有効にしてデバイスを接続してください"
        echo ""
        echo "   APKを手動でインストールする場合:"
        echo "   adb install $APK_OUTPUT"
    else
        echo "   デバイスが見つかりました ($DEVICES 台)"
        echo ""
        echo "3. APKをインストール中..."
        adb install -r "$APK_OUTPUT"
        echo "   インストール完了!"
    fi
fi

echo ""
echo "=== 完了 ==="
echo "APKファイル: $APK_OUTPUT"
echo ""
echo "手動インストール: adb install $APK_OUTPUT"
echo "Finderで開く: open $(dirname $APK_OUTPUT)"
