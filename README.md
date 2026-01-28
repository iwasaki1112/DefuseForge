# RescueForge

CS1.6 meets Door Kickers 2 - トップダウンタクティカルシューター

## 概要

RescueForgeは、カウンターストライクのような戦闘システムと、Door Kickersのような戦術的な計画・実行システムを組み合わせたトップダウン型のタクティカルシューターです。プレイヤーはキャラクターにパス（移動経路）やアクション（視線、クリアリング、アイテム使用等）を指示し、リアルタイムで実行される作戦を指揮します。

## 主な機能

- **戦術的なパス描画**: モバイル・PC両対応の直感的なインターフェースで移動経路を描画。
- **多彩なアクションマーカー**: 視線（Vision）、走り（Run）、クリアリング（Clear）、グレネード・スモーク投擲、ドア操作、待機などの詳細な指示が可能。
- **モバイル最適化**: タッチ操作によるパン、ズーム、パス編集をスムーズに行えるよう最適化。
- **マルチプレイ対応**: ロビーシステムとマルチプレイヤー同期機能を搭載。
- **高度なグラフィックス**: 影の最適化やMSAA/FXAAの切り替えなど、モバイルでのパフォーマンスを重視した描画設定。

## 開発環境

- **Engine**: Godot 4.5 (Mobile renderer)
- **Language**: GDScript
- **Target Platforms**: Android, iOS, PC

## プロジェクト構造

- `godot/`: Godotプロジェクト本体
    - `scripts/`: GDScriptソースコード
    - `scenes/`: シーンファイル
    - `assets/`: 3Dモデル、テクスチャ、音声、フォント
    - `shaders/`: カスタムシェーダー
- `docs/`: ドキュメント
    - `ai/`: AI用共通指示書
    - `godot/api/`: GDScript APIリファレンス
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
