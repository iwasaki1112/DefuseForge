# Nakama Server Setup

## 起動方法

```bash
# プロジェクトルートで実行
docker-compose up -d

# ログ確認
docker-compose logs -f nakama
```

## アクセス情報

- **API**: http://localhost:7350
- **Console (Admin)**: http://localhost:7351
  - Username: `admin`
  - Password: `password`

## 停止方法

```bash
docker-compose down

# データも削除する場合
docker-compose down -v
```

## サーバーキー

開発用: `supportrate_dev_key`

## API エンドポイント

### 認証
- `POST /v2/account/authenticate/device` - デバイス認証（ゲスト）
- `POST /v2/account/authenticate/email` - メール認証

### RPC
- `POST /v2/rpc/create_room` - ルーム作成
- `POST /v2/rpc/join_by_code` - ルームコードで参加
- `POST /v2/rpc/list_rooms` - 公開ルーム一覧
- `POST /v2/rpc/join_matchmaking` - ランダムマッチメイキング

## マッチ OpCodes

| OpCode | 説明 |
|--------|------|
| 1 | ゲーム開始要求（ホストのみ） |
| 2 | ゲームイベント（サーバー→クライアント） |
| 10 | プレイヤー位置更新 |
| 11 | プレイヤーアクション |
| 20 | フェーズ変更要求（ホストのみ） |
