package main

import (
	"sync"
)

const (
	// ルームの最大プレイヤー数
	MaxPlayers = 4
)

// Room ゲームルーム
type Room struct {
	ID         string
	Name       string
	clients    map[*Client]bool
	nextPeerID int
	mu         sync.RWMutex
	hub        *Hub
}

// NewRoom 新しいルームを作成
func NewRoom(id, name string, hub *Hub) *Room {
	return &Room{
		ID:         id,
		Name:       name,
		clients:    make(map[*Client]bool),
		nextPeerID: 1, // ホストは常にPeerID=1
		hub:        hub,
	}
}

// AddClient クライアントをルームに追加
func (r *Room) AddClient(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()

	c.SetPeerID(r.nextPeerID)
	r.nextPeerID++
	c.SetRoom(r)
	r.clients[c] = true
}

// RemoveClient クライアントをルームから削除
// 戻り値: ルームが空になった場合はtrue
func (r *Room) RemoveClient(c *Client) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	delete(r.clients, c)
	c.SetRoom(nil)

	// ルームが空になったかを返す（削除はHub側で行う）
	return len(r.clients) == 0
}

// IsFull ルームが満員か
func (r *Room) IsFull() bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.clients) >= MaxPlayers
}

// GetPlayerCount プレイヤー数を取得
func (r *Room) GetPlayerCount() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.clients)
}

// GetPlayerList プレイヤー一覧を取得
func (r *Room) GetPlayerList() []PlayerInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()

	players := make([]PlayerInfo, 0, len(r.clients))
	for client := range r.clients {
		players = append(players, PlayerInfo{
			PeerID: client.GetPeerID(),
			Name:   client.GetName(),
		})
	}
	return players
}

// Broadcast 全クライアントにメッセージを送信
func (r *Room) Broadcast(msg ServerMessage) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for client := range r.clients {
		client.SendMessage(msg)
	}
}

// BroadcastExcept 指定クライアント以外にメッセージを送信
func (r *Room) BroadcastExcept(except *Client, msg ServerMessage) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for client := range r.clients {
		if client != except {
			client.SendMessage(msg)
		}
	}
}

// SendTo 特定のピアIDにメッセージを送信
func (r *Room) SendTo(peerID int, msg ServerMessage) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for client := range r.clients {
		if client.GetPeerID() == peerID {
			client.SendMessage(msg)
			return
		}
	}
}
