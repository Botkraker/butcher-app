# Requests

One request per row, in build order. Claude takes the top `todo`, builds it, reviews it, marks it `built`, and commits.
You test it on the phone and change `built` to `done` (or write what is wrong in Notes).
Status: `todo` → `built` → `done` (or `skip`).

| # | Request | Status | Notes |
|---|---|---|---|
| 0 | Database v2 with migration, so the update keeps old data | built | Needed by 2 and 4. Run `neon_migration_002.sql` in Neon once. |
| 1 | Remove the بلاش (free) button | built | Old بلاش sales stay in history. |
| 2 | Credit (كريدي): pick or type the person's name, and the money. Balance per person, and paying back. | built | A credit sale asks for the name after the amount. |
| 3 | Voice input (Tunisian) | built | No offline Whisper on this phone. Uses the phone's own voice typing (ar-TN) on the 🎤 button; needs Google voice typing, usually needs internet. |
| 4 | Personal spending (مصروف الدار): money taken from the till, with optional details | built | Saved in `cash_moves` as a negative amount. |
| 5 | Supplier purchases (الشراء): item, kg, price per kg, cost, money given. Suggests old items and fills their last kg and price. | built | Also "pay only" for paying an old debt. Shows what you still owe. |
| 7 | Arrange the products yourself (order used in بيعة and السلعة) | built | السلعة → رتّب. The order stays on the phone; it is not sent to Neon. |
| 8 | Move to Flutter, same app, and let Claude test it | built | `flutter/`. 49 tests on the PC + screen images. Run: see `flutter/README.md`. Sync runs while the app is open (no background). |
| 9 | Sync with Neon both ways (in and out) | built | Run `app/neon_migration_003.sql` in Neon once. New phone: old data comes back. |
| 6 | Dashboard (الملخّص): filter by days, products grouped with kg and money | built | Placeholder. To discuss with a data scientist. |

## Phone test steps
Build with Run ▶ on the same PC. Do not uninstall. Then:
- **0.** Open البيعات: old sales are still there.
- **1.** بيعة → product: no بلاش button. ريميز still asks for kg.
- **2.** بيعة → product → amount → كريدي → كمّل → type or pick a name → سجّل. Open الكريدي: the person owes that amount. Tap the person → type an amount → خلّص: the balance goes down. Undo the credit sale in بيعة: the debt goes away.
- **3.** On any name or details screen, press 🎤 and speak. The words appear in the box. If the phone says no voice, the button shows a message and nothing breaks.
- **4.** مصروف الدار → amount → كمّل → details (or none) → سجّل. فسّخ removes the last one.
- **5.** الشراء → type a new item → كمّل → kg, price, money given → سجّل. Come back, type the first letters: the item is suggested. Tap it: the last kg and price are filled in. Change kg, save. Next time the new kg is filled in. "خلّص برك" records money given without an item.
- **6.** الملخّص → اليوم / 3 أيام / جمعة / شهر change the numbers. "فلوس الكاسة" = sales not on credit + credit paid back − money given to the supplier − house spending.
- **7.** السلعة → رتّب → tap a product (it turns black) → tap the place you want. It moves there. خلاص. Open بيعة: same order. Close and reopen the app: the order stays.
- **Sync.** After running the Neon SQL, press جرّب الانترنت → ابعث الكل توا: it says OK.

## Backlog (from the team review, not yet asked for)
- Local backup file of the phone database
- Stock count and daily closing (cash counted)
- Waste entry
- Merge the duplicate products (فيلي, كمونية بقري)
