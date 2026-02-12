# RescueForge

CS1.6スタイルのモバイルTPS タクティカルシューター

## 概要

RescueForgeは、カウンターストライクのような対テロ戦闘をモバイル向けTPSで実現するタクティカルシューターです。ツインスティック操作（移動+エイム）でキャラクターを直接操作し、自動戦闘システムが敵を検知・射撃します。

## 主な機能

- **TPS直接操作**: ツインスティック（左:移動、右:エイム）によるリアルタイム操作。自動敵検知・射撃システム搭載。
- **グレネード・ドアキック**: グレネード/スモーク投擲、ドアキックによる戦術的なクリアリング。
- **モバイル最適化**: タッチ操作に最適化されたUI・カメラ制御。
- **マルチプレイ対応**: WebSocketリレーサーバーによるオンラインマルチプレイヤー。
- **人質救出**: CT側プレイヤーによる人質交渉・救出ミッション。

## 開発環境

- **Engine**: Godot 4.6 (Mobile renderer)
- **Language**: GDScript
- **Target Platforms**: Android, iOS, PC

## プロジェクト構造

- `godot/`: Godotプロジェクト本体
    - `scripts/`: GDScriptソースコード
    - `scenes/`: シーンファイル
    - `assets/`: 3Dモデル、テクスチャ、音声、フォント
    - `shaders/`: カスタムシェーダー
- `server/relay/`: WebSocketリレーサーバー（Go）
- `docs/`: ドキュメント
    - `ai/`: AI用共通指示書
    - `godot/api/`: GDScript APIリファレンス
- `blender/`: マップ/アセット制作関連
- `scripts/`: ビルド・デプロイ用スクリプト

## ビルドとデプロイ

### Android

APKのビルドとインストールを自動化するスクリプトが用意されています。

```bash
# ビルドのみ
./scripts/android_build.sh

# ビルドして接続されたデバイスにインストール
./scripts/android_build.sh --install

# USB経由で既存のAPKをデプロイ
./scripts/android-deploy.sh
```

### iOS

iOSビルド用のスクリプトも用意されています（macOS環境が必要）。

```bash
./scripts/ios_build.sh
```

## ドキュメント

詳細なクラスリファレンスは以下を参照してください。

- [API Reference](docs/godot/api/README.md)
