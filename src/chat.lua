-- src/chat.lua — /aibot chat command + @bot message routing
--
-- The `@bot` handler is extracted into aibot.chat.handle_message so it can
-- be unit-tested directly. The Luanti callback just forwards.

aibot.chat = aibot.chat or {}

-- Guard against pathological input reaching the LLM (which would waste tokens
-- and, in a hostile scenario, could be a DoS vector).
local MAX_COMMAND_LEN = 500

-- Returns true if we handled the message (Luanti should stop propagating),
-- false if the message wasn't meant for us.
function aibot.chat.handle_message(player_name, message)
    -- Accept exactly "@bot" (empty command) OR "@bot" followed by whitespace
    -- and any content. Reject "@boto", "@bots" etc. — the char after "@bot"
    -- must be end-of-string or whitespace.
    local rest
    if message == "@bot" then
        rest = ""
    else
        rest = message:match("^@bot%s+(.*)$")
        if not rest then return false end
    end
    local command = rest:gsub("^%s+", ""):gsub("%s+$", "")

    if command == "" then
        core.chat_send_player(player_name,
            "[AIBot] 請輸入指令，例：@bot 砍樹")
        return true
    end

    if #command > MAX_COMMAND_LEN then
        core.chat_send_player(player_name,
            "[AIBot] 指令太長（" .. #command .. " 字，上限 " .. MAX_COMMAND_LEN .. "），請簡短")
        return true
    end

    local bot_info = aibot.state.get_bot(player_name)
    if not bot_info then
        core.chat_send_player(player_name, "[AIBot] 你還沒 spawn bot，先執行 /aibot spawn")
        return true
    end
    local luaentity = bot_info.luaentity
    if not luaentity or not luaentity.object then
        aibot.state.unregister_bot(player_name)
        core.chat_send_player(player_name, "[AIBot] bot 已消失，請重新 /aibot spawn")
        return true
    end

    -- immediate-stop shortcut: bypass LLM for interrupt latency
    if command == "停" or command:lower() == "stop" then
        aibot.executor.cancel(luaentity)
        core.chat_send_player(player_name, "[AIBot] 停下。")
        return true
    end

    if not aibot.http then
        core.chat_send_player(player_name,
            "[AIBot] HTTP API 未啟用。請在 minetest.conf 加 `secure.http_mods = aibot` 並重啟。")
        return true
    end
    if not aibot.config.is_ready() then
        core.chat_send_player(player_name,
            "[AIBot] LLM 未設定：" .. (aibot.config.reason_not_ready() or "unknown"))
        return true
    end

    aibot.planner.plan(luaentity, command)
    return true
end
aibot.chat.MAX_COMMAND_LEN = MAX_COMMAND_LEN

core.register_chatcommand("aibot", {
    params = "spawn",
    description = "Manage your AI bot (MVP: only 'spawn' supported)",
    func = function(name, param)
        local player = core.get_player_by_name(name)
        if not player then return false, "you must be in-game" end
        param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if param == "spawn" or param == "" then
            local bot = aibot.spawn_bot(player)
            if not bot then
                return false, "無法 spawn bot（位置可能被阻擋或 mob 註冊失敗）"
            end
            return true, "spawned"
        end
        return false, "usage: /aibot spawn"
    end,
})

core.register_on_chat_message(function(player_name, message)
    return aibot.chat.handle_message(player_name, message)
end)
