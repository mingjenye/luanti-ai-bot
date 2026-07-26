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

-- All bot-authored chat lines use the [AIBot] prefix (unified per DeepSeek
-- UX review; system messages in src/chat.lua use the same prefix).
local function say(luaentity, text)
    if luaentity._owner then
        core.chat_send_player(luaentity._owner, "[AIBot] " .. text)
    end
end
aibot.executor.say = say

-- Distance limit for drop_to_chest: LLM must have go_to'd the chest first.
local MAX_CHEST_DISTANCE = 5

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
    -- Invariant (frank safety review): only remove an item entity AFTER its
    -- ItemStack has been successfully added to the bot's inventory. On
    -- inventory-full, the item stays on the ground (no data loss).
    local pos = self.object:get_pos()
    local radius = tonumber(args.radius) or 3
    local filter = args.item_name  -- optional
    local objects = core.get_objects_inside_radius(pos, radius)
    local picked, skipped_full, skipped_filter = 0, 0, 0
    for _, obj in ipairs(objects) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "__builtin:item" then
            local stack = ItemStack(ent.itemstring or "")
            if stack:is_empty() then
                -- nothing
            elseif filter and stack:get_name() ~= filter then
                skipped_filter = skipped_filter + 1
            else
                local ok, _ = aibot.inventory.add_stack(self._bot_id, stack)
                if ok then
                    obj:remove()
                    picked = picked + 1
                else
                    skipped_full = skipped_full + 1
                end
            end
        end
    end
    local msg = string.format("撿了 %d 個 stack", picked)
    if skipped_full > 0 then msg = msg .. "，" .. skipped_full .. " 個裝不下" end
    if skipped_filter > 0 then msg = msg .. "，" .. skipped_filter .. " 個非目標物品" end
    if picked == 0 and skipped_full == 0 and skipped_filter == 0 then
        msg = "附近沒有可撿的物品"
    end
    say(self, msg)
end

ACTIONS.drop_to_player = function(self, args)
    -- Drops at the bot's current position. LLM is expected to have already
    -- go_to'd the owner. If bot is far from owner, we warn but still drop.
    local player = core.get_player_by_name(self._owner)
    if not player then
        say(self, "找不到主人，無法送物")
        return
    end
    local bot_pos = self.object:get_pos()
    local owner_pos = player:get_pos()
    if aibot.executor.distance(bot_pos, owner_pos) > 5 then
        say(self, string.format("我離主人 %d blocks（>5），先叫我 go_to 你再 drop 更好",
            math.floor(aibot.executor.distance(bot_pos, owner_pos))))
        -- fall through and drop anyway; owner may pick up on their way
    end
    local filter = args.item_name  -- optional
    local max_count = tonumber(args.count)
    local dropped = 0
    while true do
        if max_count and dropped >= max_count then break end
        local stack = aibot.inventory.take_stack(self._bot_id, filter)
        if not stack or stack:is_empty() then break end
        core.add_item(bot_pos, stack)
        dropped = dropped + 1
    end
    if dropped == 0 then
        if filter then
            say(self, "背包裡沒有 " .. filter)
        else
            say(self, "背包空的，沒東西送")
        end
    else
        say(self, "送了 " .. dropped .. " 個 stack")
    end
end

ACTIONS.drop_to_chest = function(self, args)
    if not (args.x and args.y and args.z) then
        say(self, "drop_to_chest 需要 x/y/z 座標")
        return
    end
    local chest_pos = {
        x = tonumber(args.x), y = tonumber(args.y), z = tonumber(args.z),
    }
    if not (chest_pos.x and chest_pos.y and chest_pos.z) then
        say(self, "座標無效")
        return
    end
    local bot_pos = self.object:get_pos()
    if aibot.executor.distance(bot_pos, chest_pos) > MAX_CHEST_DISTANCE then
        say(self, string.format("離 chest 太遠（>%d blocks），先 go_to 再 drop",
            MAX_CHEST_DISTANCE))
        return
    end
    local chest_inv = core.get_inventory({ type = "node", pos = chest_pos })
    if not chest_inv or not chest_inv:get_list("main") then
        say(self, "那個位置沒有 chest（或 chest 沒 main list）")
        return
    end
    local moved = 0
    while true do
        local stack = aibot.inventory.take_stack(self._bot_id)
        if not stack or stack:is_empty() then break end
        local leftover = chest_inv:add_item("main", stack)
        if leftover and not leftover:is_empty() then
            -- chest full: put back and stop
            aibot.inventory.add_stack(self._bot_id, leftover)
            break
        end
        moved = moved + 1
    end
    if moved == 0 then
        say(self, "背包空的，沒東西放")
    else
        say(self, "放了 " .. moved .. " 個 stack 進 chest")
    end
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
    local summary = aibot.inventory.summary(self._bot_id)
    say(self, "身上：" .. aibot.inventory.format_summary(summary))
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
aibot.executor.MAX_CHEST_DISTANCE = MAX_CHEST_DISTANCE
