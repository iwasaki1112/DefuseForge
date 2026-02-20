package main

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	// 書き込みタイムアウト
	writeWait = 10 * time.Second
	// Pong受信タイムアウト
	pongWait = 60 * time.Second
	// Ping送信間隔
	pingPeriod = (pongWait * 9) / 10
	// 最大メッセージサイズ
	maxMessageSize = 64 * 1024
)

// Client WebSocket接続を管理
type Client struct {
	hub      *Hub
	conn     *websocket.Conn
	send     chan []byte
	room     *Room
	peerID   int
	name     string
	gameMode string // ゲームモード（"coop" / "multiplayer"）
	closed   bool   // チャネルがcloseされたかどうか
	mu       sync.RWMutex
}

// NewClient 新しいクライアントを作成
func NewClient(hub *Hub, conn *websocket.Conn) *Client {
	return &Client{
		hub:  hub,
		conn: conn,
		send: make(chan []byte, 256),
	}
}

// GetPeerID ピアIDを取得
func (c *Client) GetPeerID() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.peerID
}

// SetPeerID ピアIDを設定
func (c *Client) SetPeerID(id int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.peerID = id
}

// GetName 名前を取得
func (c *Client) GetName() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.name
}

// SetName 名前を設定
func (c *Client) SetName(name string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.name = name
}

// GetRoom ルームを取得
func (c *Client) GetRoom() *Room {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.room
}

// SetRoom ルームを設定
func (c *Client) SetRoom(room *Room) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.room = room
}

// SendMessage メッセージを送信
func (c *Client) SendMessage(msg ServerMessage) {
	c.mu.RLock()
	if c.closed {
		c.mu.RUnlock()
		return
	}
	c.mu.RUnlock()

	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Error marshaling message: %v", err)
		return
	}

	// panicをrecover（チャネルクローズの競合を防ぐ）
	defer func() {
		if r := recover(); r != nil {
			log.Printf("SendMessage recovered from panic: %v", r)
		}
	}()

	select {
	case c.send <- data:
	default:
		// バッファがいっぱいの場合はクライアントを切断
		c.hub.unregister <- c
	}
}

// MarkClosed クライアントをclose済みとしてマーク
func (c *Client) MarkClosed() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.closed = true
}

// readPump WebSocketからメッセージを読み取るループ
func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		log.Printf("Received message: %s", string(message))

		var msg ClientMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			log.Printf("Error unmarshaling message: %v", err)
			c.SendMessage(NewErrorMessage("Invalid message format"))
			continue
		}

		log.Printf("Parsed message type: %s", msg.Type)
		c.handleMessage(msg)
	}
}

// writePump クライアントへメッセージを書き込むループ
func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// バッファ内の残りメッセージも送信
			n := len(c.send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// handleMessage メッセージを処理
func (c *Client) handleMessage(msg ClientMessage) {
	switch msg.Type {
	case MsgTypeLeaveRoom:
		c.handleLeaveRoom()
	case MsgTypeRelay:
		c.handleRelay(msg)
	case MsgTypeFindMatch:
		c.handleFindMatch(msg)
	case MsgTypeCancelMatch:
		c.handleCancelMatch()
	case MsgTypeHeartbeat:
		c.SendMessage(NewServerMessage(MsgTypeHeartbeatAck, nil))
	default:
		c.SendMessage(NewErrorMessage("Unknown message type: " + msg.Type))
	}
}

// handleLeaveRoom ルーム退出
func (c *Client) handleLeaveRoom() {
	room := c.GetRoom()
	if room == nil {
		return
	}

	peerID := c.GetPeerID()
	roomID := room.ID
	roomName := room.Name
	isEmpty := room.RemoveClient(c)

	// ルームが空になった場合は削除
	if isEmpty {
		c.hub.RemoveRoom(roomID)
		log.Printf("Room %s (%s) removed - no players remaining", roomName, roomID)
	} else {
		// 他のプレイヤーに退出を通知
		room.Broadcast(NewServerMessage(MsgTypePeerDisconnected, PeerEventPayload{
			PeerID: peerID,
		}))
	}

	log.Printf("Player %s left room %s", c.GetName(), roomName)
}

// GetGameMode ゲームモードを取得
func (c *Client) GetGameMode() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.gameMode
}

// SetGameMode ゲームモードを設定
func (c *Client) SetGameMode(mode string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.gameMode = mode
}

// handleFindMatch マッチ待機キューに追加
func (c *Client) handleFindMatch(msg ClientMessage) {
	if c.GetRoom() != nil {
		c.SendMessage(NewErrorMessage("Already in a room"))
		return
	}

	playerName := msg.PlayerName
	if playerName == "" {
		playerName = "Player"
	}
	c.SetName(playerName)
	c.SetGameMode(msg.GameMode)

	c.hub.AddToMatchQueue(c)
}

// handleCancelMatch マッチ待機キャンセル
func (c *Client) handleCancelMatch() {
	c.hub.RemoveFromMatchQueue(c)
}

// handleRelay メッセージリレー
func (c *Client) handleRelay(msg ClientMessage) {
	room := c.GetRoom()
	if room == nil {
		c.SendMessage(NewErrorMessage("Not in a room"))
		return
	}

	relayMsg := NewServerMessage(MsgTypeMessage, RelayPayload{
		From:    c.GetPeerID(),
		MsgType: msg.MsgType,
		Data:    msg.Data,
	})

	if msg.To == 0 {
		// ブロードキャスト（自分以外全員）
		room.BroadcastExcept(c, relayMsg)
	} else {
		// ユニキャスト（特定のピアへ）
		room.SendTo(msg.To, relayMsg)
	}
}
