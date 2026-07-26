-- spec/planner_spec.lua — unit tests for src/planner.lua
--
-- Coverage: aibot.planner.parse_response — takes an OpenAI-compat chat
-- completion payload and returns a list of { name, args } tool calls.
-- This is a pure function; no side effects, no engine calls.

local helpers = require("spec.helpers")

describe("aibot.planner.parse_response", function()
    local aibot_local

    before_each(function()
        _G.core = helpers.fresh_core()
        _G.aibot = { executor = {}, planner = {} }
        _G.mobs = {}
        helpers.load_source("src/planner.lua")
        aibot_local = _G.aibot
    end)

    it("returns empty list for nil response", function()
        local calls = aibot_local.planner.parse_response(nil)
        assert.are.equal(0, #calls)
    end)

    it("returns empty list for non-table response", function()
        assert.are.equal(0, #aibot_local.planner.parse_response("not a table"))
        assert.are.equal(0, #aibot_local.planner.parse_response(42))
    end)

    it("returns empty list when choices is missing", function()
        assert.are.equal(0, #aibot_local.planner.parse_response({}))
    end)

    it("returns empty list when message is missing", function()
        assert.are.equal(0, #aibot_local.planner.parse_response({ choices = { {} } }))
    end)

    it("parses a single tool_call", function()
        local response = {
            choices = { {
                message = {
                    tool_calls = { {
                        ["function"] = {
                            name = "go_to",
                            arguments = '{"target":"nearest tree"}',
                        },
                    } },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response, function(s)
            if s == '{"target":"nearest tree"}' then return { target = "nearest tree" } end
        end)
        assert.are.equal(1, #calls)
        assert.are.equal("go_to", calls[1].name)
        assert.are.equal("nearest tree", calls[1].args.target)
    end)

    it("parses multiple tool_calls in order", function()
        local response = {
            choices = { {
                message = {
                    tool_calls = {
                        { ["function"] = { name = "say", arguments = '{"text":"hi"}' } },
                        { ["function"] = { name = "follow", arguments = "{}" } },
                        { ["function"] = { name = "stop", arguments = "{}" } },
                    },
                },
            } },
        }
        local parser = function(s)
            if s == '{"text":"hi"}' then return { text = "hi" } end
            return {}
        end
        local calls = aibot_local.planner.parse_response(response, parser)
        assert.are.equal(3, #calls)
        assert.are.equal("say",    calls[1].name)
        assert.are.equal("follow", calls[2].name)
        assert.are.equal("stop",   calls[3].name)
    end)

    it("accepts arguments already parsed as a table", function()
        local response = {
            choices = { {
                message = {
                    tool_calls = { {
                        ["function"] = { name = "go_to", arguments = { target = "owner" } },
                    } },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response)
        assert.are.equal(1, #calls)
        assert.are.equal("owner", calls[1].args.target)
    end)

    it("defaults args to empty table when parser fails", function()
        local response = {
            choices = { {
                message = {
                    tool_calls = { {
                        ["function"] = { name = "follow", arguments = "not json" },
                    } },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response, function() return nil end)
        assert.are.equal(1, #calls)
        assert.are.same({}, calls[1].args)
    end)

    it("falls back to say(content) when no tool_calls but content is present", function()
        local response = {
            choices = { { message = { content = "你好世界" } } },
        }
        local calls = aibot_local.planner.parse_response(response)
        assert.are.equal(1, #calls)
        assert.are.equal("say", calls[1].name)
        assert.are.equal("你好世界", calls[1].args.text)
    end)

    it("prefers tool_calls over content when both present", function()
        local response = {
            choices = { {
                message = {
                    content = "should be ignored",
                    tool_calls = { { ["function"] = { name = "stop", arguments = "{}" } } },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response, function() return {} end)
        assert.are.equal(1, #calls)
        assert.are.equal("stop", calls[1].name)
    end)

    it("skips tool_calls with missing name", function()
        local response = {
            choices = { {
                message = {
                    tool_calls = {
                        { ["function"] = { arguments = "{}" } },       -- no name
                        { ["function"] = { name = "",       arguments = "{}" } },   -- empty name
                        { ["function"] = { name = "follow", arguments = "{}" } },
                    },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response, function() return {} end)
        assert.are.equal(1, #calls)
        assert.are.equal("follow", calls[1].name)
    end)

    it("handles alternative shape: message.tool_calls[i].name directly", function()
        -- Some OpenAI-compat providers deliver a flatter shape.
        local response = {
            choices = { {
                message = {
                    tool_calls = { { name = "say", arguments = { text = "hi" } } },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response)
        assert.are.equal(1, #calls)
        assert.are.equal("say", calls[1].name)
        assert.are.equal("hi", calls[1].args.text)
    end)

    it("returns empty list when message is empty (no content, no tool_calls)", function()
        local response = { choices = { { message = { content = "" } } } }
        assert.are.equal(0, #aibot_local.planner.parse_response(response))
    end)

    -- ─── unknown tool names ───────────────────────────────────────
    -- Planner is a shape-transformer, not a security boundary. It passes
    -- unknown names through verbatim. The whitelist enforcement point is
    -- aibot.executor.queue (see executor_spec.lua). This test documents
    -- the intended architecture (per frank's PR#2 safety review).

    it("passes unknown tool names through unchanged (executor is the whitelist)", function()
        local response = {
            choices = { {
                message = {
                    tool_calls = { {
                        ["function"] = { name = "hack_admin", arguments = "{}" },
                    } },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response, function() return {} end)
        assert.are.equal(1, #calls)
        assert.are.equal("hack_admin", calls[1].name)
        -- executor.queue will reject this — see executor_spec.lua
    end)

    it("passes mixed known + unknown tool calls through in order", function()
        local response = {
            choices = { {
                message = {
                    tool_calls = {
                        { ["function"] = { name = "say",         arguments = "{}" } },
                        { ["function"] = { name = "delete_world", arguments = "{}" } },
                        { ["function"] = { name = "stop",        arguments = "{}" } },
                    },
                },
            } },
        }
        local calls = aibot_local.planner.parse_response(response, function() return {} end)
        assert.are.equal(3, #calls)
        assert.are.equal("say",          calls[1].name)
        assert.are.equal("delete_world", calls[2].name)
        assert.are.equal("stop",         calls[3].name)
    end)
end)
