-- src/chat.lua — /aibot chat command + @bot message routing

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
    local command = message:match("^@bot%s+(.*)")
    if not command then return false end  -- not for us
    command = command:gsub("^%s+", ""):gsub("%s+$", "")

    local bot_info = aibot.state.get_bot(player_name)
    if not bot_info then
        core.chat_send_player(player_name, "[aibot] 你還沒 spawn bot，先執行 /aibot spawn")
        return true
    end
    local luaentity = bot_info.luaentity
    if not luaentity or not luaentity.object then
        aibot.state.unregister_bot(player_name)
        core.chat_send_player(player_name, "[aibot] bot 已消失，請重新 /aibot spawn")
        return true
    end

    -- immediate-stop shortcut: bypass LLM for interrupt latency
    if command == "停" or command:lower() == "stop" then
        aibot.executor.cancel(luaentity)
        core.chat_send_player(player_name, "[Bot] 停下。")
        return true
    end

    if not aibot.http then
        core.chat_send_player(player_name,
            "[aibot] HTTP API 未啟用。請在 minetest.conf 加 `secure.http_mods = aibot` 並重啟。")
        return true
    end
    if not aibot.config.is_ready() then
        core.chat_send_player(player_name,
            "[aibot] LLM 未設定：" .. (aibot.config.reason_not_ready() or "unknown"))
        return true
    end

    aibot.planner.plan(luaentity, command)
    return true
end)
