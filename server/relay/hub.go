package main

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
)

// Hub クライアントとルームを管理する中央ハブ
type Hub struct {
	clients    map[*Client]bool
	rooms      map[string]*Room
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
}

// NewHub 新しいHubを作成
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		rooms:      make(map[string]*Room),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

// Run Hubのメインループ
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()

		case client := <-h.unregister:
			var roomToRemove string
			var roomForBroadcast *Room
			var peerID int

			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				// ルームから退出
				if room := client.GetRoom(); room != nil {
					peerID = client.GetPeerID()
					roomForBroadcast = room
					isEmpty := room.RemoveClient(client)
					if isEmpty {
						roomToRemove = room.ID
					}
				}
				delete(h.clients, client)
				client.MarkClosed()
				close(client.send)
			}
			h.mu.Unlock()

			// ロック解放後にルーム削除（デッドロック回避）
			if roomToRemove != "" {
				h.RemoveRoom(roomToRemove)
			}

			// ロック解放後に他のプレイヤーへ通知
			if roomForBroadcast != nil && roomToRemove == "" {
				roomForBroadcast.Broadcast(NewServerMessage(MsgTypePeerDisconnected, PeerEventPayload{
					PeerID: peerID,
				}))
			}
		}
	}
}

// CreateRoom 新しいルームを作成
func (h *Hub) CreateRoom(name string) *Room {
	h.mu.Lock()
	defer h.mu.Unlock()

	id := h.generateRoomID()
	room := NewRoom(id, name, h)
	h.rooms[id] = room
	return room
}

// GetRoom ルームを取得
func (h *Hub) GetRoom(id string) *Room {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.rooms[id]
}

// RemoveRoom ルームを削除
func (h *Hub) RemoveRoom(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.rooms, id)
}

// GetRoomList ルーム一覧を取得
func (h *Hub) GetRoomList() []RoomInfo {
	h.mu.RLock()
	defer h.mu.RUnlock()

	list := make([]RoomInfo, 0, len(h.rooms))
	for _, room := range h.rooms {
		list = append(list, RoomInfo{
			ID:          room.ID,
			Name:        room.Name,
			PlayerCount: room.GetPlayerCount(),
			MaxPlayers:  MaxPlayers,
		})
	}
	return list
}

// generateRoomID ランダムなルームIDを生成（4文字の16進数）
func (h *Hub) generateRoomID() string {
	for {
		bytes := make([]byte, 2)
		rand.Read(bytes)
		id := hex.EncodeToString(bytes)
		// 重複チェック
		if _, exists := h.rooms[id]; !exists {
			return id
		}
	}
}
