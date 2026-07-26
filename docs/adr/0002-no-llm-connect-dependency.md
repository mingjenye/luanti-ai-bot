# ADR 0002: 不 fork / 不 depend on LLM Connect

**Status**: Accepted (2026-07-26)

## Context

ContentDB 上有 [LLM Connect](https://content.luanti.org/packages/H5N3RG/llm_connect/)，是連接 OpenAI-compatible LLM 的 Luanti mod。討論初期有兩個 bot 提議以 LLM Connect 為基礎：

- **Fork LLM Connect**（派大星初期提議）
- **Depend on LLM Connect as helper library**（frank 提議，做為 provider bridge）

## Decision

**兩種都不採用。自寫 ~50 行 Lua HTTP client，MVP 期間完全獨立於 LLM Connect。**

## Rationale

### LLM Connect 實際在做什麼

（根據 ContentDB 描述，未讀 code）

- 遊戲內 chat + Smart Lua IDE
- 玩家自然語言 → LLM 產生 **完整 Lua 程式碼** → runtime executor **直接 eval() 執行**
- Cold reload 機制（Run / Save / Enable on Restart）
- Capability-separated permissions（chat / dev / agents / root）

### 為什麼不 fork

1. **產品類型不同**：LLM Connect 是「in-game LLM 程式助手」（給 admin 用），我們要做的是「in-world AI agent」（給玩家娛樂）。fork 一整個 code base 沒實質幫助。
2. **Attack surface 差距極大**：LLM Connect 讓 LLM 執行任意 Lua code，我們要做的是白名單 whitelist executor（4-5 個固定 action）。fork 會繼承整個信任面。
3. **Upstream sync 成本**：LLM Connect 仍在活躍開發，fork 後跟上游變成常態負擔——不如避免。

### 為什麼不 depend on LLM Connect as library

1. **未驗證 LLM Connect exposes helper API 給其他 mod call**——ContentDB 描述沒明確提供 mod-to-mod API 契約。
2. 若沒 exposed API → 要 shim 它的 config 或塞我們自己的 config，加了依賴但沒省事。
3. 用戶負擔：想裝 aibot 就強制裝 LLM Connect（連 IDE / dev tool 一起）。
4. **YAGNI**：MVP 只需要「POST 到 OpenAI-compat endpoint」——~50 行 Lua，可控可測。

## Consequences

**正面**：
- 依賴最少：只需要 Luanti `http_api`
- Attack surface 由我們完全控制
- 可以獨立測試 provider 層

**負面**：
- 重複實作了 provider 選擇邏輯（但 50 行不算貴）
- 若未來要多 provider（Anthropic native、Gemini native、本地非 OpenAI 相容 model），要自己加 adapter

**Post-MVP 出路**：
- 若要多 provider → 抽 `ProviderAdapter` interface
- 若 LLM Connect 未來明確 export helper API + 文件穩定，可以重新評估作為 optional runtime backend
