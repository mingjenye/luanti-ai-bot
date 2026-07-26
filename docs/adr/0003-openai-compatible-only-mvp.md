# ADR 0003: MVP 只支援 OpenAI-compatible endpoint

**Status**: Accepted (2026-07-26)

## Context

LLM provider 有多種可能：

- OpenAI（GPT-4o、GPT-5 等）
- Anthropic（Claude Sonnet / Opus / Haiku）— 有自家原生 API 也有 `/v1` OpenAI-compat endpoint
- Google Gemini
- 本地 Ollama、llama.cpp、vLLM 等 — 多數支援 OpenAI-compat endpoint
- OpenRouter、Groq、Together 等 aggregator — 全走 OpenAI-compat

MVP 要選擇支援多少 provider。

## Decision

**MVP 只實作 OpenAI-compatible endpoint（`POST /v1/chat/completions` + function calling）**。用戶透過 `minetest.conf` 提供三個設定：

- `aibot.endpoint_url`（例：`https://api.openai.com/v1/chat/completions`）
- `aibot.api_key`
- `aibot.model_name`

## Rationale

### 為什麼夠用

OpenAI-compat 格式已是實質標準：

- **OpenAI** — 原生
- **Anthropic** — 走 `https://api.anthropic.com/v1/`（雖然 function calling schema 有些差異，多數 client 已抽象處理）
- **Ollama** — 走 `http://localhost:11434/v1/chat/completions`
- **OpenRouter / Groq / Together** — 全支援
- **本地 vLLM / llama.cpp server** — 支援

一份 client 打通 5 種主流部署方式。

### 為什麼不 MVP 就多 provider adapter

- 開發成本高、測試 matrix 爆炸
- 大多用戶只用一個 provider
- 抽 provider adapter 是「未來要多 provider 時才做」的重構——**YAGNI**

### 為什麼不 vendor-lock 到單一 provider

即使我們自己用 Claude 開發此專案，用戶不見得。強制單一 vendor 會限縮 mod 使用場景。

## Consequences

**正面**：
- 一份 code 支援 5+ 種 provider 部署方式
- 用戶自帶 API key，不用我們代管
- 本地模型（Ollama）能用 → 無 API 費用場景可行

**負面**：
- Function calling schema 各家有微差（OpenAI 是 `tools` + `tool_choice`；Anthropic native 有自己的 format，但 `/v1` endpoint 走 OpenAI schema）——實測若有相容問題要文件註明
- 沒法用 Anthropic prompt caching 等 vendor-specific 加值功能（post-MVP 加）

**Post-MVP 出路**：
- 若使用者反饋常用 provider 有 compat 問題 → 抽 `ProviderAdapter` interface，加 Anthropic native、Gemini native、其他 adapter
- 若成本問題大 → 加 Anthropic prompt caching adapter（低價高頻場景）
