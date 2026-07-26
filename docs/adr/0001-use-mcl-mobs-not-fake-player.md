# ADR 0001: Bot 基底採用 `mcl_mobs` 自訂 mob type

**Status**: Accepted (2026-07-26)

## Context

專案需要一個「在遊戲世界中活動的角色」作為 AI bot 的具體化身。Luanti / Mineclonia 生態內有 4 種可選路徑：

1. **`mcl_mobs` 自訂 mob type**：Mineclonia 內建 mob 框架
2. **`mobs_redo` 自訂 mob type**：獨立 mob 框架，需額外 mod dependency
3. **Fake player**：以 Lua 建立「假裝是 player」的 entity
4. **從零 DIY entity**：直接用 `minetest.register_entity()` 從零寫

## Decision

**採用 `mcl_mobs` 自訂 mob type**。

## Rationale

| 面向 | mcl_mobs | mobs_redo | Fake player | DIY entity |
|---|---|---|---|---|
| Mineclonia 內建 | ✅ | ❌ 需額外裝 | ❌ | ❌ |
| Pathfinding | ✅ 基礎版 | ✅ 基礎版 | 走 player API | ❌ 自己寫 |
| Animation / HP / drops | ✅ | ✅ | 走 player API | ❌ 自己寫 |
| 跨版本相容性 | 高（跟隨 Mineclonia） | 中（獨立維護） | 低（player API 常變） | 依實作 |
| 實作成本 | 低（~50 行） | 低（~50 行）+ dep | 高 | 極高（500+ 行） |
| API 限制 | 沒有 player inventory tabs、無 crafting grid | 同 mcl_mobs | 幾乎無 | 無 |

**關鍵取捨**：
- **Fake player** 表面上功能最完整（能用 crafting grid、player inventory），但 Luanti 內部多處以 `is_player() == true` 檢查真實 player，維護 fake player 需要 hook 大量 `player_api` 內部，跨版本升級極痛苦。
- **`mobs_redo`** 是成熟框架，但在 Mineclonia 環境是重複輪子（`mcl_mobs` 就是 mcl fork 的 mob 系統），還加一個 mod dependency，用戶負擔增加。
- **DIY entity** 沒有現成框架代價，重造 pathfinding、animation、drops，估計 500+ 行 vs 坐在 `mcl_mobs` 上的 50 行。

MVP 不需要 player-only 能力（crafting grid、inventory tabs）。Post-MVP 若要 crafting，可用 Lua-side 呼叫 `minetest.get_craft_result()` 而非真的靠 crafting grid UI。

## Consequences

**正面**：
- 實作快、跨 Mineclonia 版本升級成本低
- 玩家看到「就是一隻 NPC」，符合認知
- Pathfinding、動畫、HP 都是別人維護

**負面**：
- Bot 沒有 player-style inventory tabs（用 detached inventory 補）
- `mcl_mobs` pathfinding 是基礎版，`go_to` 遇複雜地形會卡（列為 SPEC R2 spike 項）
- 綁 Mineclonia：搬到別的 subgame（Minetest Game、VoxeLibre）要重寫 mob 註冊層

**Post-MVP 出路**：
- 若要支援多 subgame → 抽 `BotEntityAdapter` interface，各 subgame 一個 implementation
- 若要 crafting grid → 走 detached inventory + `get_craft_result()` 模擬
