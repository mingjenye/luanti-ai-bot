-- src/inventory.lua — per-bot detached inventory
--
-- Each bot has its own detached inventory keyed by `aibot_<bot_id>`. A
-- detached inventory is a Luanti primitive (docs: minetest.create_detached_inventory)
-- that lives outside any player. It's the right choice here because:
--   * bots aren't players and don't have player-inventory tabs
--   * detached inventories are per-name, so 1 bot = 1 inv, cleanly scoped
--   * they can be read/written by mod code without needing a formspec UI
--
-- We NEVER destroy an item entity without first successfully adding its
-- ItemStack into a detached inventory. This is the invariant that prevents
-- the data-loss bug pickup_nearby had before M2b.

aibot.inventory = {}

local INV_SIZE = 32  -- number of slots per bot inventory

local function inv_name_for(bot_id)
    return "aibot_" .. tostring(bot_id)
end
aibot.inventory.inv_name_for = inv_name_for

-- Create or replace a bot's inventory. Called at spawn time.
function aibot.inventory.create(bot_id)
    local name = inv_name_for(bot_id)
    core.create_detached_inventory(name, {
        allow_move = function() return 0 end,
        allow_put  = function() return 0 end,
        allow_take = function() return 0 end,
    })
    local inv = core.get_inventory({ type = "detached", name = name })
    if inv then
        inv:set_size("main", INV_SIZE)
    end
    return inv
end

-- Get the InvRef for a bot, or nil if not initialized.
function aibot.inventory.get(bot_id)
    local name = inv_name_for(bot_id)
    return core.get_inventory({ type = "detached", name = name })
end

-- Destroy a bot's inventory. Called on bot death (owner_offline retains it).
function aibot.inventory.destroy(bot_id)
    local name = inv_name_for(bot_id)
    if core.remove_detached_inventory then
        core.remove_detached_inventory(name)
    end
end

-- Add an ItemStack to a bot's inventory. Returns:
--   true  if the whole stack fit
--   false, leftover_stack  if only part (or none) fit
-- This is the invariant used by pickup: only remove the item entity AFTER
-- add_stack returned true (or partial fit + we handle leftover explicitly).
function aibot.inventory.add_stack(bot_id, itemstack)
    local inv = aibot.inventory.get(bot_id)
    if not inv then return false, itemstack end
    if not inv:room_for_item("main", itemstack) then
        local leftover = inv:add_item("main", itemstack)
        if leftover:is_empty() then
            return true
        end
        return false, leftover
    end
    inv:add_item("main", itemstack)
    return true
end

-- Take one stack matching `item_name` (or any stack, if item_name is nil)
-- out of the bot's inventory. Returns an ItemStack (may be empty).
function aibot.inventory.take_stack(bot_id, item_name)
    local inv = aibot.inventory.get(bot_id)
    if not inv then
        return ItemStack and ItemStack("") or nil
    end
    local list = inv:get_list("main") or {}
    for i, stack in ipairs(list) do
        if not stack:is_empty()
        and (not item_name or stack:get_name() == item_name) then
            inv:set_stack("main", i, ItemStack(""))
            return stack
        end
    end
    return ItemStack and ItemStack("") or nil
end

-- Return a table summary of the bot's inventory: { {name, count}, ... }.
-- Pure summary; does not mutate.
function aibot.inventory.summary(bot_id)
    local inv = aibot.inventory.get(bot_id)
    local summary = {}
    if not inv then return summary end
    local list = inv:get_list("main") or {}
    for _, stack in ipairs(list) do
        if not stack:is_empty() then
            table.insert(summary, {
                name  = stack:get_name(),
                count = stack:get_count(),
            })
        end
    end
    return summary
end

-- Human-readable formatter for summary — used by say() output.
function aibot.inventory.format_summary(summary)
    if #summary == 0 then return "空的" end
    local parts = {}
    for _, entry in ipairs(summary) do
        table.insert(parts, entry.name .. " x" .. entry.count)
    end
    return table.concat(parts, ", ")
end

aibot.inventory.INV_SIZE = INV_SIZE
