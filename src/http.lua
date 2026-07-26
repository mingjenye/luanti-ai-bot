-- src/http.lua — LLM client (OpenAI-compatible chat completions)
--
-- Uses HttpApi handle obtained at init.lua load time (see R1 in spike-report).
-- All calls are async; caller supplies a `on_response(parsed, err)` callback.

function aibot.call_llm(messages, tools, on_response)
    if not aibot.http then
        on_response(nil, "HTTP API not available; add 'secure.http_mods = aibot' to minetest.conf")
        return
    end
    if not aibot.config.is_ready() then
        on_response(nil, aibot.config.reason_not_ready() or "config not ready")
        return
    end

    local body_table = {
        model    = aibot.config.model_name,
        messages = messages,
    }
    if tools and #tools > 0 then
        body_table.tools       = tools
        body_table.tool_choice = "auto"
    end

    local body_str = core.write_json(body_table)

    aibot.http.fetch({
        url            = aibot.config.endpoint_url,
        timeout        = aibot.config.request_timeout,
        method         = "POST",
        data           = body_str,
        user_agent     = "aibot/0.1 (luanti mod)",
        extra_headers  = {
            "Content-Type: application/json",
            "Authorization: Bearer " .. aibot.config.api_key,
        },
    }, function(res)
        if not res.completed then
            on_response(nil, "HTTP request did not complete")
            return
        end
        if res.timeout then
            on_response(nil, "HTTP timeout")
            return
        end
        if not res.succeeded or (res.code and res.code >= 400) then
            on_response(nil, "HTTP " .. tostring(res.code) .. ": " .. tostring(res.data or ""):sub(1, 200))
            return
        end

        local parsed = core.parse_json(res.data)
        if not parsed then
            on_response(nil, "response was not valid JSON")
            return
        end
        on_response(parsed, nil)
    end)
end
