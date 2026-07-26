-- src/bot_entity.lua — mcl_mobs custom mob registration + spawn helper
--
-- References verified in docs/spike-report.md (R2):
--   mobs:register_mob(name, def)
--   mobs:gopath(self, target, callback)
--   self.owner, self.state, self.order — mcl_mobs built-in fields
--   do_custom(self, dtime) — tick callback for our state machine

mobs:register_mob("aibot:companion", {
    type    = "npc",
    visual  = "mesh",
    mesh    = "character.b3d",
    textures = { { "character.png" } },
    visual_size    = { x = 1, y = 1 },
    collisionbox   = { -0.3, 0, -0.3, 0.3, 1.7, 0.3 },
    makes_footstep_sound = true,
    hp_min = 20, hp_max = 20,
    walk_velocity  = 2,
    run_velocity   = 3,
    walk_chance    = 0,   -- don't wander autonomously
    jump           = true,
    view_range     = 32,
    pathfinding    = 1,   -- built-in basic pathfinding
    order          = "stand",
    passive        = true,

    -- custom state (persisted on self via mcl_mobs)
    _bot_state  = "idle",   -- idle | planning | executing
    _task_queue = nil,
    _owner      = nil,
    _bot_id     = nil,
    _last_say_at = 0,

    on_spawn = function(self)
        self._task_queue = {}
        return true
    end,

    do_custom = function(self, dtime)
        -- state machine tick: drain the task queue one step at a time
        if aibot.executor and aibot.executor.tick then
            aibot.executor.tick(self, dtime)
        end
    end,

    on_die = function(self, pos)
        if self._bot_id and aibot.inventory then
            -- Bot dies: drop its inventory on the ground so the owner can
            -- pick up what remains, then remove the inventory storage.
            local drop_pos = pos or (self.object and self.object:get_pos())
            local summary = aibot.inventory.summary(self._bot_id)
            for _ = 1, #summary do
                local stack = aibot.inventory.take_stack(self._bot_id)
                if stack and not stack:is_empty() and drop_pos then
                    core.add_item(drop_pos, stack)
                end
            end
            aibot.inventory.destroy(self._bot_id)
        end
        if self._owner then
            aibot.state.unregister_bot(self._owner)
            if core.get_player_by_name(self._owner) then
                core.chat_send_player(self._owner, "[AIBot] 你的 bot 死了，背包物品掉在死亡地點")
            end
        end
    end,
})

function aibot.spawn_bot(player)
    local player_name = player:get_player_name()

    -- MVP: 1 bot per player. Despawn old before creating new.
    if aibot.state.has_bot(player_name) then
        local existing = aibot.state.get_bot(player_name)
        if existing.luaentity and existing.luaentity.object then
            existing.luaentity.object:remove()
        end
        aibot.state.unregister_bot(player_name)
    end

    local pos = player:get_pos()
    pos.x = pos.x + 1  -- spawn one block to the side

    -- mcl_mobs:spawn returns nil on failure (e.g. position blocked)
    local obj = mcl_mobs and mcl_mobs.spawn and mcl_mobs:spawn(pos, "aibot:companion")
    if not obj then
        -- fallback: use core.add_entity directly
        obj = core.add_entity(pos, "aibot:companion")
    end
    if not obj then return nil end

    local luaentity = obj:get_luaentity()
    if not luaentity then return nil end

    luaentity._owner  = player_name
    luaentity._bot_id = "bot-" .. player_name .. "-" .. os.time()
    luaentity.owner   = player_name  -- mcl_mobs built-in
    luaentity.tamed   = true
    luaentity.order   = "follow"

    -- Give the bot its own detached inventory (M2b).
    if aibot.inventory then
        aibot.inventory.create(luaentity._bot_id)
    end

    local nametag = "AIBot (" .. player_name .. ")"
    obj:set_properties({ nametag = nametag, nametag_color = "#00ffcc" })

    aibot.state.register_bot(player_name, luaentity)

    core.after(0.5, function()
        if core.get_player_by_name(player_name) then
            core.chat_send_player(player_name,
                "[AIBot] 我是你的 AI Bot！用 @bot + 指令控制我，例如：@bot 砍樹")
        end
    end)

    return luaentity
end
