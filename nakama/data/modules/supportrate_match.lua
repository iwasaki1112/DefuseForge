--[[
SupportRate Game - Match Handler Module
マッチのライフサイクル管理
]]--

local nk = require("nakama")

local function match_init(context, setupstate)
    local gamestate = {
        match_id = context.match_id,
        tick_rate = 20,
        team_size = setupstate.team_size or 5,
        team_a = {},
        team_b = {},
        phase = "waiting",
        round = 0,
        max_rounds = 15,
        presences = {},
        player_count = 0,
        room_code = setupstate.room_code or nil,
        is_private = setupstate.is_private or false,
        host_user_id = setupstate.host_user_id or nil,
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
        if #state.team_a < state.team_size then
            table.insert(state.team_a, presence.user_id)
        else
            table.insert(state.team_b, presence.user_id)
        end
        nk.logger_info(string.format("Player %s joined match %s", presence.user_id, state.match_id))
    end

    local label = nk.json_encode({
        team_size = state.team_size,
        phase = state.phase,
        player_count = state.player_count,
        room_code = state.room_code,
        is_private = state.is_private
    })
    -- マッチラベルを更新（検索可能にする）
    dispatcher.match_label_update(label)
    dispatcher.broadcast_message(0, label)

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

    -- マッチラベルを更新
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
    for _, message in ipairs(messages) do
        local op_code = message.op_code
        local sender = message.sender
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
            end
        elseif op_code == 5 then
            -- チーム割り当て: ホストから全員にブロードキャスト（送信者含む）
            nk.logger_info(string.format("Broadcasting team assignment from %s", sender.user_id))
            dispatcher.broadcast_message(5, message.data)
        elseif op_code == 10 then
            -- プレイヤー位置: 全員にブロードキャスト（送信者含む）
            -- クライアント側で自分自身のデータをフィルタリングする
            dispatcher.broadcast_message(10, message.data)
        elseif op_code == 11 then
            -- プレイヤーアクション: 全員にブロードキャスト
            dispatcher.broadcast_message(11, message.data)
        elseif op_code == 20 and sender.user_id == state.host_user_id then
            local data = nk.json_decode(message.data)
            if data and data.phase then
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

return {
    match_init = match_init,
    match_join_attempt = match_join_attempt,
    match_join = match_join,
    match_leave = match_leave,
    match_loop = match_loop,
    match_terminate = match_terminate,
    match_signal = match_signal
}
