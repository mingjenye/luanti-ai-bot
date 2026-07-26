-- spec/lifecycle_spec.lua — tests for player disconnect handling (M2c gap #7)
--
-- When a bot's owner disconnects, the bot should stop whatever it's doing
-- and return to idle. It should NOT despawn (the mob stays in the world;
-- SPEC out-of-scope excludes despawn-on-disconnect).

local helpers = require("spec.helpers")

describe("on_leaveplayer bot handling", function()
    local leave_handlers, cancel_calls

    before_each(function()
        leave_handlers = {}
        cancel_calls = {}
        _G.core = helpers.fresh_core()
        _G.core.register_on_leaveplayer = function(fn)
            table.insert(leave_handlers, fn)
        end
        _G.aibot = {
            state = {
                _map = {},
                get_bot = function(name) return _G.aibot.state._map[name] end,
                unregister_bot = function(name) _G.aibot.state._map[name] = nil end,
            },
            executor = {
                cancel = function(le) table.insert(cancel_calls, le) end,
            },
        }
        _G.mobs = {}
        helpers.load_source("src/lifecycle.lua")
    end)

    it("registers exactly one leaveplayer handler", function()
        assert.are.equal(1, #leave_handlers)
    end)

    it("cancels the leaving player's bot", function()
        local bot = { _owner = "henry", object = {} }
        _G.aibot.state._map["henry"] = { luaentity = bot, bot_id = "b" }
        leave_handlers[1]({ get_player_name = function() return "henry" end })
        assert.are.equal(1, #cancel_calls)
        assert.are.equal(bot, cancel_calls[1])
    end)

    it("is a no-op when the leaving player has no bot", function()
        leave_handlers[1]({ get_player_name = function() return "stranger" end })
        assert.are.equal(0, #cancel_calls)
    end)

    it("is a no-op when the bot has no live object", function()
        _G.aibot.state._map["henry"] = { luaentity = { _owner = "henry", object = nil }, bot_id = "b" }
        leave_handlers[1]({ get_player_name = function() return "henry" end })
        assert.are.equal(0, #cancel_calls)
    end)

    it("safely handles nil player", function()
        -- Should not crash. Nothing to cancel.
        leave_handlers[1](nil)
        assert.are.equal(0, #cancel_calls)
    end)

    it("safely handles player without get_player_name", function()
        leave_handlers[1]({})
        assert.are.equal(0, #cancel_calls)
    end)
end)
