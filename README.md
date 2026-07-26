# aibot

LLM-controlled AI bot for Mineclonia. Players instruct an NPC companion via natural language chat commands, and the bot executes bounded in-world actions (move, dig, pick up, drop).

**Status**: skeleton — spec approved, static API verification done. Implementation in progress. See [`docs/SPEC.md`](docs/SPEC.md) and [`docs/spike-report.md`](docs/spike-report.md).

## Requirements

- Luanti / Minetest 5.9+
- Mineclonia (uses `mcl_mobs` framework)
- Luanti binary built with curl support (for HTTP API)
- An OpenAI-compatible LLM endpoint + API key (OpenAI, Anthropic `/v1`, OpenRouter, or local Ollama)

## Installation

1. Clone this repo into your Luanti mods folder (or your world's `worldmods/`)
2. Enable `aibot` for your world
3. Edit `minetest.conf`, add:

   ```
   # Whitelist aibot for HTTP calls (required)
   secure.http_mods = aibot

   # LLM endpoint config (OpenAI-compatible)
   aibot.endpoint_url = https://api.openai.com/v1/chat/completions
   aibot.api_key = sk-...
   aibot.model_name = gpt-4o-mini
   ```

4. Restart the server.

## Usage (planned — not yet implemented in skeleton)

```
/aibot spawn         Spawn your AI bot at your feet.
@bot <指令>          Give a natural language instruction.
@bot 停              Interrupt the current task.
```

Example session:

```
Player: /aibot spawn
Bot:    我是你的 AI Bot，下指令請 @ 我。
Player: @bot 去砍 3 棵樹
Bot:    好，我去找樹。
        [bot walks off, chops trees, returns]
Bot:    砍完了，木頭掉在你腳邊。
```

## Config keys

| Key | Required | Default | Description |
|---|---|---|---|
| `secure.http_mods` | ✅ (must include `aibot`) | — | Luanti's mod HTTP whitelist |
| `aibot.endpoint_url` | ✅ | — | OpenAI-compat chat completions URL |
| `aibot.api_key` | ✅ | — | API key for the endpoint |
| `aibot.model_name` | ✅ | — | Model name (e.g. `gpt-4o-mini`, `claude-sonnet-4-5`) |
| `aibot.request_timeout` | ⬜ | 30 | HTTP timeout (seconds) |

## Provider examples

| Provider | `endpoint_url` | `model_name` |
|---|---|---|
| OpenAI | `https://api.openai.com/v1/chat/completions` | `gpt-4o-mini` |
| Anthropic | `https://api.anthropic.com/v1/chat/completions` | `claude-sonnet-4-5` |
| OpenRouter | `https://openrouter.ai/api/v1/chat/completions` | `openai/gpt-4o-mini` |
| Local Ollama | `http://localhost:11434/v1/chat/completions` | `llama3.1:8b` |

## Running tests

Unit tests use [busted](https://olivinelabs.com/busted/), the standard Lua test framework.

```sh
# One-time setup (Ubuntu / Debian)
sudo apt-get install lua5.3 luarocks
sudo luarocks install busted

# Run the suite
./scripts/run-tests.sh
# or
busted --verbose spec/
```

Tests cover the pure logic that does not depend on the Luanti runtime:
`aibot.executor.resolve_target` (R3 target-description resolution) and
`aibot.planner.parse_response` (OpenAI-compat tool_call parsing).

Runtime tests against a real Mineclonia server are separate and require
setting up a headless minetestserver — see the CI setup once M2d lands.

## Multi-agent workflow

This project is also an experiment in multi-agent AI development. See [`docs/SPEC.md`](docs/SPEC.md#multi-agent-workflow-留痕) for the collaboration receipt.

## License

TBD (will decide before v1 release).
