# iOS Build & Deploy

iPhoneへのビルドとデプロイを実行する。

## 手順

1. **エクスポート設定の確認**
   - `godot/export_presets.cfg` の `targeted_device_family` が `0` (iPhone+iPad両対応) であることを確認
   - `1` はiPad専用と解釈されるため、iPhoneにインストールできない

2. **ビルドディレクトリの準備**
   ```bash
   mkdir -p godot/builds/ios
   ```

3. **Godotエクスポート実行**
   ```bash
   godot --headless --path godot --export-debug "iOS" builds/ios/godot.xcodeproj
   ```
   - タイムアウト: 300秒
   - 出力: `godot/builds/ios/godot.ipa`

4. **iPhoneへのインストール**
   ```bash
   xcrun ios-deploy -b godot/builds/ios/godot.ipa
   ```
   - WiFi経由でも接続可能
   - タイムアウト: 120秒

## トラブルシューティング

### エラー: "This application does not support this kind of device"
- **原因**: `targeted_device_family` の設定が間違っている
- **解決**: `export_presets.cfg` で `application/targeted_device_family=0` に設定

### エラー: プロビジョニングプロファイルが見つからない
- **原因**: プロファイルがインストールされていない
- **解決**: Xcodeでプロビジョニングプロファイルを確認・更新

## 前提条件
- Xcode がインストールされていること
- `ios-deploy` がインストールされていること (`brew install ios-deploy`)
- 有効なプロビジョニングプロファイルが設定されていること
- iPhoneがMacと接続されていること（USB or WiFi）
