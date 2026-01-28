# WebSocket Relay Server

RescueForge用のWebSocketリレーサーバー。Cloud Runにデプロイして使用。

## 概要

- **言語**: Go
- **プロトコル**: WebSocket
- **機能**: ルーム作成・参加、メッセージリレー

## ローカル開発

```bash
# 起動
go run .

# ビルド確認
go build -o /dev/null .
```

ローカルURL: `ws://localhost:8080/ws`

Godot側で `network_constants.gd` の `USE_LOCAL_RELAY = true` に設定。

## GCP Cloud Run デプロイ

### 前提条件

- gcloud CLI がインストール・認証済み
- プロジェクト: `rescueforge`

### デプロイコマンド

```bash
gcloud run deploy rescueforge-relay \
  --source . \
  --platform managed \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --session-affinity \
  --min-instances=1
```

### 重要なオプション

| オプション | 説明 | 必須 |
|-----------|------|------|
| `--session-affinity` | WebSocket用にセッション維持 | Yes |
| `--min-instances=1` | コールドスタート回避 | Yes |
| `--max-instances=3` | 最大インスタンス数 | No |

### URL

- **本番WebSocket**: `wss://rescueforge-relay-344342786567.asia-northeast1.run.app/ws`
- **ヘルスチェック**: `https://rescueforge-relay-344342786567.asia-northeast1.run.app/health`

## 運用コマンド

```bash
# ヘルスチェック
curl https://rescueforge-relay-344342786567.asia-northeast1.run.app/health

# ログ確認
gcloud run services logs read rescueforge-relay --region asia-northeast1 --limit 30

# サービス情報
gcloud run services describe rescueforge-relay --region asia-northeast1

# リビジョン一覧
gcloud run revisions list --service rescueforge-relay --region asia-northeast1
```

## トラブルシューティング

### 接続が失敗する

1. ログを確認
2. サーバーを再デプロイ
3. `min-instances=1` を確認（コールドスタート回避）

### WebSocket 101接続成功だがメッセージが処理されない

デッドロックの可能性。サーバー再デプロイで状態リセット。

## アーキテクチャ

```
┌─────────┐     ┌─────────────────┐     ┌─────────┐
│ Player1 │────▶│   Cloud Run     │◀────│ Player2 │
│ (Host)  │◀────│ WebSocket Relay │────▶│(Client) │
└─────────┘     └─────────────────┘     └─────────┘
```

## ファイル構成

| ファイル | 説明 |
|---------|------|
| `main.go` | エントリポイント、WebSocketハンドラ |
| `hub.go` | クライアント・ルーム管理 |
| `room.go` | ルーム構造体 |
| `client.go` | WebSocket接続管理 |
| `messages.go` | メッセージ定義 |
| `Dockerfile` | Cloud Run用ビルド設定 |
