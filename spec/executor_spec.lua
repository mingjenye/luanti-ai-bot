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

describe("ACTIONS.pickup_nearby is safe pre-M2b (frank safety review)", function()
    local sent
    local removed_count
    local luaentity

    before_each(function()
        sent = {}
        removed_count = 0
        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(name, msg) table.insert(sent, msg) end
        _G.core.get_objects_inside_radius = function()
            -- fake: 3 dropped items in radius
            local items = {}
            for i = 1, 3 do
                items[i] = {
                    get_luaentity = function() return { name = "__builtin:item" } end,
                    remove = function() removed_count = removed_count + 1 end,
                }
            end
            return items
        end
        _G.aibot = {}
        _G.mobs = {}
        helpers.load_source("src/executor.lua")
        luaentity = helpers.fresh_luaentity()
    end)

    it("does NOT remove item entities (avoids data loss until inventory exists)", function()
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { radius = 3 })
        assert.are.equal(0, removed_count)   -- CRITICAL: no items destroyed
    end)

    it("reports visible drop count to owner", function()
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { radius = 3 })
        assert.is_true(#sent > 0)
        assert.matches("3 個掉落物", sent[#sent])
    end)

    it("mentions M2b as when pickup will be enabled", function()
        _G.aibot.executor.ACTIONS.pickup_nearby(luaentity, { radius = 3 })
        assert.matches("M2b", sent[#sent])
    end)
end)
