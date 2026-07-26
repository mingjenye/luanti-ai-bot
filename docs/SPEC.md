# Luanti AI Bot — MVP Spec

## 專案目標

**主目的（henry）**：以真實 Luanti mod 專案，實測 multi-agent 開發流程（bots 之間如何討論、決策、留痕、產出 artifact）。

**次目的（產品）**：Mineclonia 上一個 AI bot mod，讓玩家用自然語言指揮一隻 NPC 執行遊戲內動作（走路、砍樹、撿物、送物）。

## MVP 範圍

### In-scope

- 一個 Lua mod（`aibot`）掛在 Mineclonia 上
- 每個 player 可 spawn 1 隻 AI bot（一 bot 一主，1 player 上限 1 bot）
- Chat command 觸發：`/aibot spawn` 生 bot；`@bot <NL 指令>` 下任務
- LLM 走 OpenAI-compatible endpoint（BYO API key，`minetest.conf` 設定）
- Bot 具備 9 個 whitelist actions（見下）
- Bot 挖方塊 → 走正常 `dig_node` 掉落 pipeline（物品掉在地上）
- Bot 撿物品 → 儲存在自己的 detached inventory
- Bot 送物 → `drop_to_player` / `drop_to_chest`
- `@bot 停` 中斷任意進行中任務

### Out-of-scope（post-MVP）

- 多 bot per player、共享 bot、無主 bot
- Bot 之間協作
- Craft recipe / spawn egg（MVP 純 chat command）
- Bot GUI / inventory viewer
- 戰鬥、建造、紅石／機械類技能
- 多 LLM provider adapter（Anthropic native、Gemini native、本地非 OpenAI-compatible 模型）
- 大範圍 pathfinding（跨 chunk、爬複雜地形）
- 中文以外的 UX 文案

## 架構

```
[Player: chat "@bot 去砍 3 棵樹"]
       │
       ▼
[aibot mod (Lua) — 單一 mod]
   ├── ChatHandler：解析 @bot 訊息、路由到 owner 的 bot
   ├── PlanningClient：POST 到 OpenAI-compatible endpoint (~50 行 Lua HTTP)
   ├── ToolCallExecutor：驗證 LLM 回的 JSON tool call、白名單校驗
   ├── BotEntity：mcl_mobs 註冊的自訂 mob type，狀態機
   └── DetachedInventory：bot 個人 inventory（不是 player inventory）
       │
       ▼
[Mineclonia / Luanti engine]
```

**明確不採用的設計**（見 ADR）：
- 不 fork / 不 depend on LLM Connect（[ADR-0002](adr/0002-no-llm-connect-dependency.md)）
- 不做 fake player entity（[ADR-0001](adr/0001-use-mcl-mobs-not-fake-player.md)）
- 不做獨立 MCP server（MVP 內建於 mod；post-MVP 再抽）

## Action set（whitelist）

LLM 只能回傳以下 tool call。任何未列出的 action 一律拒絕。

### 動作類（會改變 world state）

| Tool | 參數 | 描述 |
|---|---|---|
| `follow` | `{target: player_name}` | 跟隨玩家（idle 時的預設） |
| `stop` | `{}` | 中斷任意進行中任務，回 idle |
| `go_to` | `{x, y, z}` | 走到指定座標（受 pathfinding 限制） |
| `pickup_nearby` | `{radius: int, item_name?: string}` | 拾取周圍 item entity |
| `drop_to_player` | `{item_name?, count?}` | 走到 owner 腳邊掉物品 |
| `drop_to_chest` | `{x, y, z}` | 走到指定 chest 存放物品 |
| `say` | `{text: string}` | Bot 用 chat 發言 |

### 查詢類（唯讀）

| Tool | 參數 | 描述 |
|---|---|---|
| `query_recipe` | `{item_name: string}` | 回配方 JSON |
| `query_inventory` | `{}` | 回 bot 目前 detached inventory 內容 |

**LLM 呼叫模式**：Plan-then-execute。LLM 收到指令 → 回一串 tool call → mod 逐項執行、每項執行前用當下 world state 重新驗證座標／目標。

## MVP Acceptance Test

```
GIVEN Mineclonia server 已裝 aibot mod、`http_api` 白名單已加、OpenAI-compat endpoint 已設定
WHEN  玩家在 chat 輸入 `/aibot spawn`
THEN  bot 生在玩家腳前、nametag 顯示、自報身份：「我是你的 AI Bot，下指令請 @ 我」
AND   玩家輸入 `@bot 去砍 3 棵樹`
THEN  bot 走到最近 3 棵樹、依序砍倒（正常掉落）、撿取木頭、走回玩家腳邊、掉下木頭
AND   玩家隨時輸入 `@bot 停`
THEN  bot 立即中斷、回到 idle 跟隨狀態
```

## 技術風險（進 spike 驗證）

以下 3 項在動工 code 前必須先 spike 驗證，若不可行則 MVP 範圍要調整。

### R1: `http_api` 配置成本

**Risk**：Luanti `http_api` 對 mod 預設關閉；用戶要在 `minetest.conf` 加 `secure.http_mods = aibot` 才能運作。忘記 → mod 靜默失效（`minetest.request_http_api()` 回 `nil`）。

**Spike**：
- 驗證從 mod 的 `init.lua` 呼叫 `request_http_api()` 能拿到 handle
- 設計失敗時的錯誤處理：首次呼叫失敗要在 chat 明確報錯，不能靜默
- README 明確告知用戶如何設定

### R2: `mcl_mobs` pathfinding 品質

**Risk**：`mcl_mobs` 內建 pathfinding 是 line-of-sight + wander，不是 A*。`go_to(x, y, z)` 遇障礙可能卡住。

**Spike**：
- Mineclonia 測試世界放 20 blocks 距離 + 小坡 + 障礙物的 target，測 bot 能否到達
- 若不行 → MVP 範圍限制在「玩家 30 blocks 內、視線內」的 target
- 記錄實測結果，寫進 README known limitations

### R3: LLM latency ↔ world state 漂移

**Risk**：LLM call 1-5 秒 round-trip，回應時 bot 位置 / target 已變。tool call 帶回的座標可能失效。

**Spike**：
- 測 3 個 provider（OpenAI、Anthropic、Ollama）的 round-trip 延遲
- 實作「LLM plan → mod 用當下 state re-validate → 執行」pattern
- 不直接信任 LLM 回的座標；固定 target 用「target 描述」（例：「最近的樹」）而非死座標

### 其他實作 chore（不需 spike，但要在實作中處理）

- **中斷 state machine**：`stop` 到來時 bot 可能在 pathfinding / dig 動畫 / drop / query 任一 phase。設計乾淨的 cancel token / phase machine，各 phase 都能安全中斷。
- **Owner 離線**：owner disconnect 時 bot 進 idle、原地待命。
- **Bot 死亡 / 卡死**：加超時（30 秒無進度 → 自動 stop 並 say error）。

## 決策記錄（ADR）

- [ADR-0001](adr/0001-use-mcl-mobs-not-fake-player.md) — Bot 基底：`mcl_mobs` 自訂 mob type
- [ADR-0002](adr/0002-no-llm-connect-dependency.md) — 不 fork / 不 depend on LLM Connect
- [ADR-0003](adr/0003-openai-compatible-only-mvp.md) — MVP 只支援 OpenAI-compatible endpoint

## Multi-agent workflow 留痕

本 spec 由以下 bots 討論後由 **厭世草泥馬 (Claude)** 執筆：

- **厭世草泥馬**：主 coder + spec author（fleet ADR-004 routing）
- **frank (Codex)**：cross-vendor code review，提出 action set + Top 3 技術風險
- **派大星教授加博士先生 (DeepSeek)**：產品／UX sanity check，簡化 Q7 chat routing、Q6 加 intro-line

Handoff 走 **TaskEnvelope v0** 格式（見 fleet CLAUDE.md）：每次跨 bot 都帶 `task/goal/context` + `<@ID>` mention + status line。

## 下一步（henry 決策後）

1. henry review 本 spec，決策 accept / modify / reject
2. Accept → 進 spike phase：driver 三個 spike（R1/R2/R3），實測結果回饋 spec
3. Spike passed → 進 implementation phase
