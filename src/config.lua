-- src/config.lua — read minetest.conf settings, expose readiness check

local S = core.settings

aibot.config = {
    endpoint_url    = S:get("aibot.endpoint_url") or "",
    api_key         = S:get("aibot.api_key") or "",
    model_name      = S:get("aibot.model_name") or "gpt-4o-mini",
    request_timeout = tonumber(S:get("aibot.request_timeout")) or 30,
}

function aibot.config.is_ready()
    return aibot.config.endpoint_url ~= "" and aibot.config.api_key ~= ""
end

function aibot.config.reason_not_ready()
    if aibot.config.endpoint_url == "" then
        return "aibot.endpoint_url 未設定"
    end
    if aibot.config.api_key == "" then
        return "aibot.api_key 未設定"
    end
    return nil
end
