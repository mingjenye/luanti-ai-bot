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

-- Minimal ItemStack fake matching the surface our code uses.
-- Real ItemStack is provided by Luanti; tests can't call the C impl.
function M.fake_itemstack(name_or_empty)
    if type(name_or_empty) == "table" then return name_or_empty end
    local name, count = tostring(name_or_empty or ""), 1
    -- Accept forms: "", "modname:item", "modname:item 5"
    local n, c = tostring(name_or_empty or ""):match("^(%S+)%s+(%d+)$")
    if n and c then name, count = n, tonumber(c) end
    if name == "" then count = 0 end
    return {
        _name = name, _count = count,
        is_empty = function(self) return self._count == 0 or self._name == "" end,
        get_name = function(self) return self._name end,
        get_count = function(self) return self._count end,
    }
end

-- Install a global ItemStack constructor for tests that touch stack-using code.
function M.install_itemstack()
    _G.ItemStack = M.fake_itemstack
end

-- Build a stub aibot.inventory implementation for tests that exercise
-- executor actions without loading the real inventory module (which needs
-- core.create_detached_inventory to be truly functional).
function M.stub_inventory(initial_stacks)
    initial_stacks = initial_stacks or {}
    local contents = {}
    for _, s in ipairs(initial_stacks) do table.insert(contents, s) end
    local full = false
    return {
        _contents = contents,
        _set_full = function(self, v) full = v end,
        add_stack = function(bot_id, stack)
            if full then return false, stack end
            table.insert(contents, stack)
            return true
        end,
        take_stack = function(bot_id, filter)
            for i, s in ipairs(contents) do
                if (not filter) or (s.get_name and s:get_name() == filter) then
                    table.remove(contents, i)
                    return s
                end
            end
            return M.fake_itemstack("")
        end,
        summary = function(bot_id)
            local out = {}
            for _, s in ipairs(contents) do
                table.insert(out, { name = s:get_name(), count = s:get_count() })
            end
            return out
        end,
        format_summary = function(summary)
            if #summary == 0 then return "空的" end
            local parts = {}
            for _, e in ipairs(summary) do
                table.insert(parts, e.name .. " x" .. e.count)
            end
            return table.concat(parts, ", ")
        end,
        create = function() end,
        destroy = function() end,
    }
end

return M
