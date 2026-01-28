# Build stage
FROM golang:1.22-alpine AS builder

WORKDIR /app

# 依存関係をコピーしてダウンロード
COPY go.mod go.sum* ./
RUN go mod download

# ソースコードをコピーしてビルド
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o relay-server .

# Runtime stage
FROM alpine:latest

# CA証明書（HTTPS用）
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# ビルド済みバイナリをコピー
COPY --from=builder /app/relay-server .

# Cloud Runはポート8080を使用
EXPOSE 8080

CMD ["./relay-server"]
