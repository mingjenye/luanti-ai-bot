-- spec/chat_spec.lua — unit tests for src/chat.lua's @bot message router
--
-- Coverage: aibot.chat.handle_message — the pure-ish router that decides
-- how to respond to a chat message. UX edge cases (from 派大星's PR#2 review):
--   * empty command  ("@bot")
--   * super-long command (>500 chars)
--   * special characters (verifies whitelist executor keeps us safe from
--     shell-injection-shaped inputs; the LLM path itself is bypassed here)

local helpers = require("spec.helpers")

describe("aibot.chat.handle_message", function()
    local chat, sent_messages, planner_calls, executor_cancels

    before_each(function()
        sent_messages   = {}
        planner_calls   = {}
        executor_cancels = 0

        _G.core = helpers.fresh_core()
        _G.core.chat_send_player = function(name, msg)
            table.insert(sent_messages, { to = name, text = msg })
        end
        _G.core.register_chatcommand = function() end
        _G.core.register_on_chat_message = function() end

        _G.mobs = {}
        _G.aibot = {
            state = {
                bots_by_owner = {},
                get_bot = function(name) return _G.aibot.state.bots_by_owner[name] end,
                unregister_bot = function(name) _G.aibot.state.bots_by_owner[name] = nil end,
            },
            executor = {
                cancel = function() executor_cancels = executor_cancels + 1 end,
            },
            planner = {
                plan = function(le, cmd) table.insert(planner_calls, { le = le, cmd = cmd }) end,
            },
            config = {
                is_ready = function() return true end,
                reason_not_ready = function() return nil end,
            },
            http = {}, -- non-nil = HTTP API available
        }

        helpers.load_source("src/chat.lua")
        chat = _G.aibot.chat
    end)

    -- ─── not our message ──────────────────────────────────────────

    it("returns false for messages not starting with @bot", function()
        assert.is_false(chat.handle_message("henry", "hello world"))
        assert.is_false(chat.handle_message("henry", "@other 砍樹"))
        assert.are.equal(0, #sent_messages)
    end)

    -- ─── empty command ────────────────────────────────────────────

    it("prompts user when command is empty ('@bot' alone)", function()
        assert.is_true(chat.handle_message("henry", "@bot"))
        assert.are.equal(0, #planner_calls)
        assert.are.equal(1, #sent_messages)
        assert.matches("請輸入指令", sent_messages[1].text)
    end)

    it("prompts user when command is only whitespace ('@bot   ')", function()
        assert.is_true(chat.handle_message("henry", "@bot     "))
        assert.are.equal(0, #planner_calls)
        assert.are.equal(1, #sent_messages)
        assert.matches("請輸入指令", sent_messages[1].text)
    end)

    -- ─── length guard ─────────────────────────────────────────────

    it("rejects commands over MAX_COMMAND_LEN chars", function()
        local long = string.rep("a", chat.MAX_COMMAND_LEN + 100)
        assert.is_true(chat.handle_message("henry", "@bot " .. long))
        assert.are.equal(0, #planner_calls)
        assert.are.equal(1, #sent_messages)
        assert.matches("指令太長", sent_messages[1].text)
    end)

    it("accepts commands at exactly MAX_COMMAND_LEN chars", function()
        -- give this player a bot so we don't short-circuit on 'no bot'
        _G.aibot.state.bots_by_owner["henry"] = {
            luaentity = { object = {}, _owner = "henry" }, bot_id = "b",
        }
        local at_limit = string.rep("a", chat.MAX_COMMAND_LEN)
        assert.is_true(chat.handle_message("henry", "@bot " .. at_limit))
        assert.are.equal(1, #planner_calls)  -- planner called
    end)

    -- ─── special characters ───────────────────────────────────────
    -- Whitelist executor + no shell path means "; rm -rf /" is just a string
    -- forwarded to the LLM as prompt text. Verify the router does not crash
    -- and does not treat the input specially.

    it("safely handles shell-injection-shaped input", function()
        _G.aibot.state.bots_by_owner["henry"] = {
            luaentity = { object = {}, _owner = "henry" }, bot_id = "b",
        }
        assert.is_true(chat.handle_message("henry", "@bot ; rm -rf /"))
        assert.are.equal(1, #planner_calls)
        assert.are.equal("; rm -rf /", planner_calls[1].cmd)
    end)

    it("safely handles unicode and control characters", function()
        _G.aibot.state.bots_by_owner["henry"] = {
            luaentity = { object = {}, _owner = "henry" }, bot_id = "b",
        }
        assert.is_true(chat.handle_message("henry", "@bot 砍樹\0\r\n🌳"))
        assert.are.equal(1, #planner_calls)
        -- forwarded verbatim to planner (LLM prompt); no crash
    end)

    -- ─── no bot spawned ───────────────────────────────────────────

    it("tells user to /aibot spawn when they have no bot", function()
        assert.is_true(chat.handle_message("henry", "@bot 砍樹"))
        assert.are.equal(0, #planner_calls)
        assert.are.equal(1, #sent_messages)
        assert.matches("/aibot spawn", sent_messages[1].text)
    end)

    -- ─── stop shortcut ────────────────────────────────────────────

    it("cancels current task on '停' (bypasses LLM)", function()
        _G.aibot.state.bots_by_owner["henry"] = {
            luaentity = { object = {}, _owner = "henry" }, bot_id = "b",
        }
        assert.is_true(chat.handle_message("henry", "@bot 停"))
        assert.are.equal(1, executor_cancels)
        assert.are.equal(0, #planner_calls)  -- LLM not called
    end)

    it("cancels current task on 'stop' (case-insensitive, bypasses LLM)", function()
        _G.aibot.state.bots_by_owner["henry"] = {
            luaentity = { object = {}, _owner = "henry" }, bot_id = "b",
        }
        assert.is_true(chat.handle_message("henry", "@bot STOP"))
        assert.are.equal(1, executor_cancels)
        assert.are.equal(0, #planner_calls)
    end)

    -- ─── config / http not ready ──────────────────────────────────

    it("tells user when HTTP API not whitelisted", function()
        _G.aibot.state.bots_by_owner["henry"] = {
            luaentity = { object = {}, _owner = "henry" }, bot_id = "b",
        }
        _G.aibot.http = nil
        assert.is_true(chat.handle_message("henry", "@bot 砍樹"))
        assert.are.equal(0, #planner_calls)
        assert.matches("secure.http_mods", sent_messages[1].text)
    end)

    it("tells user when LLM config missing", function()
        _G.aibot.state.bots_by_owner["henry"] = {
            luaentity = { object = {}, _owner = "henry" }, bot_id = "b",
        }
        _G.aibot.config.is_ready = function() return false end
        _G.aibot.config.reason_not_ready = function() return "aibot.api_key 未設定" end
        assert.is_true(chat.handle_message("henry", "@bot 砍樹"))
        assert.are.equal(0, #planner_calls)
        assert.matches("api_key", sent_messages[1].text)
    end)
end)
