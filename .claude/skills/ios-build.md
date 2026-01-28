# iOS Build Skill

iPhoneにゲームをビルド＆インストールする。Xcodeを開く必要なく完全自動化。

## 概要

GodotプロジェクトをiOS向けにエクスポートし、ユーザーのiPhone（iwasaki）に自動的にインストール＆起動する。

## ターゲットデバイス

- **デバイス名:** iwasaki (iPhone 12 mini)
- **デバイスID:** 7C46939D-68A2-58E9-8850-FDA526502428

## 使用方法

### GDScript変更後（エクスポートが必要な場合）

```bash
./scripts/ios_build.sh --export --run
```

### ビルドのみ（エクスポート不要な場合）

```bash
./scripts/ios_build.sh --run
```

### インストールのみ（起動しない）

```bash
./scripts/ios_build.sh --export
```

## 処理内容

スクリプト `scripts/ios_build.sh` は以下を自動で行う:

1. **Godotエクスポート** (--export指定時)
   - `godot --headless --export-release "iOS"`
   - Xcodeプロジェクトと.pckファイルを生成

2. **Info.plist修正**
   - プライバシー説明（カメラ、マイク、フォトライブラリ）を自動設定

3. **署名設定修正**
   - CODE_SIGN_STYLE を Automatic に変更
   - DEVELOPMENT_TEAM を NSB57DVW9V に設定

4. **既存アプリのアンインストール**
   - 古いバージョンを削除して競合を防止

5. **Xcodeビルド**
   - `xcodebuild` でDebugビルドを実行

6. **インストール＆起動** (--run指定時)
   - `xcrun devicectl` でインストールと起動

## 設定変更

デバイスを変更する場合は `scripts/ios_build.sh` の以下を編集:

```bash
DEVICE_ID="7C46939D-68A2-58E9-8850-FDA526502428"  # iwasaki (iPhone 12 mini)
```

利用可能なデバイス一覧を確認:

```bash
xcrun devicectl list devices
```

## トラブルシューティング

### デバイスが見つからない

```bash
xcrun devicectl list devices
```

でデバイスが `connected` または `available (paired)` であることを確認。

### プロビジョニングエラー

Xcodeを一度開いて、Signing & CapabilitiesでTeamを選択し、手動で一度ビルドする。その後はスクリプトで自動化可能。

### ビルド成果物が見つからない

Xcode DerivedDataをクリア:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/RescueForge-*
```

## 関連ファイル

- `scripts/ios_build.sh` - ビルドスクリプト
- `godot/export_presets.cfg` - Godotエクスポート設定
- `godot/builds/ios/` - 生成されたXcodeプロジェクト

## 重要な注意事項

### DirAccessの制限

iOSエクスポートでは `DirAccess` が `res://` パス内で動作しない。以下のレジストリは静的ファイルリストを使用するように修正済み:

- `scripts/registries/map_registry.gd`
- `scripts/registries/character_registry.gd`
- `scripts/registries/weapon_registry.gd`

新しいマップ、キャラクター、武器を追加した場合は、対応するレジストリの `PRESET_FILES` 配列にパスを追加すること。
