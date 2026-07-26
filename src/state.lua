-- src/state.lua — in-memory owner ↔ bot mapping (MVP: 1 bot per player)

aibot.state = {
    bots_by_owner = {},  -- player_name -> { luaentity, bot_id }
}

function aibot.state.register_bot(owner_name, luaentity)
    aibot.state.bots_by_owner[owner_name] = {
        luaentity = luaentity,
        bot_id    = luaentity._bot_id,
    }
end

function aibot.state.unregister_bot(owner_name)
    aibot.state.bots_by_owner[owner_name] = nil
end

function aibot.state.get_bot(owner_name)
    return aibot.state.bots_by_owner[owner_name]
end

function aibot.state.has_bot(owner_name)
    return aibot.state.bots_by_owner[owner_name] ~= nil
end
