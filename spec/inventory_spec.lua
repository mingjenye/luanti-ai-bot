-- spec/inventory_spec.lua — unit tests for src/inventory.lua
--
-- Coverage focuses on the pure helpers (inv_name_for, format_summary).
-- The stateful methods (create/get/add_stack/take_stack) wrap Luanti's
-- detached inventory primitives; those are tested indirectly by the
-- executor action tests using stub_inventory.

local helpers = require("spec.helpers")

describe("aibot.inventory pure helpers", function()
    before_each(function()
        _G.core = helpers.fresh_core()
        _G.aibot = {}
        _G.mobs = {}
        helpers.install_itemstack()
        helpers.load_source("src/inventory.lua")
    end)

    describe("inv_name_for", function()
        it("prefixes the bot_id with 'aibot_'", function()
            assert.are.equal("aibot_bot-henry-123",
                _G.aibot.inventory.inv_name_for("bot-henry-123"))
        end)

        it("coerces non-string bot_ids to string", function()
            assert.are.equal("aibot_42",
                _G.aibot.inventory.inv_name_for(42))
        end)

        it("uses a unique namespace per bot_id", function()
            assert.are_not.equal(
                _G.aibot.inventory.inv_name_for("bot-a"),
                _G.aibot.inventory.inv_name_for("bot-b"))
        end)
    end)

    describe("format_summary", function()
        it("returns '空的' for empty summary", function()
            assert.are.equal("空的", _G.aibot.inventory.format_summary({}))
        end)

        it("formats single entry as 'name xCOUNT'", function()
            local s = _G.aibot.inventory.format_summary({
                { name = "default:tree", count = 5 },
            })
            assert.are.equal("default:tree x5", s)
        end)

        it("joins multiple entries with ', '", function()
            local s = _G.aibot.inventory.format_summary({
                { name = "default:tree",  count = 5 },
                { name = "default:stone", count = 3 },
                { name = "default:dirt",  count = 12 },
            })
            assert.are.equal("default:tree x5, default:stone x3, default:dirt x12", s)
        end)
    end)

    describe("INV_SIZE", function()
        it("is exposed as a public constant", function()
            assert.is_number(_G.aibot.inventory.INV_SIZE)
            assert.is_true(_G.aibot.inventory.INV_SIZE > 0)
        end)
    end)
end)
