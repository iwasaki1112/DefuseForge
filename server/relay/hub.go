package main

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"math/big"
	"sync"
)

// 利用可能マップIDリスト
var availableMapIDs = []string{"home", "office"}

// Hub クライアントとルームを管理する中央ハブ
type Hub struct {
	clients    map[*Client]bool
	rooms      map[string]*Room
	matchQueue []*Client
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
}

// NewHub 新しいHubを作成
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		rooms:      make(map[string]*Room),
		matchQueue: make([]*Client, 0),
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
				// マッチキューから削除
				h.removeFromMatchQueueLocked(client)

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

// ========================================
// マッチメイキング
// ========================================

// AddToMatchQueue マッチ待機キューにクライアントを追加
// マッチ成立した場合はtrueを返す
func (h *Hub) AddToMatchQueue(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	// 既にキューにいる場合はスキップ
	for _, c := range h.matchQueue {
		if c == client {
			return
		}
	}

	h.matchQueue = append(h.matchQueue, client)
	log.Printf("Matchmaking: Player %s added to queue (queue size: %d)", client.GetName(), len(h.matchQueue))

	// 2人揃ったらマッチ成立
	if len(h.matchQueue) >= 2 {
		player1 := h.matchQueue[0]
		player2 := h.matchQueue[1]
		h.matchQueue = h.matchQueue[2:]

		h.createMatchLocked(player1, player2)
	}
}

// RemoveFromMatchQueue マッチ待機キューからクライアントを削除
func (h *Hub) RemoveFromMatchQueue(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.removeFromMatchQueueLocked(client)
}

// removeFromMatchQueueLocked ロック保持済みの状態でキューからクライアントを削除
func (h *Hub) removeFromMatchQueueLocked(client *Client) {
	for i, c := range h.matchQueue {
		if c == client {
			h.matchQueue = append(h.matchQueue[:i], h.matchQueue[i+1:]...)
			log.Printf("Matchmaking: Player %s removed from queue (queue size: %d)", client.GetName(), len(h.matchQueue))
			return
		}
	}
}

// createMatchLocked マッチを成立させる（ロック保持済み）
func (h *Hub) createMatchLocked(player1, player2 *Client) {
	// マップをランダム選択
	mapIdx, _ := rand.Int(rand.Reader, big.NewInt(int64(len(availableMapIDs))))
	mapID := availableMapIDs[mapIdx.Int64()]

	// ルーム作成
	id := h.generateRoomID()
	room := NewRoom(id, "match_"+id, h)
	h.rooms[id] = room

	// プレイヤーをルームに追加（player1=Host=PeerID 1, player2=Client=PeerID 2）
	room.AddClient(player1)
	room.AddClient(player2)

	// プレイヤー一覧を取得
	players := room.GetPlayerList()

	// 両プレイヤーにマッチ成立通知
	player1.SendMessage(NewServerMessage(MsgTypeMatchFound, MatchFoundPayload{
		RoomID:  id,
		PeerID:  player1.GetPeerID(),
		MapID:   mapID,
		Players: players,
	}))

	player2.SendMessage(NewServerMessage(MsgTypeMatchFound, MatchFoundPayload{
		RoomID:  id,
		PeerID:  player2.GetPeerID(),
		MapID:   mapID,
		Players: players,
	}))

	log.Printf("Matchmaking: Match found! Room %s, Map %s, Players: %s vs %s",
		id, mapID, player1.GetName(), player2.GetName())
}
