package main

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"math/big"
	"sync"
)

// 利用可能マップIDリスト
var availableMapIDs = []string{"home"}

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

// RemoveRoom ルームを削除
func (h *Hub) RemoveRoom(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.rooms, id)
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
// 同じゲームモードのプレイヤーとのみマッチする
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
	gameMode := client.GetGameMode()
	log.Printf("Matchmaking: Player %s (mode: %s) added to queue (queue size: %d)", client.GetName(), gameMode, len(h.matchQueue))

	// 同じゲームモードの相手をキューから探す
	for i, candidate := range h.matchQueue {
		if candidate == client {
			continue
		}
		if candidate.GetGameMode() == gameMode {
			// キューから両者を削除
			h.matchQueue = h.removeFromSlice(h.matchQueue, client, candidate)
			h.createMatchLocked(candidate, client)
			return
		}
		_ = i
	}
}

// removeFromSlice スライスから2つの要素を削除
func (h *Hub) removeFromSlice(queue []*Client, a, b *Client) []*Client {
	result := make([]*Client, 0, len(queue)-2)
	for _, c := range queue {
		if c != a && c != b {
			result = append(result, c)
		}
	}
	return result
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
