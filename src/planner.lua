-- src/planner.lua — build prompt + tool schema, parse LLM response, dispatch to executor

aibot.planner = {}

-- OpenAI-compat function-calling tool schema. Keep in sync with executor's ACTIONS.
local TOOL_SCHEMA = {
    { type = "function", ["function"] = {
        name = "say",
        description = "Bot speaks a message to the owner in chat.",
        parameters = { type = "object",
            properties = { text = { type = "string" } },
            required   = { "text" },
        },
    }},
    { type = "function", ["function"] = {
        name = "follow",
        description = "Bot follows the owner.",
        parameters = { type = "object", properties = {} },
    }},
    { type = "function", ["function"] = {
        name = "stop",
        description = "Bot stops current activity and stands still.",
        parameters = { type = "object", properties = {} },
    }},
    { type = "function", ["function"] = {
        name = "go_to",
        description = "Bot walks to a target. Prefer a natural-language target description ('nearest tree', 'owner') so the mod can re-resolve against current world state.",
        parameters = { type = "object",
            properties = { target = { type = "string", description = "e.g. 'nearest tree', 'owner'" } },
            required   = { "target" },
        },
    }},
    { type = "function", ["function"] = {
        name = "pickup_nearby",
        description = "Bot picks up dropped items in a radius.",
        parameters = { type = "object",
            properties = {
                radius    = { type = "integer", description = "pickup radius in blocks (default 3)" },
                item_name = { type = "string",  description = "optional filter, e.g. 'default:tree'" },
            },
        },
    }},
    { type = "function", ["function"] = {
        name = "drop_to_player",
        description = "Bot walks to owner and drops items from its inventory.",
        parameters = { type = "object",
            properties = {
                item_name = { type = "string" },
                count     = { type = "integer" },
            },
        },
    }},
    { type = "function", ["function"] = {
        name = "drop_to_chest",
        description = "Bot walks to a chest position and stores items there.",
        parameters = { type = "object",
            properties = {
                x = { type = "number" }, y = { type = "number" }, z = { type = "number" },
            },
            required = { "x", "y", "z" },
        },
    }},
    { type = "function", ["function"] = {
        name = "query_recipe",
        description = "Look up how to craft an item.",
        parameters = { type = "object",
            properties = { item_name = { type = "string" } },
            required   = { "item_name" },
        },
    }},
    { type = "function", ["function"] = {
        name = "query_inventory",
        description = "Get bot's current inventory contents.",
        parameters = { type = "object", properties = {} },
    }},
}
aibot.planner.TOOL_SCHEMA = TOOL_SCHEMA

local SYSTEM_PROMPT = [[
You control an AI companion NPC in the Mineclonia (Minecraft-like) game.
Convert the player's natural-language command (usually in Chinese) into a
sequence of tool calls. Rules:
- Prefer target descriptions ("nearest tree", "owner") over absolute coordinates;
  the mod re-resolves targets against current world state.
- If the command is a question, use say() to reply.
- Keep responses short: 1-4 tool calls is normal.
- If you cannot fulfill the request, use say() to explain briefly.
]]

function aibot.planner.plan(luaentity, nl_command)
    if not luaentity or not luaentity._owner then return end
    local owner = luaentity._owner

    local pos = luaentity.object and luaentity.object:get_pos() or {x = 0, y = 0, z = 0}
    local snapshot = string.format(
        "bot position: (%d, %d, %d); owner: %s",
        math.floor(pos.x), math.floor(pos.y), math.floor(pos.z), owner
    )

    local messages = {
        { role = "system", content = SYSTEM_PROMPT },
        { role = "user",   content = "World state: " .. snapshot .. "\n\nCommand: " .. nl_command },
    }

    core.chat_send_player(owner, "[Bot] 收到，思考中…")

    aibot.call_llm(messages, TOOL_SCHEMA, function(response, err)
        if err then
            core.chat_send_player(owner, "[aibot] LLM 錯誤：" .. err)
            return
        end

        local choice = response.choices and response.choices[1]
        if not choice or not choice.message then
            core.chat_send_player(owner, "[aibot] LLM 回應格式異常")
            return
        end

        local msg = choice.message

        if msg.tool_calls and #msg.tool_calls > 0 then
            for _, call in ipairs(msg.tool_calls) do
                local fn_info  = call["function"] or call.func or {}
                local fn_name  = fn_info.name or call.name
                local args_raw = fn_info.arguments or call.arguments or "{}"
                local args     = type(args_raw) == "string" and core.parse_json(args_raw) or args_raw
                if type(args) ~= "table" then args = {} end
                aibot.executor.queue(luaentity, fn_name, args)
            end
        elseif msg.content and msg.content ~= "" then
            aibot.executor.queue(luaentity, "say", { text = msg.content })
        else
            core.chat_send_player(owner, "[aibot] LLM 沒回東西")
        end
    end)
end
