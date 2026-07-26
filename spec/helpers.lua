-- spec/helpers.lua — shared test scaffolding
--
-- Luanti mod code assumes global `core` and `aibot` tables. Tests build
-- minimal fakes for these before loading the code under test.

local M = {}

-- Build a fresh `core` mock. Individual tests override methods as needed.
function M.fresh_core()
    return {
        get_player_by_name = function() return nil end,
        find_nodes_in_area = function() return {} end,
        chat_send_player  = function() end,
        settings = { get = function() return nil end },
        parse_json = function(s)
            -- Only used by planner tests; keep this dumb — real JSON is injected
            -- via the `json_parser` argument to parse_response in tests.
            return nil
        end,
        write_json = function() return "{}" end,
        log = function() end,
        after = function() end,
    }
end

-- Build a minimal luaentity for executor tests.
function M.fresh_luaentity(overrides)
    local le = {
        _owner = "henry",
        _task_queue = {},
        object = {
            get_pos = function() return { x = 0, y = 64, z = 0 } end,
        },
    }
    for k, v in pairs(overrides or {}) do le[k] = v end
    return le
end

-- Reset globals and load a single source file. Callers set up `_G.core`,
-- `_G.aibot`, `_G.mobs` etc. as needed BEFORE calling this.
function M.load_source(path)
    local fn, err = loadfile(path)
    if not fn then error("failed to load " .. path .. ": " .. tostring(err)) end
    fn()
end

return M
