-- src/executor.lua — whitelist action executor for the 9 MVP actions
--
-- Tool calls from LLM are validated against the ACTIONS table below.
-- Any name not in ACTIONS is rejected here. This is the security boundary
-- (planner passes tool_call names through verbatim; the enforcement point
-- is `aibot.executor.queue`).

aibot.executor = {}

-- Bounds guard for go_to: reject targets more than N blocks from the bot.
-- Rationale (per frank's safety review of PR #2):
--   * LLMs occasionally hallucinate absurd coordinates (e.g. 1e6, 1e6).
--   * mcl_mobs pathfinding is basic and would spin trying to reach them.
--   * Absurd coordinates can also load unnecessary map chunks.
local MAX_GO_TO_DISTANCE = 100

-- Pure distance helper, exposed for unit testing.
function aibot.executor.distance(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function say(luaentity, text)
    if luaentity._owner then
        core.chat_send_player(luaentity._owner, "[Bot] " .. text)
    end
end
aibot.executor.say = say

-- ─── target resolution ──────────────────────────────────────────
-- LLM gives target descriptions ("nearest tree"); we resolve here at execution
-- time against current world state. This is R3's mitigation pattern.
-- Exposed on aibot.executor so it can be unit-tested with mocks.

function aibot.executor.resolve_target(luaentity, description)
    if not description or description == "" then return nil end
    local desc = tostring(description):lower()

    if desc:match("owner") or desc:match("player") or desc:match("主人") or desc:match("我") then
        local p = core.get_player_by_name(luaentity._owner)
        return p and p:get_pos() or nil
    end

    if desc:match("tree") or desc:match("樹") or desc:match("wood") or desc:match("log") then
        local pos = luaentity.object:get_pos()
        local trees = core.find_nodes_in_area(
            { x = pos.x - 20, y = pos.y - 10, z = pos.z - 20 },
            { x = pos.x + 20, y = pos.y + 10, z = pos.z + 20 },
            { "group:tree", "group:leaves" }
        )
        return trees and trees[1] or nil
    end

    return nil
end

-- ─── actions ────────────────────────────────────────────────────

local ACTIONS = {}

ACTIONS.say = function(self, args)
    say(self, tostring(args.text or ""))
end

ACTIONS.follow = function(self, args)
    self.order = "follow"
    self.state = "walk"
    say(self, "跟你走。")
end

ACTIONS.stop = function(self, args)
    self._task_queue = {}
    self.order = "stand"
    self.state = "stand"
    say(self, "停下。")
end

ACTIONS.go_to = function(self, args)
    local target_pos = nil
    if args.target then
        target_pos = aibot.executor.resolve_target(self, args.target)
    elseif args.x and args.y and args.z then
        target_pos = { x = tonumber(args.x), y = tonumber(args.y), z = tonumber(args.z) }
        if not target_pos.x or not target_pos.y or not target_pos.z then
            say(self, "go_to 座標無效")
            return
        end
    end
    if not target_pos then
        say(self, "找不到目標：" .. tostring(args.target or "(no target)"))
        return
    end
    -- Distance guard (frank safety review)
    local bot_pos = self.object and self.object:get_pos() or {x=0, y=0, z=0}
    local dist = aibot.executor.distance(bot_pos, target_pos)
    if dist > MAX_GO_TO_DISTANCE then
        say(self, string.format("目標太遠（%d blocks，上限 %d）",
            math.floor(dist), MAX_GO_TO_DISTANCE))
        return
    end
    if mobs and mobs.gopath then
        mobs:gopath(self, target_pos, function()
            say(self, "到了。")
        end)
    else
        -- Fallback: set movement target directly
        self._target_pos = target_pos
        say(self, "移動中（無 pathfinding fallback）")
    end
end

ACTIONS.pickup_nearby = function(self, args)
    -- Safety (frank safety review): do NOT remove item entities before we
    -- have a real inventory to store them in. Data loss is worse than a
    -- stub. This action becomes real in M2b when detached inventory lands.
    local pos = self.object:get_pos()
    local radius = tonumber(args.radius) or 3
    local objects = core.get_objects_inside_radius(pos, radius)
    local visible = 0
    for _, obj in ipairs(objects) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "__builtin:item" then
            visible = visible + 1
        end
    end
    say(self, string.format(
        "附近有 %d 個掉落物（撿取功能等 M2b detached inventory 完成後啟用；目前不動它們避免資料遺失）",
        visible))
end

ACTIONS.drop_to_player = function(self, args)
    say(self, "TODO: drop_to_player 尚未實作（等 detached inventory）")
end

ACTIONS.drop_to_chest = function(self, args)
    say(self, "TODO: drop_to_chest 尚未實作")
end

ACTIONS.query_recipe = function(self, args)
    local item = args.item_name or args.item or ""
    if item == "" then
        say(self, "query_recipe 缺 item_name")
        return
    end
    local recipe = core.get_craft_recipe(item)
    if recipe and recipe.items then
        say(self, item .. " 的配方：" .. core.write_json(recipe.items))
    else
        say(self, "查無 " .. item .. " 的配方")
    end
end

ACTIONS.query_inventory = function(self, args)
    -- MVP: return placeholder until detached inventory is wired
    say(self, "TODO: query_inventory 尚未實作（等 detached inventory）")
end

-- ─── queue + tick ───────────────────────────────────────────────

function aibot.executor.queue(luaentity, action_name, args)
    if not ACTIONS[action_name] then
        say(luaentity, "unknown action: " .. tostring(action_name))
        return
    end
    luaentity._task_queue = luaentity._task_queue or {}
    table.insert(luaentity._task_queue, { name = action_name, args = args or {} })
end

function aibot.executor.cancel(luaentity)
    luaentity._task_queue = {}
    luaentity._bot_state  = "idle"
    luaentity.order = "stand"
    luaentity.state = "stand"
end

function aibot.executor.tick(luaentity, dtime)
    if not luaentity._task_queue or #luaentity._task_queue == 0 then return end
    -- Execute one action per tick to keep interrupt latency low.
    local task = table.remove(luaentity._task_queue, 1)
    local fn = ACTIONS[task.name]
    if fn then
        local ok, err = pcall(fn, luaentity, task.args)
        if not ok then
            say(luaentity, "action " .. task.name .. " 失敗: " .. tostring(err))
        end
    end
end

aibot.executor.ACTIONS = ACTIONS  -- exposed for planner (tool schema derivation)
aibot.executor.MAX_GO_TO_DISTANCE = MAX_GO_TO_DISTANCE
