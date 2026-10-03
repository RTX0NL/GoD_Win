# `pocket_menu.rel` — shop tables (XD and Colosseum)

Both games' `pocket_menu.rel` hold the same four tables in one data section:
the mart list, the mart goods, the coupon-counter dialogue and the greeting
dialogue. The REL route tables point every copy of the module — each PAL
language copy is routed on its own — at `pocket_menu_typemap.json`, which
types all four and links each to its count word.

| XD label | Colosseum label | Struct | Record |
|---|---|---|---:|
| `shopData` | `MartStartIndexes` | `Shop` | 4 |
| `shopGoods` | `MartItems` | `ShopGoodsEntry` | 2 |
| `shopExchanger` | `CouponCounterDialog` | `ShopCouponDialog` | 0x4C |
| `shopSalesman` | `MartGreetings` | `ShopGreetingDialog` | 0x3C |

XD's labels are the game's own; Colosseum's come from the legacy GoD tool's
symbol list (`Colosseum/Resources/pocket_menu_symbols.json`), checked
against the readers below. Structs live in each game's
`Structs/entries/PocketMenuStructs.swift`.

**Verified.** Every `pocket_menu.rel` on all six discs (XD 1 + 5 PAL
copies + 1, Colosseum likewise) dumps all four tables as CSV and rebuilds
byte-identically.


Both games' `pocket_menu.rel` have the same 4 tables in one data section (section 3), same
sizes, same counts, and **byte-identical contents on US, PAL (all five language copies) and
JP** for the two tables below — in fact the two games' tables differ only in message ids.
XD readers found via the registered globals (XD r13 = 0x804EFE20): shopData `-0x75bc`,
shopExchanger `-0x75c4`, shopGoods `-0x75cc`, shopSalesman `-0x75d4`. Colosseum (r13 =
0x80480820, from `__init_registers`): its prolog registers idx 0 (coupon) at 0x80478E4C =
`-0x79d4(r13)`, idx 6 (greetings) at 0x80478E3C = `-0x79e4(r13)`, idx 4 (shop list) at
0x80478E54 = `-0x79cc(r13)`.

Both tables are addressed the same way: `row = shopData[shop].byte0` (the 4-byte shop list
record: +0 dialog-row index, +1 shop kind, +2 u16 first goods index), and then a message
slot by a `MENU_SHOP_MSG_CODE` / `MENU_COUPON_MSG_CODE`. `menuShopMain` dispatches on shop
kind (+1): 0/5/6 → `shopProc`, 1 → `vendingMachineProc`, 2/3/4 → `couponProc` (kind is passed
on as the coupon "mode"; 2 = memory-card path, 4 = Mt. Battle min-point path).

## Coupon counter — XD `shopExchanger` (idx 2/3), Colosseum `CouponCounterDialog` (idx 0/1)

- Record **0x4C**, count **3** in both games, every region; 3 × 0x4C = 0xE4 = chunk exactly.
  No relocations.
- XD accessor `getCouponMsgID__FPUci20MENU_COUPON_MSG_CODEiP16__va_list_struct`:
  `mulli r5, row, 0x4C; lbzx` +0 → out-byte; `lwzx (row*0x4C + 4) + code*4` → message id,
  filtered through `_msgIdWazaMachineChange` (swaps in a TM-specific variant). The out-byte is
  passed as `winMsgOpenWithSE`'s SE argument → window param 2 → `winMsgCtrl` → `GSmsgExec` arg 3
  → `MSG_TASK_WORK`+3 → the **MessageSFX search key** (see `message_se` above). Colosseum's
  mirror is `zz_0029fac_` (0x80029FAC), identical instruction for instruction; Colosseum's
  `zz_002c408_` (couponExchangeMain mirror) also reads +0 directly for its hard-coded GBA
  message 0x3D83.

| Off | Name | Type | Evidence (XD code site using that code) |
|---|---|---|---|
| 0x00 | `message_se_type` | uint8 | `lbzx` +0 → `winMsgOpenWithSE` SE arg (both games) |
| 0x01 | padding | 3 bytes | zero in all rows, both games; never read |
| 0x04 | `greeting_msg` | uint32 msg id | code 0, `couponProc` |
| 0x08 | `anything_else_msg` | uint32 | code 1, `couponProc` |
| 0x0C | `farewell_msg` | uint32 | code 2, `couponProc` |
| 0x10 | `choose_prize_msg` | uint32 | code 3 — not referenced as a constant in XD; text "What do you want to exchange your coupons for?" |
| 0x14 | `not_enough_coupons_msg` | uint32 | code 4, `couponExchangeMain` |
| 0x18 | `confirm_msg` | uint32 | code 5, `couponExchangeMain` (yes/no) |
| 0x1C | `received_msg` | uint32 | code 6, `couponExchangeMain` |
| 0x20 | `exchange_again_msg` | uint32 | code 7, `couponExchangeMain` (yes/no) |
| 0x24 | `cannot_afford_msg` | uint32 | code 8, `couponExchangeMain` |
| 0x28 | `no_room_msg` | uint32 | code 9, `couponExchangeMain` |
| 0x2C | `prize_list_msg` | uint32 | code 10, `couponListMain` |
| 0x30 | `explanation_msg` | uint32 | code 11, `couponExplanationMain` |
| 0x34 | `quantity_msg` | uint32 | code 12, `couponExchangeMain` → `setExplanationMsgID` |
| 0x38 | `quit_msg` | uint32 | code 13, `writeBackPcBox` (yes/no) |
| 0x3C | `link_off_msg` | uint32 | code 14 — no XD site; Colo text "Please turn off the GBA" |
| 0x40 | `transfer_msg` | uint32 | code 15, `writeBackPcBox` (yes/no, then `memCardSave`) |
| 0x44 | `retry_msg` | uint32 | code 16 — no XD site; Colo "Retry the transfer?/saving?" |
| 0x48 | `cancel_msg` | uint32 | code 17 — no XD site; Colo "The exchange will be canceled. OK?" |

(Names are from the strings each slot holds in both games — the codes are an enum whose
member names aren't in the binary; slot meaning is identical in both games, verified string by
string against XD US `pocket_menu.msg` and Colosseum US.) 0 = slot unused.

Rows and per-game difference:
- Row 0 = Mt. Battle coupon counter (kind 4) in both games; slots 13–17 = 0.
- Rows 1–2 are the link exchanges: Colosseum row 1 = GBA Game Pak coupons (kind 3), row 2 =
  memory-card coupons (kind 2), with real messages in 13–17. **XD keeps both rows but fills
  them with its row-0 ids and the value `1` in slots 13–17** (row 2: `1,0,1,1,1`). No XD `.msg`
  defines id 1, so those are placeholders for a dropped feature (XD's shop list still has
  kind-2/3 entries pointing at rows 2/1). Keep the column a plain uint32 so `1` round-trips.
- message_se_type: XD 2,0,0 ; Colosseum 2,0,0.
- Enum candidates: none; message ids stay uint32 (the code reads them with `lwzx`). If a
  MessageID abstraction exists, it fits every slot.

## Greetings — XD `shopSalesman` (idx 6/7), Colosseum `MartGreetings` (idx 6/7)

- Record **0x3C (60)**, count **6 in XD, 4 in Colosseum**, every region; 6 × 60 = 0x168 and
  4 × 60 = 0xF0, chunk exactly. No relocations.
- XD accessor `getMsgID__FPUci18MENU_SHOP_MSG_CODEiP16__va_list_struct` (same shape as the
  coupon one, `mulli 0x3C`); `shopBuyMain` also reads +0 directly for the hard-coded Battle CD
  sold-out message 0xC5EA. Colosseum mirror `zz_002a0b8_` (0x8002A0B8), identical.

| Off | Name | Type | Evidence (XD code site using that code) |
|---|---|---|---|
| 0x00 | `message_se_type` | uint8 | `lbzx` +0 → `winMsgOpenWithSE` SE arg (getMsgID, shopBuyMain) |
| 0x01 | padding | 3 bytes | zero everywhere; never read |
| 0x04 | `greeting_msg` | uint32 msg id | code 0, `shopProc`, `vendingMachineProc` |
| 0x08 | `anything_else_msg` | uint32 | code 1, `shopProc` |
| 0x0C | `farewell_msg` | uint32 | code 2, `shopProc`, `vendingMachineProc` |
| 0x10 | `confirm_purchase_msg` | uint32 | code 3, `shopBuyMain` |
| 0x14 | `thank_you_msg` | uint32 | code 4, `shopBuyMain`, `vendingMachineProc` |
| 0x18 | `not_enough_money_msg` | uint32 | code 5, `shopBuyMain`, `vendingMachineProc` |
| 0x1C | `no_room_msg` | uint32 | code 6, `shopBuyMain`, `vendingMachineProc` |
| 0x20 | `premier_ball_bonus_msg` | uint32 | code 7, `shopBuyMain` |
| 0x24 | `needs_cologne_case_msg` | uint32 | code 8, `shopBuyMain` ("can't sell you a SCENT…") |
| 0x28 | `sell_offer_msg` | uint32 | code 9 — **unread in XD** (no selling); text "We can pay you $…" |
| 0x2C | `unknown_sell_msg` | uint32 | code 10 — unread in XD; every row's id is an empty `{07}` string in both games |
| 0x30 | `cannot_buy_msg` | uint32 | code 11 — unread in XD; "we can't buy that item from you" |
| 0x34 | `quantity_buy_msg` | uint32 | code 12, `shopBuyMain` |
| 0x38 | `quantity_sell_msg` | uint32 | code 13 — unread in XD |

Rows: XD 0 = Poké Mart (se 2), 1 = vending machine (se 0; only slots 0,2,4,5,6 set — exactly the
codes `vendingMachineProc` uses — all pointing at empty strings), 2 = second clerk voice
(se 1), 3/4 = Herb Shop (two greetings, se 2), 5 = Battle CD shop (se 2). Colosseum 0 = Mart
(se 2), 1 = vending (se 0), 2 = clerk (se 1), 3 = Herb Shop (se 1). Colosseum's code mirrors
XD's; the selling slots (9–11, 13) are presumably live there (Colosseum allows selling) — the
Colosseum sell routine was not traced.

Differences: row count (6 vs 4), message ids, and row 3's SE type (XD 2, Colo 1). No
per-region or per-language difference in either game.





| Table | XD idx / game name | Colo idx / name | Record | Count | Bytes | Tiles |
|---|---|---|---|---|---|---|
| mart list | 0/1 `shopData` (global `-0x75bc(r13)`) | 4/5 `MartStartIndexes` (`-0x79cc(r13)`, Colo US r13 = 0x80480820) | 4 | XD 21, Colo 14 | 0x54 / 0x38 | exact |
| mart goods | 4/5 `shopGoods` (`-0x75cc(r13)`) | 2/3 `MartItems` (`-0x79dc(r13)`) | 2 | XD 184, Colo 122 | 0x170 / 0xF4 | exact |

No relocations in either. XD: both tables byte-identical on US, PAL (all five language copies)
and JP. Colosseum: mart list identical everywhere; goods identical US = JP, but **PAL reorders
two lists** (goods 74-82 / 89-97, the TM coupon/shop lists, and 103-105 at the head of the
coupon prize list) — same items, different order, in all five PAL language copies.

Readers (XD): `getGoodsList__FiPi` — `shopData + 4*shop` → `lhz +0x2` → walk `shopGoods`
from that index until a 0 entry (count returned); `menuShopMain` switches on `lbz +0x1`;
`menuShopDrawTitleText` indexes a 7-entry DOL title table by `+0x1`; `getMsgID`,
`getCouponMsgID`, `shopBuyMain` use `lbzx +0x0` as the dialog row (`mulli 0x3C` into
`shopSalesman`, `0x4C` into `shopExchanger`). Colosseum mirrors: `zz_002a0b8_`/`zz_0029fac_`
(+0), `zz_002d5d4_` (menuShopMain, +1), `zz_002c284_`, `zz_002c408_`, `zz_002ce6c_`,
`zz_002d154_` (+2 → goods walk), all instruction-for-instruction the XD shapes.

## Mart list record (4)

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `dialog_index` | uint8 | `lbzx +0x0` → row of the greetings table (`shopSalesman`/`MartGreetings`) for shop kinds, of the coupon-counter table (`shopExchanger`/`CouponCounterDialog`) for coupon kinds. XD 0-5, Colo 0-3 |
| 0x1 | `shop_kind` | uint8 | XD `menuShopMain`: 0/5/6 → `shopProc`, 1 → `vendingMachineProc`, else (2/3/4) → `couponProc` with the kind as its mode; title message = DOL table[kind] (0xC5E2, 0xC5E4, 0xC5E9 ×3, 0xC5F1, 0xC5E3), so kind < 7. Colo: 0 → shop, 1 → vending, ≥2 → coupon |
| 0x2 | `first_item_index` | uint16 | `lhz +0x2` → start index in the goods table (`getGoodsList` and the Colo mirrors) |

Enum candidate `ShopKind` (uint8, legacy `XGShopTypes`): Shop 0, VendingMachine 1,
MemoryCardCoupons 2 (legacy "bonusDiscCoupons"), GBACoupons 3 (Colo; legacy
"brokenCoupons"), PokeCoupons 4 (Mt. Battle), BattleCDs 5 (XD), HerbShop 6 (XD). Values seen: XD
0,1,2,3,4,5,6; Colo 0,1,2,3,4. `dialog_index` is an index, not a type: legacy's
`XGShopDialogTypes` enum just names the XD greeting rows (pokemart, vending, shop, herb, herb2,
battle CDs) and has no Colosseum meaning beyond 0-3 — keep it uint8.

XD extra: `menuShopMain` replaces shop **16** with `_getBattleDiskShopID` — one of the three
shops listed in DOL `lbl_803C25B4` = {16, 17, 18}, chosen by the Battle CD sold-out flags
(`deckDataVirtualDB_GetFlagData(item − 0x215)` on each list's goods) — so shops 16-18 must
stay CD shops and their goods must be Battle CD items.

## Mart goods (2)

A flat `uint16` array of **item data ids**, one zero-terminated run per shop; each run starts
right after the previous terminator and every run is referenced (XD shops 7/20 and 9/10/11,
Colo 11/12/13 share runs). `first_item_index` must point at a run start.

The value is **not** an `Items` row number. It goes to `itemDataBiosGetPtr` (XD) /
`zz_01440a0_` (Colo), which first maps it through a data-id → row table: XD common.rel
**`ValidItems`** (idx 68, 594 entries), Colosseum the DOL list at `lbl_803681E8` (548 entries).
Both are identity below 500; above it **XD row = id − 150, Colosseum row = id − 151**
(XD 0x1F4-0x251 → rows 350-443; Colo 0x1F4-0x223 → rows 349-396). Ids that map to 0 are invalid.
Marts use the high range: XD 0x1FF, 0x201-0x203, 0x217-0x233 (Battle CDs; 0x217 → row 385);
Colo 0x21F-0x221 (rows 392-394).

So the existing `Items` enum (row space) would name these wrong. Options: plain `uint16`, or a
generated per-game `ItemDataID` enum (row names re-keyed: id = row below 350/349, row + 150 / +151
above). Same applies to any other field that holds a script/data item id.

Legacy errors: its XD path (`scriptIndex`, +150 for rows ≥ 0x15E) matches the code. Its
**Colosseum** read path wraps the raw value as a row index (and the save comment says that's
deliberate), so the three Colosseum key-item goods (0x21F-0x221) display and save as rows
543-545 instead of 392-394; its `CMItems.scriptIndex` (rows ≥ 0x15E → +151) agrees with the DOL table
except for row 349, which the table maps from data id 500 but legacy leaves unshifted.
