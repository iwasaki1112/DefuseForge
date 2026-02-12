package main

// クライアント→サーバーのメッセージタイプ
const (
	MsgTypeCreateRoom  = "CREATE_ROOM"
	MsgTypeListRooms   = "LIST_ROOMS"
	MsgTypeJoinRoom    = "JOIN_ROOM"
	MsgTypeLeaveRoom   = "LEAVE_ROOM"
	MsgTypeRelay       = "RELAY"
	MsgTypeHeartbeat   = "HEARTBEAT"
	MsgTypeFindMatch   = "FIND_MATCH"
	MsgTypeCancelMatch = "CANCEL_MATCH"
)

// サーバー→クライアントのメッセージタイプ
const (
	MsgTypeRoomCreated      = "ROOM_CREATED"
	MsgTypeRoomList         = "ROOM_LIST"
	MsgTypeRoomJoined       = "ROOM_JOINED"
	MsgTypePeerConnected    = "PEER_CONNECTED"
	MsgTypePeerDisconnected = "PEER_DISCONNECTED"
	MsgTypeMessage          = "MESSAGE"
	MsgTypeError            = "ERROR"
	MsgTypeHeartbeatAck     = "HEARTBEAT_ACK"
	MsgTypeMatchFound       = "MATCH_FOUND"
)

// ClientMessage クライアントからのメッセージ
type ClientMessage struct {
	Type       string                 `json:"type"`
	RoomName   string                 `json:"room_name,omitempty"`
	RoomID     string                 `json:"room_id,omitempty"`
	PlayerName string                 `json:"player_name,omitempty"`
	To         int                    `json:"to,omitempty"`          // 0=ブロードキャスト, >0=特定ピアへ
	MsgType    int                    `json:"msg_type,omitempty"`    // ゲーム内メッセージタイプ
	Data       map[string]interface{} `json:"data,omitempty"`        // ゲームデータ
}

// ServerMessage サーバーからのメッセージ（基本構造）
type ServerMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload,omitempty"`
}

// RoomCreatedPayload ルーム作成完了
type RoomCreatedPayload struct {
	RoomID string `json:"room_id"`
	PeerID int    `json:"peer_id"`
}

// RoomListPayload ルーム一覧
type RoomListPayload struct {
	Rooms []RoomInfo `json:"rooms"`
}

// RoomInfo ルーム情報
type RoomInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	PlayerCount int    `json:"player_count"`
	MaxPlayers  int    `json:"max_players"`
}

// RoomJoinedPayload ルーム参加完了
type RoomJoinedPayload struct {
	RoomID  string       `json:"room_id"`
	PeerID  int          `json:"peer_id"`
	Players []PlayerInfo `json:"players"`
}

// PlayerInfo プレイヤー情報
type PlayerInfo struct {
	PeerID int    `json:"peer_id"`
	Name   string `json:"name"`
}

// PeerEventPayload ピア接続/切断イベント
type PeerEventPayload struct {
	PeerID int    `json:"peer_id"`
	Name   string `json:"name,omitempty"`
}

// RelayPayload リレーメッセージ
type RelayPayload struct {
	From    int                    `json:"from"`
	MsgType int                    `json:"msg_type"`
	Data    map[string]interface{} `json:"data"`
}

// ErrorPayload エラー
type ErrorPayload struct {
	Message string `json:"message"`
}

// MatchFoundPayload マッチ成立通知
type MatchFoundPayload struct {
	RoomID  string       `json:"room_id"`
	PeerID  int          `json:"peer_id"`
	MapID   string       `json:"map_id"`
	Players []PlayerInfo `json:"players"`
}

// NewServerMessage サーバーメッセージを作成
func NewServerMessage(msgType string, payload interface{}) ServerMessage {
	return ServerMessage{
		Type:    msgType,
		Payload: payload,
	}
}

// NewErrorMessage エラーメッセージを作成
func NewErrorMessage(message string) ServerMessage {
	return ServerMessage{
		Type: MsgTypeError,
		Payload: ErrorPayload{
			Message: message,
		},
	}
}
