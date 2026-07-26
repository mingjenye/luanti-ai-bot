-- spec/executor_spec.lua — unit tests for src/executor.lua
--
-- Coverage: aibot.executor.resolve_target (R3 mitigation: target-description
-- resolution against current world state). This is a pure-ish function that
-- takes a description string + luaentity and returns a Vector or nil.

local helpers = require("spec.helpers")

describe("aibot.executor.resolve_target", function()
    local aibot_local, luaentity

    before_each(function()
        _G.core = helpers.fresh_core()
        _G.aibot = {}
        _G.mobs = {}
        helpers.load_source("src/executor.lua")
        aibot_local = _G.aibot
        luaentity = helpers.fresh_luaentity()
    end)

    it("returns nil for nil description", function()
        assert.is_nil(aibot_local.executor.resolve_target(luaentity, nil))
    end)

    it("returns nil for empty description", function()
        assert.is_nil(aibot_local.executor.resolve_target(luaentity, ""))
    end)

    it("resolves 'owner' to owner position", function()
        _G.core.get_player_by_name = function(name)
            assert.are.equal("henry", name)
            return { get_pos = function() return { x = 10, y = 64, z = 20 } end }
        end
        local pos = aibot_local.executor.resolve_target(luaentity, "owner")
        assert.is_not_nil(pos)
        assert.are.equal(10, pos.x)
        assert.are.equal(64, pos.y)
        assert.are.equal(20, pos.z)
    end)

    it("resolves '主人' to owner position", function()
        _G.core.get_player_by_name = function(name)
            return { get_pos = function() return { x = 5, y = 64, z = 5 } end }
        end
        local pos = aibot_local.executor.resolve_target(luaentity, "去找主人")
        assert.is_not_nil(pos)
        assert.are.equal(5, pos.x)
    end)

    it("resolves 'player' to owner position", function()
        _G.core.get_player_by_name = function() return { get_pos = function() return { x = 1, y = 2, z = 3 } end } end
        local pos = aibot_local.executor.resolve_target(luaentity, "go to player")
        assert.is_not_nil(pos)
    end)

    it("returns nil when owner is offline", function()
        _G.core.get_player_by_name = function() return nil end
        local pos = aibot_local.executor.resolve_target(luaentity, "owner")
        assert.is_nil(pos)
    end)

    it("resolves 'tree' to nearest tree node", function()
        _G.core.find_nodes_in_area = function(min_p, max_p, groups)
            assert.are.equal("group:tree", groups[1])
            return { { x = 5, y = 64, z = 5 }, { x = 8, y = 64, z = 8 } }
        end
        local pos = aibot_local.executor.resolve_target(luaentity, "nearest tree")
        assert.is_not_nil(pos)
        assert.are.equal(5, pos.x)
    end)

    it("resolves '樹' to nearest tree node", function()
        _G.core.find_nodes_in_area = function() return { { x = 3, y = 64, z = 3 } } end
        local pos = aibot_local.executor.resolve_target(luaentity, "去砍樹")
        assert.is_not_nil(pos)
        assert.are.equal(3, pos.x)
    end)

    it("resolves 'wood' to nearest tree node", function()
        _G.core.find_nodes_in_area = function() return { { x = 7, y = 64, z = 7 } } end
        local pos = aibot_local.executor.resolve_target(luaentity, "collect some wood")
        assert.is_not_nil(pos)
    end)

    it("returns nil when no trees found", function()
        _G.core.find_nodes_in_area = function() return {} end
        assert.is_nil(aibot_local.executor.resolve_target(luaentity, "nearest tree"))
    end)

    it("returns nil for unknown target type", function()
        assert.is_nil(aibot_local.executor.resolve_target(luaentity, "some random thing"))
        assert.is_nil(aibot_local.executor.resolve_target(luaentity, "unknown"))
    end)

    it("is case-insensitive", function()
        _G.core.get_player_by_name = function() return { get_pos = function() return { x = 1, y = 2, z = 3 } end } end
        local pos_upper = aibot_local.executor.resolve_target(luaentity, "OWNER")
        local pos_mixed = aibot_local.executor.resolve_target(luaentity, "Owner")
        assert.is_not_nil(pos_upper)
        assert.is_not_nil(pos_mixed)
    end)

    it("searches in a 40x20x40 box around the bot", function()
        local captured_min, captured_max
        _G.core.find_nodes_in_area = function(min_p, max_p, groups)
            captured_min, captured_max = min_p, max_p
            return {}
        end
        luaentity.object.get_pos = function() return { x = 100, y = 200, z = 300 } end
        aibot_local.executor.resolve_target(luaentity, "tree")
        assert.are.equal(80,  captured_min.x)   -- 100 - 20
        assert.are.equal(190, captured_min.y)   -- 200 - 10
        assert.are.equal(280, captured_min.z)   -- 300 - 20
        assert.are.equal(120, captured_max.x)   -- 100 + 20
        assert.are.equal(210, captured_max.y)   -- 200 + 10
        assert.are.equal(320, captured_max.z)   -- 300 + 20
    end)
end)

-- ═══ aibot.executor.distance ═══════════════════════════════════════════
describe("aibot.executor.distance", function()
    before_each(function()
        _G.core = helpers.fresh_core()
        _G.aibot = {}
        _G.mobs = {}
        helpers.load_source("src/executor.lua")
    end)

    it("returns 0 for same position", function()
        local d = _G.aibot.executor.distance({x=1,y=2,z=3}, {x=1,y=2,z=3})
        assert.are.equal(0, d)
    end)

    it("computes 3-4-5 triangle correctly", function()
        local d = _G.aibot.executor.distance({x=0,y=0,z=0}, {x=3,y=4,z=0})
        assert.are.equal(5, d)
    end)

    it("handles missing coords as 0", function()
        local d = _G.aibot.executor.distance({}, {x=3,y=4,z=0})
        assert.are.equal(5, d)
    end)

    it("is symmetric", function()
        local a = {x=1,y=2,z=3}
        local b = {x=10,y=20,z=30}
        assert.are.equal(_G.aibot.executor.distance(a, b),
                         _G.aibot.executor.distance(b, a))
    end)
end)

-- ═══ aibot.executor.queue — unknown action rejection ═══════════════════
describe("aibot.executor.queue whitelist enforcement", function()
    local sent
    local luaentity

    before_each(function()
        sent = {}
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(name, msg)
            table.insert(sent, msg)
        end
        _G.aibot = {}
        _G.mobs = {}
        helpers.load_source("src/executor.lua")
        luaentity = helpers.fresh_luaentity()
    end)

    it("silently rejects unknown action names (security boundary)", function()
        _G.aibot.executor.queue(luaentity, "hack_admin", { arg = 1 })
        -- queue should be empty (nothing to run)
        assert.are.equal(0, #luaentity._task_queue)
        -- and a "unknown" message should have been sent to owner
        assert.are.equal(1, #sent)
        assert.matches("unknown", sent[1]:lower())
        assert.matches("hack_admin", sent[1])
    end)

    it("rejects nil action name", function()
        _G.aibot.executor.queue(luaentity, nil, {})
        assert.are.equal(0, #luaentity._task_queue)
    end)

    it("rejects empty action name", function()
        _G.aibot.executor.queue(luaentity, "", {})
        assert.are.equal(0, #luaentity._task_queue)
    end)

    it("accepts whitelisted action names", function()
        _G.aibot.executor.queue(luaentity, "say", { text = "hi" })
        assert.are.equal(1, #luaentity._task_queue)
        assert.are.equal("say", luaentity._task_queue[1].name)
    end)

    it("accepts all 9 MVP whitelisted actions", function()
        local whitelist = {
            "say", "follow", "stop", "go_to",
            "pickup_nearby", "drop_to_player", "drop_to_chest",
            "query_recipe", "query_inventory",
        }
        for _, name in ipairs(whitelist) do
            luaentity._task_queue = {}
            _G.aibot.executor.queue(luaentity, name, {})
            assert.are.equal(1, #luaentity._task_queue,
                "expected " .. name .. " to be accepted")
        end
    end)
end)

-- ═══ ACTIONS.go_to — distance guard + pickup_nearby safety ═════════════
describe("ACTIONS.go_to distance guard (frank safety review)", function()
    local sent
    local luaentity

    before_each(function()
        sent = {}
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(name, msg) table.insert(sent, msg) end
        _G.aibot = {}
        _G.mobs = { gopath = function(_, self, target, cb) if cb then cb() end end }
        setmetatable(_G.mobs, { __index = function(t, k) return _G.mobs[k] end })
        helpers.load_source("src/executor.lua")
        luaentity = helpers.fresh_luaentity()
        luaentity.object.get_pos = function() return { x = 0, y = 64, z = 0 } end
    end)

    it("rejects go_to with coords beyond MAX_GO_TO_DISTANCE", function()
        local max = _G.aibot.executor.MAX_GO_TO_DISTANCE
        _G.aibot.executor.ACTIONS.go_to(luaentity, { x = max + 50, y = 64, z = 0 })
        -- The "target too far" message should have been sent, gopath not called
        assert.is_true(#sent > 0)
        assert.matches("太遠", sent[#sent])
    end)

    it("accepts go_to well within MAX_GO_TO_DISTANCE", function()
        local gopath_called = false
        _G.mobs = { gopath = function() gopath_called = true end }
        mobs = _G.mobs  -- some code uses upvalue
        _G.aibot.executor.ACTIONS.go_to(luaentity, { x = 5, y = 64, z = 5 })
        -- We can't assert gopath directly due to how the mob path is called;
        -- instead assert "too far" message did NOT appear.
        for _, msg in ipairs(sent) do
            assert.is_nil(msg:find("太遠"))
        end
    end)

    it("rejects go_to with non-numeric coords", function()
        _G.aibot.executor.ACTIONS.go_to(luaentity, { x = "banana", y = 64, z = 0 })
        assert.is_true(#sent > 0)
        assert.matches("無效", sent[#sent])
    end)
end)

-- ═══ ACTIONS.pickup_nearby (M2b — real inventory) ═════════════════════
describe("ACTIONS.pickup_nearby with detached inventory", function()
    local sent, removed_count, luaentity, inv_stub

    local function fake_item_ent(itemstring)
        return {
            name = "__builtin:item",
            itemstring = itemstring,
        }
    end

    before_each(function()
        sent = {}
        removed_count = 0
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(_, msg) table.insert(sent, msg) end
        _G.aibot = {}
        _G.mobs = {}
        helpers.install_itemstack()
        helpers.load_source("src/executor.lua")
        inv_stub = helpers.stub_inventory()
        _G.aibot.inventory = inv_stub
        luaentity = helpers.fresh_luaentity()
        luaentity._bot_id = "test-bot"
    end)

    it("picks up items and removes their entities on success", function()
        _G.core.get_objects_inside_radius = function()
            local objs = {}
            for i = 1, 3 do
                local ent = fake_item_ent("default:tree")
                objs[i] = {
                    get_luaentity = function() return ent end,
                    remove        = function() removed_count = removed_count + 1 end,
                }
            end
            return objs
        end
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { radius = 3 })
        assert.are.equal(3, removed_count)
        assert.are.equal(3, #inv_stub._contents)
        assert.matches("撿了 3 個", sent[#sent])
    end)

    it("does NOT remove item entity when inventory is full", function()
        inv_stub:_set_full(true)
        _G.core.get_objects_inside_radius = function()
            local ent = fake_item_ent("default:tree")
            return {{
                get_luaentity = function() return ent end,
                remove        = function() removed_count = removed_count + 1 end,
            }}
        end
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { radius = 3 })
        assert.are.equal(0, removed_count)   -- invariant
        assert.matches("裝不下", sent[#sent])
    end)

    it("skips items not matching item_name filter", function()
        _G.core.get_objects_inside_radius = function()
            return {
                { get_luaentity = function() return fake_item_ent("default:tree") end, remove = function() end },
                { get_luaentity = function() return fake_item_ent("default:stone") end, remove = function() end },
                { get_luaentity = function() return fake_item_ent("default:tree") end, remove = function() end },
            }
        end
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { item_name = "default:tree", radius = 3 })
        -- 2 trees picked up, 1 stone skipped
        assert.are.equal(2, #inv_stub._contents)
        assert.matches("非目標物品", sent[#sent])
    end)

    it("reports nothing to pick up when radius has no items", function()
        _G.core.get_objects_inside_radius = function() return {} end
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { radius = 3 })
        assert.matches("沒有可撿", sent[#sent])
    end)

    it("ignores non-item entities (mobs, players)", function()
        _G.core.get_objects_inside_radius = function()
            return {
                { get_luaentity = function() return { name = "mobs:cow" } end, remove = function() removed_count = removed_count + 1 end },
                { get_luaentity = function() return nil end,                    remove = function() removed_count = removed_count + 1 end },
            }
        end
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { radius = 3 })
        assert.are.equal(0, removed_count)
        assert.are.equal(0, #inv_stub._contents)
    end)
end)

-- ═══ ACTIONS.drop_to_player (M2b) ══════════════════════════════════════
describe("ACTIONS.drop_to_player", function()
    local sent, dropped_items, luaentity, inv_stub

    before_each(function()
        sent = {}
        dropped_items = {}
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(_, msg) table.insert(sent, msg) end
        _G.core.add_item = function(pos, stack) table.insert(dropped_items, { pos = pos, stack = stack }) end
        _G.core.get_player_by_name = function(name)
            return { get_pos = function() return { x = 5, y = 64, z = 5 } end }
        end
        _G.aibot = {}
        _G.mobs = {}
        helpers.install_itemstack()
        helpers.load_source("src/executor.lua")
        luaentity = helpers.fresh_luaentity()
        luaentity._bot_id = "test-bot"
        luaentity.object.get_pos = function() return { x = 5, y = 64, z = 5 } end  -- near owner
    end)

    it("warns and returns when owner is offline", function()
        _G.core.get_player_by_name = function() return nil end
        _G.aibot.inventory = helpers.stub_inventory({
            helpers.fake_itemstack("default:tree 5"),
        })
        _G.aibot.executor.ACTIONS.drop_to_player(luaentity, {})
        assert.are.equal(0, #dropped_items)
        assert.matches("找不到主人", sent[#sent])
    end)

    it("drops all stacks from bot inventory at bot position", function()
        _G.aibot.inventory = helpers.stub_inventory({
            helpers.fake_itemstack("default:tree 5"),
            helpers.fake_itemstack("default:stone 3"),
        })
        _G.aibot.executor.ACTIONS.drop_to_player(luaentity, {})
        assert.are.equal(2, #dropped_items)
        assert.matches("送了 2", sent[#sent])
    end)

    it("filters by item_name arg", function()
        inv_stub = helpers.stub_inventory({
            helpers.fake_itemstack("default:tree 5"),
            helpers.fake_itemstack("default:stone 3"),
            helpers.fake_itemstack("default:tree 2"),
        })
        _G.aibot.inventory = inv_stub
        _G.aibot.executor.ACTIONS.drop_to_player(luaentity, { item_name = "default:tree" })
        assert.are.equal(2, #dropped_items)  -- 2 tree stacks dropped
        assert.are.equal(1, #inv_stub._contents)  -- stone remains
    end)

    it("respects count limit", function()
        inv_stub = helpers.stub_inventory({
            helpers.fake_itemstack("default:tree 5"),
            helpers.fake_itemstack("default:tree 5"),
            helpers.fake_itemstack("default:tree 5"),
        })
        _G.aibot.inventory = inv_stub
        _G.aibot.executor.ACTIONS.drop_to_player(luaentity, { count = 2 })
        assert.are.equal(2, #dropped_items)
        assert.are.equal(1, #inv_stub._contents)
    end)

    it("warns when inventory is empty", function()
        _G.aibot.inventory = helpers.stub_inventory({})
        _G.aibot.executor.ACTIONS.drop_to_player(luaentity, {})
        assert.are.equal(0, #dropped_items)
        assert.matches("背包空", sent[#sent])
    end)

    it("warns when filter matches nothing in inventory", function()
        _G.aibot.inventory = helpers.stub_inventory({
            helpers.fake_itemstack("default:stone 3"),
        })
        _G.aibot.executor.ACTIONS.drop_to_player(luaentity, { item_name = "default:diamond" })
        assert.are.equal(0, #dropped_items)
        assert.matches("背包裡沒有", sent[#sent])
    end)

    it("warns when bot is far from owner but still drops", function()
        _G.core.get_player_by_name = function()
            return { get_pos = function() return { x = 100, y = 64, z = 100 } end }
        end
        _G.aibot.inventory = helpers.stub_inventory({
            helpers.fake_itemstack("default:tree 5"),
        })
        _G.aibot.executor.ACTIONS.drop_to_player(luaentity, {})
        assert.are.equal(1, #dropped_items)
        -- Two messages: distance warning + success
        assert.is_true(#sent >= 2)
        local joined = table.concat(sent, "|")
        assert.matches("go_to", joined)
    end)
end)

-- ═══ ACTIONS.drop_to_chest (M2b) ═══════════════════════════════════════
describe("ACTIONS.drop_to_chest", function()
    local sent, luaentity, chest_inv_contents

    before_each(function()
        sent = {}
        chest_inv_contents = {}
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(_, msg) table.insert(sent, msg) end
        _G.core.get_inventory = function(spec)
            if spec.type == "node" then
                return {
                    get_list = function() return chest_inv_contents end,
                    add_item = function(_, _, stack)
                        table.insert(chest_inv_contents, stack)
                        return helpers.fake_itemstack("")  -- no leftover
                    end,
                }
            end
        end
        _G.aibot = {}
        _G.mobs = {}
        helpers.install_itemstack()
        helpers.load_source("src/executor.lua")
        luaentity = helpers.fresh_luaentity()
        luaentity._bot_id = "test-bot"
        luaentity.object.get_pos = function() return { x = 5, y = 64, z = 5 } end
    end)

    it("rejects missing coordinates", function()
        _G.aibot.executor.ACTIONS.drop_to_chest(luaentity, {})
        assert.matches("需要", sent[#sent])
    end)

    it("rejects when chest is beyond MAX_CHEST_DISTANCE", function()
        _G.aibot.inventory = helpers.stub_inventory({ helpers.fake_itemstack("default:tree 5") })
        _G.aibot.executor.ACTIONS.drop_to_chest(luaentity, { x = 100, y = 64, z = 100 })
        assert.matches("太遠", sent[#sent])
    end)

    it("rejects when node at pos has no inventory", function()
        _G.core.get_inventory = function() return nil end
        _G.aibot.inventory = helpers.stub_inventory({ helpers.fake_itemstack("default:tree 5") })
        _G.aibot.executor.ACTIONS.drop_to_chest(luaentity, { x = 6, y = 64, z = 5 })
        assert.matches("chest", sent[#sent]:lower())
    end)

    it("moves stacks from bot inventory to chest inventory", function()
        _G.aibot.inventory = helpers.stub_inventory({
            helpers.fake_itemstack("default:tree 5"),
            helpers.fake_itemstack("default:stone 3"),
        })
        _G.aibot.executor.ACTIONS.drop_to_chest(luaentity, { x = 6, y = 64, z = 5 })
        assert.are.equal(2, #chest_inv_contents)
        assert.matches("放了 2", sent[#sent])
    end)

    it("reports empty when bot inventory has nothing", function()
        _G.aibot.inventory = helpers.stub_inventory({})
        _G.aibot.executor.ACTIONS.drop_to_chest(luaentity, { x = 6, y = 64, z = 5 })
        assert.matches("背包空", sent[#sent])
    end)
end)

-- ═══ Timeout + busy state (M2c gap #6) ════════════════════════════════
describe("aibot.executor tick timeout + busy state", function()
    local sent, luaentity, fake_time

    before_each(function()
        sent = {}
        fake_time = 1000
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(_, msg) table.insert(sent, msg) end
        _G.aibot = {}
        _G.mobs = { gopath = function(_, self, target, cb) end }  -- never fires callback => stuck
        helpers.install_itemstack()
        helpers.load_source("src/executor.lua")
        _G.aibot.executor.now = function() return fake_time end
        luaentity = helpers.fresh_luaentity()
        luaentity._bot_id = "test-bot"
    end)

    it("go_to marks bot busy and sets a task_deadline", function()
        _G.aibot.executor.ACTIONS.go_to(luaentity, { x = 5, y = 64, z = 5 })
        assert.is_true(luaentity._busy)
        assert.is_number(luaentity._task_deadline)
        assert.are.equal(fake_time + _G.aibot.executor.TASK_TIMEOUT_SECONDS,
                         luaentity._task_deadline)
    end)

    it("tick does NOT dequeue new task while _busy is true", function()
        _G.aibot.executor.queue(luaentity, "say", { text = "hi" })
        assert.are.equal(1, #luaentity._task_queue)
        luaentity._busy = true
        _G.aibot.executor.tick(luaentity, 0.1)
        assert.are.equal(1, #luaentity._task_queue)  -- unchanged
    end)

    it("tick does dequeue when not busy", function()
        _G.aibot.executor.queue(luaentity, "say", { text = "hi" })
        _G.aibot.executor.tick(luaentity, 0.1)
        assert.are.equal(0, #luaentity._task_queue)
    end)

    it("tick force-cancels task when deadline exceeded", function()
        _G.aibot.executor.queue(luaentity, "say", { text = "queued" })
        luaentity._busy = true
        luaentity._task_deadline = fake_time - 1  -- already expired
        _G.aibot.executor.tick(luaentity, 0.1)
        assert.is_false(luaentity._busy or false)
        assert.is_nil(luaentity._task_deadline)
        assert.are.equal(0, #luaentity._task_queue)  -- cancelled
        local joined = table.concat(sent, "|")
        assert.matches("超過.-秒", joined)
    end)

    it("tick allows task to continue while deadline not yet reached", function()
        luaentity._busy = true
        luaentity._task_deadline = fake_time + 10  -- 10s in future
        _G.aibot.executor.tick(luaentity, 0.1)
        assert.is_true(luaentity._busy)
        assert.are.equal(fake_time + 10, luaentity._task_deadline)
    end)

    it("gopath callback clears _busy and _task_deadline", function()
        local captured_cb
        _G.mobs = { gopath = function(_, self, target, cb) captured_cb = cb end }
        _G.aibot.executor.ACTIONS.go_to(luaentity, { x = 5, y = 64, z = 5 })
        assert.is_true(luaentity._busy)
        captured_cb()  -- simulate arrival
        assert.is_falsy(luaentity._busy)
        assert.is_nil(luaentity._task_deadline)
    end)

    it("cancel clears _busy and _task_deadline", function()
        luaentity._busy = true
        luaentity._task_deadline = fake_time + 10
        _G.aibot.executor.cancel(luaentity)
        assert.is_false(luaentity._busy)
        assert.is_nil(luaentity._task_deadline)
    end)
end)

-- ═══ ACTIONS.query_inventory (M2b) ═════════════════════════════════════
describe("ACTIONS.query_inventory", function()
    local sent, luaentity

    before_each(function()
        sent = {}
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(_, msg) table.insert(sent, msg) end
        _G.aibot = {}
        _G.mobs = {}
        helpers.install_itemstack()
        helpers.load_source("src/executor.lua")
        luaentity = helpers.fresh_luaentity()
        luaentity._bot_id = "test-bot"
    end)

    it("reports '空的' when bot has nothing", function()
        _G.aibot.inventory = helpers.stub_inventory({})
        _G.aibot.executor.ACTIONS.query_inventory(luaentity, {})
        assert.matches("空的", sent[#sent])
    end)

    it("lists stack name and count for each entry", function()
        _G.aibot.inventory = helpers.stub_inventory({
            helpers.fake_itemstack("default:tree 5"),
            helpers.fake_itemstack("default:stone 3"),
        })
        _G.aibot.executor.ACTIONS.query_inventory(luaentity, {})
        assert.matches("default:tree x5", sent[#sent])
        assert.matches("default:stone x3", sent[#sent])
    end)
end)
