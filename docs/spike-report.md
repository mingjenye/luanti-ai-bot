# Spike Verification Report

Static verification of the 3 spike risks listed in [SPEC.md](SPEC.md).

- **Date**: 2026-07-26
- **Verifier**: Claude (厭世草泥馬) via WebFetch
- **Scope**: static API verification against Luanti docs + VoxeLibre mcl_mobs docs (Mineclonia inherits from this lineage)
- **NOT verified**: runtime behavior on a live Mineclonia server. That requires Phase 2 (henry's test world or CI headless server).

## R1: `http_api` + `secure.http_mods` config

**Status**: ✅ Verified (with 1 critical gotcha)

### Findings

- Function: `core.request_http_api()` — no params, returns `HttpApi` table on success, `nil` on failure
- Config: `secure.http_mods = <modname>` in `minetest.conf` (or `secure.trusted_mods` for broader access)
- **CRITICAL GOTCHA**: `core.request_http_api()` MUST be called **directly from mod's `init.lua`**, NOT inside functions or event handlers. Late binding returns nil silently.
- Also fails silently if the Luanti binary is not built with curl support.
- All requests are async (callback-based via `HttpApi.fetch(request, callback)`).

### Request table fields

- `url` (required)
- `timeout` (seconds)
- `method` (`GET` / `POST` / `PUT` / `DELETE`, default `GET`)
- `data` (string or table with x-www-form-urlencoded encoding)
- `user_agent`
- `extra_headers` (table of `"key: value"` strings)
- `multipart` (boolean, POST only)

### Response fields (delivered to callback)

- `completed`, `succeeded`, `timeout` (booleans)
- `code` (HTTP status int)
- `data` (response body)

### Implication for `aibot`

- Get http handle in `init.lua`, pass to submodules via a mod-scoped table
- If handle is `nil` → log warning at mod load, disable LLM features gracefully; chat says `"[aibot] HTTP API not configured, see README"` on first `@bot` command
- LLM errors must be surfaced in chat, not silent
- Reference: [Luanti issue #14221](https://github.com/luanti-org/luanti/issues/14221) documents a common misconfiguration failure mode

## R2: `mcl_mobs` API for custom mob type

**Status**: ✅ Verified (via VoxeLibre docs; Mineclonia inherits this API from the shared MineClone2 → VoxeLibre → Mineclonia lineage, with minor variations)

### Findings

- Register: `mobs:register_mob(name, definition)` — name format `"aibot:companion"`
- Required def fields: `type` (use `"npc"`), `visual` (use `"mesh"` or `"sprite"`)
- Recommended: `textures`, `animation`, `initial_properties` (hp_min, hp_max)
- Spawn programmatically: `mcl_mobs:spawn(pos, name)`
- Owner binding: `self.owner = "player_name"` (built-in field, already used by tamed animals)
- State control: `self.state` (`"stand"` / `"walk"` / `"attack"` / `"runaway"` / `"flop"` / `"die"`)
- Order: `self.order` (`"follow"` or `"stand"`) for NPC behavior control
- Custom vars: attach directly to `self.xxx`; persist across ticks inside callbacks

### Pathfinding (critical for `go_to` action)

- Built-in: `pathfinding = 1` in def enables basic player-tracking pathfinding
- **Manual go-to-point**: `mobs:gopath(self, target, callback_arrived)` — pathfinds to `target` (Vector), invokes `callback_arrived` on arrival
- Quality: basic pathfinding is line-of-sight + wander; will fail on complex terrain (matches SPEC R2 risk)
- Advanced (`pathfinding = 2`) allows block break/place but requires `mobs_griefing` server setting — not appropriate for MVP

### Callbacks needed for `aibot`

- `do_custom(self, dtime)` — tick callback for our state machine (idle / planning / executing)
- `on_spawn(self)` — for spawn-intro-message logic
- `on_die(self, pos)` — cleanup (unbind from owner state map)
- `on_rightclick(self, clicker)` — future: open a bot inspector UI

### Implication for `aibot`

- Register mob `aibot:companion` in `src/bot_entity.lua`
- Owner binding via `self.owner`
- State machine lives in `do_custom` (`state = "idle" | "planning" | "executing"`)
- `go_to(x,y,z)` implemented via `mobs:gopath()`; on pathfinding fail → `say("我卡住了，繞不過去")`
- Detached inventory keyed by `bot_id` (unique per spawn), created in `src/state.lua`

## R3: LLM latency ↔ world state drift

**Status**: ⚠️ Requires runtime measurement (cannot verify statically)

### Static observations

- Typical round-trip:
  - OpenAI GPT-4o-mini: 0.5-2s
  - OpenAI GPT-4o: 1-3s
  - Anthropic Claude Sonnet: 1-4s
  - Local Ollama (7B): 0.5-2s
  - Local Ollama (30B+): 3-10s
- Luanti server tick: 20Hz → 1 second = 20 ticks; in a normal round-trip, world can change several blocks

### Mitigation designed in SPEC

- LLM tool calls should reference **target descriptions** (e.g., `{target: "nearest tree", radius: 20}`), NOT absolute coordinates
- mod re-resolves the target at execution time against current world state
- Bot state at LLM call time is included in prompt as a world snapshot; LLM plans intent, mod resolves specifics

### To verify at runtime (Phase 2)

- Measure actual round-trip on the specific provider + model chosen
- Test scenario: bot chases a moving target while LLM is planning; observe re-resolve behavior
- Test scenario: player types `@bot 停` during in-flight LLM call; verify interrupt reaches state machine before response arrives

## Overall

- **R1 and R2 are green** (with known gotchas documented, all designs adjusted accordingly)
- **R3 requires runtime** but the mitigation pattern (target descriptions + re-resolve) is sound; will validate in Phase 2

### Recommend

Proceed to implementation phase, in this order:

1. `src/bot_entity.lua` — mcl_mobs registration + skeleton `do_custom` state machine
2. `src/chat.lua` — `/aibot spawn` + `@bot` message routing
3. `src/http.lua` — LLM client using verified `core.request_http_api()` pattern
4. `src/executor.lua` — 9-action whitelist executor with re-resolve pattern
5. `src/planner.lua` — prompt building, tool schema, response parsing

## Sources

- [Luanti HTTP API docs](https://docs.luanti.org/for-creators/api/http-api/)
- [VoxeLibre mcl_mobs api.txt](https://github.com/VoxeLibre/VoxeLibre/blob/master/mods/ENTITIES/mcl_mobs/api.txt) (Mineclonia's mcl_mobs inherits this)
- [Luanti API index](https://api.luanti.org/)
- [Luanti Modding Book — Security](https://rubenwardy.com/minetest_modding_book/en/quality/security.html)
