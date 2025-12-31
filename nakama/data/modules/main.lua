--[[
SupportRate Game - Nakama Server Module
RPC関数定義
]]--

local nk = require("nakama")

-- =====================================
-- 定数
-- =====================================
local MATCH_MODULE = "supportrate_match"

-- =====================================
-- RPC: ルーム作成
-- =====================================
local function rpc_create_room(context, payload)
    local data = nk.json_decode(payload)
    local team_size = data.team_size or 5
    local is_private = data.is_private or false

    -- ルームコード生成（6桁英数字）
    local room_code = nil
    if is_private then
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        room_code = ""
        for i = 1, 6 do
            local idx = math.random(1, string.len(chars))
            room_code = room_code .. string.sub(chars, idx, idx)
        end
    end

    -- マッチ作成
    local match_id = nk.match_create(MATCH_MODULE, {
        team_size = team_size,
        room_code = room_code,
        is_private = is_private,
        host_user_id = context.user_id
    })

    nk.logger_info(string.format("Room created: %s (code: %s)", match_id, room_code or "public"))

    return nk.json_encode({
        match_id = match_id,
        room_code = room_code,
        team_size = team_size,
        is_private = is_private
    })
end

nk.register_rpc(rpc_create_room, "create_room")

-- =====================================
-- RPC: ルームコードで参加
-- =====================================
local function rpc_join_by_code(context, payload)
    local data = nk.json_decode(payload)
    local room_code = data.room_code

    if not room_code or room_code == "" then
        return nk.json_encode({error = "Room code required"})
    end

    -- ルームコードでマッチを検索
    local query = string.format("+label.room_code:%s", room_code)
    local min_count = 0
    local max_count = 10
    local matches = nk.match_list(1, true, nil, min_count, max_count, query)

    if #matches == 0 then
        return nk.json_encode({error = "Room not found"})
    end

    local match = matches[1]

    return nk.json_encode({
        match_id = match.match_id,
        room_code = room_code
    })
end

nk.register_rpc(rpc_join_by_code, "join_by_code")

-- =====================================
-- RPC: 公開ルーム一覧
-- =====================================
local function rpc_list_rooms(context, payload)
    nk.logger_info("list_rooms called with payload: " .. (payload or "nil"))

    local data = {}
    if payload and payload ~= "" then
        data = nk.json_decode(payload)
    end

    local team_size = data.team_size  -- nilなら全サイズ

    -- 公開ルームのみ検索（クエリなしで全マッチを取得）
    local query = "*"
    nk.logger_info("Searching with query: " .. query)

    local min_count = 0
    local max_count = 50
    local matches = nk.match_list(50, true, nil, min_count, max_count, query)

    nk.logger_info("Found " .. #matches .. " matches")

    local rooms = {}
    for _, match in ipairs(matches) do
        nk.logger_info("Match: " .. match.match_id .. " label: " .. (match.label or "nil"))
        if match.label and match.label ~= "" then
            local label = nk.json_decode(match.label)
            -- 公開ルームかつ待機中のみ
            if not label.is_private and label.phase == "waiting" then
                if not team_size or label.team_size == team_size then
                    table.insert(rooms, {
                        match_id = match.match_id,
                        team_size = label.team_size,
                        player_count = label.player_count,
                        phase = label.phase
                    })
                end
            end
        end
    end

    nk.logger_info("Returning " .. #rooms .. " rooms")
    return nk.json_encode({rooms = rooms})
end

nk.register_rpc(rpc_list_rooms, "list_rooms")

nk.logger_info("SupportRate Game module loaded")
