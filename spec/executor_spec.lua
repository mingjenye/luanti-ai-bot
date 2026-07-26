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
