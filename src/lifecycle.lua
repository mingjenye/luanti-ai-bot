-- src/lifecycle.lua — player lifecycle hooks
--
-- When the bot's owner disconnects, we don't despawn the bot (it may still
-- be alive in the world; another player could later see it standing there)
-- but we DO cancel any in-flight task so the bot doesn't wander off or
-- burn LLM tokens on stale plans. On rejoin, the bot is picked up again
-- by the existing state entry — owner may re-issue commands.

core.register_on_leaveplayer(function(player)
    if not player or not player.get_player_name then return end
    local player_name = player:get_player_name()
    local bot_info = aibot.state.get_bot(player_name)
    if bot_info and bot_info.luaentity and bot_info.luaentity.object then
        aibot.executor.cancel(bot_info.luaentity)
    end
end)
