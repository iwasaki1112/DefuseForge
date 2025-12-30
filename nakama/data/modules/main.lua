--[[
SupportRate Game - Nakama Server Module
マッチメイキング、ルーム管理、ゲーム状態同期
]]--

local nk = require("nakama")

-- =====================================
-- 定数
-- =====================================
local MATCH_MODULE = "supportrate_match"
local MATCHMAKER_QUERY = "*"  -- 全員マッチ可能（後でスキルベースに拡張）

-- =====================================
-- マッチメイキング設定
-- =====================================

-- カスタムマッチ用のマッチハンドラを登録
local function match_init(context, setupstate)
    local gamestate = {
        -- マッチ設定
        match_id = context.match_id,
        tick_rate = 20,  -- 1秒に20回更新

        -- チーム設定
        team_size = setupstate.team_size or 5,
        team_a = {},
        team_b = {},

        -- ゲーム状態
        phase = "waiting",  -- waiting, buy, play, ended
        round = 0,
        max_rounds = 15,

        -- プレイヤー情報
        presences = {},
        player_count = 0,

        -- ルーム設定（ルーム作成式の場合）
        room_code = setupstate.room_code or nil,
        is_private = setupstate.is_private or false,
        host_user_id = setupstate.host_user_id or nil,

        -- 作成時刻
        created_at = os.time()
    }

    local tick_rate = gamestate.tick_rate
    local label = nk.json_encode({
        team_size = gamestate.team_size,
        phase = gamestate.phase,
        player_count = gamestate.player_count,
        room_code = gamestate.room_code,
        is_private = gamestate.is_private
    })

    return gamestate, tick_rate, label
end

local function match_join_attempt(context, dispatcher, tick, state, presence, metadata)
    -- 参加可否の判定
    local max_players = state.team_size * 2
    if state.player_count >= max_players then
        return state, false, "Match is full"
    end

    if state.phase ~= "waiting" then
        return state, false, "Match already started"
    end

    return state, true
end

local function match_join(context, dispatcher, tick, state, presences)
    for _, presence in ipairs(presences) do
        state.presences[presence.user_id] = presence
        state.player_count = state.player_count + 1

        -- チーム割り当て
        if #state.team_a < state.team_size then
            table.insert(state.team_a, presence.user_id)
        else
            table.insert(state.team_b, presence.user_id)
        end

        nk.logger_info(string.format("Player %s joined match %s", presence.user_id, state.match_id))
    end

    -- ラベル更新
    local label = nk.json_encode({
        team_size = state.team_size,
        phase = state.phase,
        player_count = state.player_count,
        room_code = state.room_code,
        is_private = state.is_private
    })
    dispatcher.match_label_update(label)

    -- 全員揃ったら通知
    local max_players = state.team_size * 2
    if state.player_count >= max_players then
        local data = nk.json_encode({
            event = "match_ready",
            team_a = state.team_a,
            team_b = state.team_b
        })
        dispatcher.broadcast_message(1, data)
    end

    return state
end

local function match_leave(context, dispatcher, tick, state, presences)
    for _, presence in ipairs(presences) do
        state.presences[presence.user_id] = nil
        state.player_count = state.player_count - 1

        -- チームから削除
        for i, user_id in ipairs(state.team_a) do
            if user_id == presence.user_id then
                table.remove(state.team_a, i)
                break
            end
        end
        for i, user_id in ipairs(state.team_b) do
            if user_id == presence.user_id then
                table.remove(state.team_b, i)
                break
            end
        end

        nk.logger_info(string.format("Player %s left match %s", presence.user_id, state.match_id))
    end

    -- ラベル更新
    local label = nk.json_encode({
        team_size = state.team_size,
        phase = state.phase,
        player_count = state.player_count,
        room_code = state.room_code,
        is_private = state.is_private
    })
    dispatcher.match_label_update(label)

    return state
end

local function match_loop(context, dispatcher, tick, state, messages)
    -- メッセージ処理
    for _, message in ipairs(messages) do
        local op_code = message.op_code
        local data = nk.json_decode(message.data)
        local sender = message.sender

        -- ゲーム開始要求（ホストのみ）
        if op_code == 1 and sender.user_id == state.host_user_id then
            if state.phase == "waiting" and state.player_count >= 2 then
                state.phase = "buy"
                state.round = 1
                local event_data = nk.json_encode({
                    event = "game_start",
                    phase = state.phase,
                    round = state.round
                })
                dispatcher.broadcast_message(2, event_data)

                local label = nk.json_encode({
                    team_size = state.team_size,
                    phase = state.phase,
                    player_count = state.player_count,
                    room_code = state.room_code,
                    is_private = state.is_private
                })
                dispatcher.match_label_update(label)
            end

        -- プレイヤー位置更新
        elseif op_code == 10 then
            -- 他のプレイヤーに転送
            dispatcher.broadcast_message(10, message.data, {sender})

        -- プレイヤーアクション（射撃、リロードなど）
        elseif op_code == 11 then
            dispatcher.broadcast_message(11, message.data, {sender})

        -- フェーズ変更要求
        elseif op_code == 20 and sender.user_id == state.host_user_id then
            if data.phase then
                state.phase = data.phase
                if data.round then
                    state.round = data.round
                end
                local event_data = nk.json_encode({
                    event = "phase_change",
                    phase = state.phase,
                    round = state.round
                })
                dispatcher.broadcast_message(2, event_data)
            end
        end
    end

    return state
end

local function match_terminate(context, dispatcher, tick, state, grace_seconds)
    nk.logger_info(string.format("Match %s terminating", state.match_id))
    return nil
end

local function match_signal(context, dispatcher, tick, state, data)
    return state, data
end

-- マッチハンドラ登録
nk.register_match(MATCH_MODULE, {
    match_init = match_init,
    match_join_attempt = match_join_attempt,
    match_join = match_join,
    match_leave = match_leave,
    match_loop = match_loop,
    match_terminate = match_terminate,
    match_signal = match_signal
})

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
            local idx = math.random(1, #chars)
            room_code = room_code .. chars:sub(idx, idx)
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
    local data = {}
    if payload and payload ~= "" then
        data = nk.json_decode(payload)
    end

    local team_size = data.team_size  -- nilなら全サイズ

    -- 公開ルームのみ検索
    local query = "+label.is_private:false +label.phase:waiting"
    if team_size then
        query = query .. string.format(" +label.team_size:%d", team_size)
    end

    local min_count = 0
    local max_count = 50
    local matches = nk.match_list(50, true, nil, min_count, max_count, query)

    local rooms = {}
    for _, match in ipairs(matches) do
        local label = nk.json_decode(match.label)
        table.insert(rooms, {
            match_id = match.match_id,
            team_size = label.team_size,
            player_count = label.player_count,
            phase = label.phase
        })
    end

    return nk.json_encode({rooms = rooms})
end

nk.register_rpc(rpc_list_rooms, "list_rooms")

-- =====================================
-- RPC: ランダムマッチメイキング参加
-- =====================================
local function rpc_join_matchmaking(context, payload)
    local data = nk.json_decode(payload)
    local team_size = data.team_size or 5

    -- マッチメイキングチケット作成
    local query = string.format("+properties.team_size:%d", team_size)
    local min_count = team_size * 2
    local max_count = team_size * 2
    local properties = {
        team_size = team_size
    }

    local ticket = nk.matchmaker_add(
        context.session_id,  -- session_id
        min_count,           -- min_count
        max_count,           -- max_count
        query,               -- query
        properties,          -- string_properties
        {}                   -- numeric_properties
    )

    return nk.json_encode({
        ticket = ticket
    })
end

nk.register_rpc(rpc_join_matchmaking, "join_matchmaking")

-- =====================================
-- マッチメイカーマッチ完了時の処理
-- =====================================
local function matchmaker_matched(context, matched_users)
    -- マッチしたユーザーからチームサイズを取得
    local team_size = 5
    for _, user in ipairs(matched_users) do
        if user.properties and user.properties.team_size then
            team_size = user.properties.team_size
            break
        end
    end

    -- マッチ作成
    local match_id = nk.match_create(MATCH_MODULE, {
        team_size = team_size,
        room_code = nil,
        is_private = false,
        host_user_id = matched_users[1].presence.user_id  -- 最初のユーザーをホストに
    })

    nk.logger_info(string.format("Matchmaker created match: %s for %d users", match_id, #matched_users))

    return match_id
end

nk.register_matchmaker_matched(matchmaker_matched)

nk.logger_info("SupportRate Game module loaded")
