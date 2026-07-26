-- aibot: LLM-controlled AI bot for Mineclonia
--
-- Architecture and design: see docs/SPEC.md
-- Verified API assumptions: see docs/spike-report.md
--
-- IMPORTANT: core.request_http_api() must be called from init.lua directly,
-- not inside a function. It returns nil if the mod is not listed in
-- secure.http_mods or secure.trusted_mods in minetest.conf.

local modname = core.get_current_modname()
local modpath = core.get_modpath(modname)

local http_api = core.request_http_api and core.request_http_api()

aibot = {
    modname = modname,
    modpath = modpath,
    http = http_api,
}

if not http_api then
    core.log("warning",
        "[aibot mod] core.request_http_api() returned nil. " ..
        "LLM features disabled. To enable, add 'secure.http_mods = aibot' " ..
        "to minetest.conf and restart the server."
    )
end

-- Load order matters: config/state first (no deps), executor before bot_entity
-- (bot_entity's do_custom references executor), planner before chat (chat calls it).
dofile(modpath .. "/src/config.lua")
dofile(modpath .. "/src/state.lua")
dofile(modpath .. "/src/inventory.lua")
dofile(modpath .. "/src/executor.lua")
dofile(modpath .. "/src/http.lua")
dofile(modpath .. "/src/planner.lua")
dofile(modpath .. "/src/bot_entity.lua")
dofile(modpath .. "/src/chat.lua")
dofile(modpath .. "/src/lifecycle.lua")

core.log("action",
    "[aibot mod] loaded (skeleton, implementation pending). " ..
    "HTTP API: " .. (http_api and "available" or "unavailable — see warning above")
)
