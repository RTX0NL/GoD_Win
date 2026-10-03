# XD `common.rel` tables — the code-derived and legacy-declared set

Every `common.rel` table XD reads, or that the legacy GoD tool declared, with
a struct in `XD/Structs/entries/` (`CommonRelStructs.swift`,
`CommonRelCodeNamedStructs.swift`, `CommonRelLegacyStructs.swift`) and an
entry in `common_rel_typemap_{us,eu,jp}.json`. This file covers the tables
typed in October 2026; the accessor-derived layouts of the earlier set are
under `Documentation/Assembly Analysis/Data Structures/`.

**Method.** Chunk extents and counts come from the REL's own pointer indices
and count words (`scripts/analysis/rel_routes.py`). Every table is reached
from the DOL through a `relglobal.o` small-data word that the module's
`_prolog` fills, so the readers were found by that word's `r13` offset (US
`_SDA_BASE_` = `0x804EFE20`; a global at runtime address A is
`A − 0x804EFE20(r13)`). No other REL imports `common.rel`, so a table with no
such load is **read by nothing**. Game names are the `relglobal.o` symbols,
which the US/PAL maps misplace by a slot in places — where that happens the
section says so and the code decides. Every field was checked against every
row on the US, PAL and JP discs, and every table tiles its count exactly or
declares an explicit count.

**Verified.** A typed dump of `common.rel` reassembles byte-identically on
all three XD discs: 59 tables, each with a linked count chunk where the count
word equals the row count.

## Summary

| Table (label) | Game name | Struct | Record | Rows | Read by code |
|---|---|---|---:|---:|---|
| BattleBingo | `bingo_data` | `BattleBingo` (+ `BattleBingoPokemon`, `BattleBingoMysteryPanel`) | 0xB8 | 11 | yes |
| BattleCDs | `deckdata_virtual` | `BattleCD` (+ `BattleCDItem`) | 0x3C | 68 | yes |
| ContestData | `contest_data` | `ContestEffect` | 0x08 | 51 | no |
| ContestTypes | `contest_type` | — raw, all zero | — | 7 | no |
| PokespotAppData | `esabaappdata` | `PokespotAppearance` | 0x18 | 1 | yes |
| OrreColosseum | `fight_orre_data` | `OrreColosseumBattle` | 0x08 | 29 | no |
| BattleSideData | `fight_side_data` | `BattleSide` | 0x14 | 5 | yes |
| StoryProgressFlags | `flag_etc` | `StoryCheckpoint` | 0x20 | 101 | yes |
| FlagItemData | `flag_item` | `FlagItem` | 0x04 | — | no (Colosseum leftover) |
| FlagsMetaData | `flag_level` | — raw, runtime-filled | — | — | — |
| FlagPartyData | `flag_party` | `FlagParty` | 0x02 | — | no (Colosseum leftover) |
| FlagPokemonData | `flag_pokemon` | — raw, all zero | — | — | no |
| FlagValues | `flag_value` | `FlagValue` | 0x04 | — | no (Colosseum leftover) |
| RoomBGM | `floorsoundTbl` | `RoomSound` | 0x0C | — | yes |
| LegendaryPokemon | `legendPokemonData` | `LegendaryPokemon` | 0x02 | 22 | yes |
| MasterBallPokemon | `mball_data` | `BallSprite` (explicit count 13) | 0x02 | 13 | yes |
| MenuSFX / MessageSFX | `menu_se` / `message_se` | `MenuSounds` / `MessageSound` | | | yes |
| DeoxysFormes | `deoxys_pokemon_data` | `ColosseumFormatPokemonStat` | 0x11C | 5 | no |
| ShadowPokemonFilterData | `pokemon_dp_filter_data` | `HeartGaugeChange` (explicit count 6) | 0x01 | 6 | yes |
| PurificationChamberData | `relivehall_data` | `PurificationChamberSettings` | 0x4C | 1 | yes |
| Ribbons | `ribbon_data` | `Ribbon` | 0x08 | — | yes |
| SoundTest× 4 | | `SoundTestEntry` | | | yes |
| TableResData | `table_res` | `TableResEntry` | 0x04 | 8 | yes |
| TutorialData | `tutorialdata` | `TutorialEntry` (explicit count 13) | 0x02 | 13 | yes |
| MirorBData | `undertakerdata` | `MirorB` (+ `MirorBPlace`) | 0x6C | 1 | yes |
| WorldMapLocations | `worldmapXD_data` | `WorldMapLocation` | 0x24 | 18 | yes |

The struct name is authoritative where it differs from a name proposed in a
section below — the sections are the evidence the structs were written from.
`Items`-typed fields hold Items rows; a field holding an item **data id**
(Battle CD items, mart goods) is a plain `u16`, because above 500 a data id
and its row differ (see `pocket_menu.rel - Shop Tables.md`).

A finding that runs through these tables: the legacy GoD tool's layouts for
BattleBingo (0xB6, really 0xB8) and WorldMapLocations (declared with the
0x20 door struct, really 0x24) misread every row after the first.

## ContestData — `contest_data` (pointer index 4, count index 5 `contest_data_number`)

- Record 0x08, **51 rows** on US/PAL/JP; 51 × 8 = 0x198 = chunk span exactly. Chunk at 0x10E8 (sec 4) on all three.
- Byte-identical on all three regions.
- **No reader**: `contest_data` (-0x743C(r13)) and `contest_data_number` (-0x7440) are loaded nowhere in the DOL; no `contest`/`appeal` routine exists in the map. A Gen-3 leftover.
- Indexed by `Move.contest_appeal_jam_index` (Move +0x16): values 0…50 across the 375 moves (36 distinct) on every region — max 50 = count − 1, so the table is exactly that index's range.
- Identity: rows 1…48 are pokeemerald's `gContestEffects[0…47]` (appeal, jam) in order — row 1 = HIGHLY_APPEALING 40/0, 2 = 60/0, 3 = 80/0, … 9 = STARTLE_FRONT_MON 30/20, 19 = JAMS_OTHERS_BUT_MISS_ONE_TURN 40/40 — so row N = contest effect N−1, row 0 a null entry. Rows 49, 50 are 0/0.

| Off | Name | Type | Evidence |
|----:|------|------|----------|
| 0x0 | `appeal` | u8 | unread; data (pokeemerald `ContestEffect.appeal`, matches row-for-row) |
| 0x1 | `jam` | u8 | unread; data (pokeemerald `ContestEffect.jam`) |
| 0x2 | `unknown_0x02` | 5 × u8 (or padding) | 0 on every row, every region |
| 0x7 | `unknown_0x07` | u8 | 1 on rows 1–50, 0 on row 0 (a "valid" byte?); unread |

No enum fields. (pokeemerald's `effectType` byte has no counterpart here: bytes 2–6 are zero everywhere.)

## ContestTypes — `contest_type` (pointer index 6, count index 7 `contest_type_number`)

- Count **7** on US/PAL/JP; chunk span 0x10 (at 0x1280). 7 × 2 = 14 + 2 trailing bytes ⇒ **does not tile exactly**; the 2-byte remainder is the 4-byte alignment before the next symbol (`esabaappdata`, 0x1290). Record size 2 is inferred (16 / 7 only fits ≤ 2 with alignment); 1 is equally possible.
- **Every byte is zero** on all three regions.
- **No reader**: `contest_type` (-0x7444(r13)) / `_number` (-0x7448) are loaded nowhere.
- Probably one row per contest category (`ContestCategory`: None, Cool, Beauty, Cute, Smart, Tough = 6 values; Move +0x17 uses 0…5) plus one — but with all-zero content nothing confirms a layout.
- Recommendation: leave as raw `.bin` (or a 2-byte `unknown_0x00` u16 struct with an explicit count of 7). No enum candidates.

## PokespotAppData — `esabaappdata` (pointer index 8, count index 9 `esabaappdata_number`)

- Record 0x18, **1 row** on US/PAL/JP; tiles the 0x18 span exactly (chunk 0x1290). Byte-identical on all regions:
  `01f4 0bb8 01f4 0003 0002 001e 000a 0000 00000049 000004f2`
- Not an array in practice: a single parameter block for Pokéspot "appearance" (`app`) timing. Readers: `_esabaCallBackAppFunc__FUs15FootStepCounterl` and `_esabaAppearPokemon__FUs` (`lwz rX,-0x745C(r13)`); nothing else, and neither indexes it (always row 0).

| Off | Name (proposed) | Type | US value | Evidence |
|----:|------|------|------|----------|
| 0x00 | `appear_step_min` | u16 | 500 | `_esabaCallBackAppFunc`: `lhz 0x0` — while (spot flag +0x4 count + steps) < this, the count just accumulates, no appearance |
| 0x02 | `appear_step_guaranteed` | u16 | 3000 | `lhz 0x2` — count ≥ this ⇒ `_esabaAppearPokemon` unconditionally |
| 0x04 | `roll_step_interval` | u16 | 500 | `lhz 0x4` — between the two, the spot's +0x8 flag accumulates steps; each time it reaches this, a roll is made and the interval subtracted |
| 0x06 | `roll_chance_divisor` | u16 | 3 | `lhz 0x6` — roll succeeds when `HSD_Rand() % this == 0` (1 in 3) |
| 0x08 | `extra_list_spot_state` | u16 | 2 | `_esabaAppearPokemon`: `lhz 0x8`, compared with `GSflagGet(spot +0x14)`; equal (and the story check below passes) ⇒ `_esabaAppearPokemonSub` (the `esabapokemondata_EX` list — Bonsly 413 / Munchlax 414), else `_esabaAppearPokemonSub2` (the spot's own list) |
| 0x0A | `unknown_0x0A` | u16 | 30 | unread (equals the EX list's first rate, 30) |
| 0x0C | `unknown_0x0C` | u16 | 10 | unread (equals the EX list's second rate, 10) |
| 0x0E | `unknown_0x0E` | u16 | 0 | unread |
| 0x10 | `extra_list_story_step` | u32 | 73 | `_esabaAppearPokemon`: `lwz 0x10`, used as an index into `flag_etc` (StoryProgressFlags, 0x20 stride: `slwi r0,r31,5`), whose +0x8 value is compared with `GSflagGet(0x3C4)` (story progress); progress below it ⇒ always the normal list |
| 0x14 | `unknown_0x14` | u32 | 0x4F2 (1266) | unread; value lies in the Pokéspot flag-id range (0x4E0–0x586), likely a flag id |

Enum candidates: none (0x10 is a `StoryProgressFlags` row index). Side finding: the Pokéspot descriptor's +0x14 flag *is* read — by `_esabaAppearPokemon` (`GSflagGet`) and `_esabaCallBackAppFunc` (`GSflagTest`) — contrary to `EsabaData.md`'s "not read by any esaba* routine".

> **Naming caveat (applies to every section).** The SDA operands above are computed from the
> runtime address the `_prolog` actually stores each table into (not from the map), so the reader
> lists are code-derived. The `relglobal.o` names are map-derived and the maps can misplace names
> by a slot; each section says whether the code corroborates its name. For tables nobody reads,
> the map name is the only name and is corroborated (or not) by content alone.

## OrreColosseum — map name `fight_orre_data` (pointer index 32, count index 33)

- Record 0x08, **29 rows** on US/PAL/JP; 29 × 8 = 0xE8 = span exactly. Chunk 0x9378 US/JP, 0xB338 PAL (PAL's earlier tables are wider). Contents byte-identical on all regions.
- **No reader**: -0x74B4(r13) / -0x74B8(r13) are loaded nowhere in the DOL, and no REL imports `common.rel`. `menuOrreColosseum.o` doesn't touch it (it works off `_deckNumber`/`pOrre` instead). Name corroborated by content only.
- Row 0 is all zero; rows 1…28 hold 87…114 consecutively.

| Off | Name | Type | Evidence |
|----:|------|------|----------|
| 0x0 | `battle_id` | u32 | data: values 87–114 are exactly the 28 Orre Colosseum entries of the `Battles` table (`fightEncountData`) on all three regions — battle_kind 6 (round) ×3 then 7 (final), intro WZX 0x95/0x96/0x9C/0x9B repeating per set of four, i.e. 7 colosseums × 4 rounds; row 0 = none. Unread by code. |
| 0x4 | `unknown_0x04` | u32 | 0 on every row; unread |

Enum candidates: none (`battle_id` is a `Battles` row index). No regional difference.

## BattleSideData — `fight_side_data` (pointer index 34, count index 35)

- Record **0x14**, **5 rows** on US/PAL/JP; 5 × 0x14 = 0x64 = span exactly. Chunk 0x9460 US/JP, 0xB420 PAL. Byte-identical on all regions.
- Accessors (name corroborated by code): `fightSideDataBiosGetPtr` (`lwz -0x74C0(r13)` count bound, `mulli r0,r3,0x14`, `lwz -0x74BC(r13)`), the `fightSideDataBios{Get,Set}*` family, `fightSideDB_GetYrot`; dispatched by `fightSideGetStatus` / `fightSideSetStatus`. The row index is a battle side's `fightSideDataId` (`fightSideBiosGetFightSideDataId`, +0x0 of the runtime side).

| Off | Name (accessor) | Type | Evidence |
|----:|------|------|----------|
| 0x00 | `yrot` | u16 | `fightSideDataBiosGetYrot`/`SetYrot` (`lhz/sth 0x0`), `fightSideDB_GetYrot`; `fightSideGetFightTrainerGridParam` uses it as a boolean (≠0 ⇒ 1) — which way the side faces. Data: 0,0,1,0,1 |
| 0x02 | `unknown_0x02` | u16 | 0 everywhere; unread (alignment before the u32s) |
| 0x04 | `fight_trainer_status_menu_data_id` | 2 × u32 | `fightSideDataBiosGetFightTrainerStatusMenuDataId(ptr, i)`: `i < 2`, `lwz 0x4(ptr + i*4)`. Data: 0x44,0x45 (rows 1,3) / 0x42,0x43 (rows 2,4) |
| 0x0C | `fightout_pokemon_status_menu_data_id` | 2 × u32 | `fightSideDataBiosGetFightoutPokemonStatusMenuDataId(ptr, i)`: `i < 2`, `ptr + i*4 + 0xC`. Data: 0x38,0x41 / 0x37,0x40 |

Rows: 0 = null; 1 and 3 identical (yrot 0, player-side menus), 2 and 4 identical (yrot 1, opponent side). Array index = trainer slot on that side (0/1, matching `fightSideBiosGetFightTrainerPtr`'s `< 2` bound). Enum candidates: none (menu data ids).

## LegendaryPokemon — `legendPokemonData` (pointer index 72, count index 73)

- Record **0x02**, **22 rows** on US/PAL/JP; 22 × 2 = 0x2C = span exactly. Chunk 0x22794 US, 0x24754 PAL, 0x21548 JP. Contents byte-identical on all regions.
- A **flat u16 species list**, not a struct. Readers (name corroborated): `isLegend__7PokemonCFv` (`lwz -0x753C(r13)`, `lhzx r30,r3,r31` with `r31 += 2`, bounded by `*(-0x7540(r13))`; **stops early at a 0 entry**) and `menuCBRule_CheckLegendPokemon` (same list, `lhz 0x0(r5)`, `addi r5,r5,2`, `bdnz` over the count; returns 0 = rule violation if the species is listed, unless rule byte +0x18 == 1). `getLegendPokemonSize__4HeroCFv` counts party legendaries via `isLegend`.
- Data (XD species ids): MEW, MEWTWO, HO-OH, LUGIA, ENTEI, RAIKOU, SUICUNE, CELEBI, KYOGRE, GROUDON, LATIAS, LATIOS, REGICE, REGISTEEL, REGIROCK, RAYQUAZA, JIRACHI, DEOXYS, MOLTRES, ZAPDOS, ARTICUNO, **0**. The trailing 0 is a live sentinel row inside the count: `isLegend` returns false on reaching it.

| Off | Name | Type | Evidence |
|----:|------|------|----------|
| 0x0 | `species` | u16 → **`PokemonSpecies`** | `lhzx`/`lhz` compared to `getPokemonDataId` / `pokemonBiosGetPokemonDataId` |

Enum: `PokemonSpecies` (uint16, matches width). Keep the final 0 row (count includes it).

## MasterBallPokemon — map name `mball_data` (pointer index 74, count index 75) — actually **Poké Ball → menu sprite id**

- Record **0x02**, **13 rows**; 13 × 2 = 0x1A in a 0x1C span ⇒ **does not tile exactly**: 2 trailing zero bytes = 4-byte alignment before the next symbol. Chunk 0x227C0 US, 0x24780 PAL, 0x21574 JP.
- The legacy name is wrong: it is not a Pokémon list. Sole reader `mballBiosGetSpriteID(id)` (`lwz -0x7558(r13)` count bound, `rlwinm r0,r3,1,15,30` = id×2, `lhzx` from `-0x7554(r13)`; out of range ⇒ 0). Callers pass a ball: `getCatchBallID__11DarkPokemonCFv` in `PokemonBall__10menuPdaDPM…` and `DispList__14menuPdaDPMList…` (the Shadow Pokémon monitor's caught-ball icon), and `menuPokemonStatusDrawTitle` (the status screen's ball icon). *mball* = monster ball. Name corroborated by code.
- **Row index = ball item id** (0 none, 1 Master … 12 Premier), so the table has no key column; the row is the key.

| Off | Name | Type | Evidence |
|----:|------|------|----------|
| 0x0 | `sprite_id` | u16 | `mballBiosGetSpriteID` return value, drawn as a menu sprite; 0 = no icon (callers skip on 0) |

- **Regional difference:** US and PAL: `0, 399, 400, 401, 402, 391, 398, 397, 396, 395, 394, 393, 392`; **JP: every non-zero value +3** (`0, 402 … 395`) — JP's menu sprite list has three more entries ahead of the ball icons. A sprite-id enum would therefore have to be per region; leave as plain u16.
- Recommend `entryLabels`/documentation note that row N = `Items` raw value N (Master Ball = 1 … Premier Ball = 12). Rename suggestion: `PokeBallSprites`.

## ShadowPokemonFilterData — `pokemon_dp_filter_data` (pointer index 90, count index 91)

- Record **0x01**, **6 rows**; 6 bytes in an 8-byte span ⇒ **does not tile exactly** (2 trailing zero bytes, alignment). Chunk 0x45A54 US, 0x47A14 PAL, 0x44808 JP. Byte-identical on all regions: `ff ff fd fd ff ff` (+ `00 00`).
- Readers (name corroborated): `pokemonDpFilterDataBiosGetPtr(kind)` (count bound at `-0x7590(r13)`, `add r3, table, kind` — stride 1, from `-0x758C(r13)`) and `pokemonDpFilterDataBiosGetValue` (`lbz 0x0; extsb` ⇒ **signed**). Single caller `pokemonAddDpFormPokemonDpFilterId(pokemon, item, kind)`: for a Shadow Pokémon, value → float, adjusted per kind, scaled by the nature's rate (`pokemonSeikakuRateDataBios*`), then `pokemonAddDp` — i.e. it is the **base heart-gauge (DP) change per purification event**.
- **Row index = event kind** (from the branches in that routine and its callers):

| Row | Kind | Value | Code |
|---:|---|---:|---|
| 0 | battle (`ReliveFightout`) | −1 | caller `fightSeqFightOutPokemonDarkCheckAppear` |
| 1 | walking (`ReliveWalk`) | −1 | — |
| 2 | Call (`ReliveCall`) | −3 | value **overridden** by a constant (`lfs f31,-0x624C(r2)`); caller `fightSeqCallExec` |
| 3 | day care (`ReliveSodateya`) | −3 | caller `_sodateyaCallBackFunc` |
| 4 | cologne (`ReliveNadenade`) | −1 | multiplied by the item's `itemDataBiosGetBuff` (item kind must be 6); caller `menuUseItemScriptCologn` |
| 5 | (no nature rate) | −1 | value **overridden** by constant × `pokemonGetDp` |

| Off | Name | Type | Evidence |
|----:|------|------|----------|
| 0x0 | `dp_change` (base heart-gauge delta) | s8 | `lbz`+`extsb` in `pokemonDpFilterDataBiosGetValue` |

No enum on the field; the row index lines up with the Nature struct's five purify-multiplier columns (battle, walking, call, daycare, cologne). Rows 2 and 5 are effectively dead data (overridden in code).

## DeoxysFormes — map name `deoxys_pokemon_data` (pointer index 86, count index 87)

- Record **0x11C**, **5 rows** on US/PAL/JP; 5 × 0x11C = 0x58C = span exactly. Chunk 0x27B6C US, 0x29B2C PAL, 0x26920 JP. The 0x58C bytes are **byte-identical on all three regions**.
- **No reader**: -0x7454(r13) / -0x7458(r13) are loaded nowhere; no REL imports `common.rel`. The forme mechanics the game actually uses live in the DOL: `_menuCB_DeoxysParamCustom__FP7PokemonUs` reads a DOL table `lbl_8032EB88` (stride 0x14 = five u32 Atk/Def/SpA/SpD/Spe base stats per forme, indexed by `_menuCB_pokemonGetDeoxysSel`), and the models are the DOL's `deoxys_pokemon_pkx_data`. Name corroborated by content only.
- **It is a species record in Colosseum's `PokemonStat` layout (0x11C), not XD's (0x124).** Row 0 is all zero; rows 1–4 are four identical copies of **Normal-forme Deoxys** — stats 50/150/50/150/50/150, EVs Atk/SpA/Spe 1, nat. dex 386, Hoenn dex 202, name id 0x56A, Normal forme learnset (Leer, Wrap, Night Shade, Teleport, Knock Off, Pursuit, Psychic, Snatch, Psycho Boost…). None of the four carries forme-specific values, so the table is vestigial data (presumably meant as Normal/Attack/Defense/Speed).
- Field layout = Colosseum's `PokemonStat` struct (`Colosseum/Structs/entries/CommonRelStructs.swift`) offset-for-offset; every check below is from the data, nothing reads it:

| Off | Name (Colosseum `PokemonStat`) | Type | Row 1–4 value |
|----:|------|------|------|
| 0x00 | `exp_rate` | u8 → `ExpRate` | 5 (Slow) |
| 0x01 | `catch_rate` | u8 | 3 |
| 0x02 | `gender_ratio` | u8 → `GenderRatio` | 0xFF (genderless) |
| 0x03 | `unknown_1` | u8 | 5 (Colosseum: "5 for every real species") |
| 0x04 | `unknown_2` | u8 | 0 |
| 0x05 | padding | 1 | 0 |
| 0x06 | `base_exp_yield` | u16 | 215 |
| 0x08 | `base_friendship` | u16 | 0 |
| 0x0A | `height` | u16 | **507 = 5′07″ — US imperial encoding** (XD's own `pokemon_data` Deoxys is metric: 17) |
| 0x0C | `weight` | u16 | **1340 = 134.0 lb — imperial** (on PAL and JP too: the bytes are the same) |
| 0x0E | `cry_id` | u16 | 0x350 |
| 0x10 | `national_dex_index` | u16 | 386 |
| 0x12 | `unknown_3` | u16 | 386 |
| 0x14 | `pokedex_number` | u16 | 202 |
| 0x16 | `unknown_4` | u16 | 120 |
| 0x18 | `name_id` | u32 | 0x56A |
| 0x1C | `species_name_id` | u32 | 0x5DF |
| 0x20 | `unknown_5` | u32 | 0 |
| 0x24 | `unknown_6` (XD: seen flag) | u32 | 0x187 |
| 0x28 | `caught_flag_id` | u32 | 0x309 |
| 0x2C | `model_index` | u32 | 0x19A |
| 0x30 | `type_1`, `type_2` | u8 ×2 → `Type` | 0x0E, 0x0E (Psychic) |
| 0x32 | `ability_1`, `ability_2` | u8 ×2 → `Abilities` | 0x2E (Pressure), 0 |
| 0x34 | `learnable_tms` | 50 × bool | |
| 0x66 | `learnable_hms` | 8 × bool | |
| 0x6E | `egg_group_1`, `egg_group_2` | u8 ×2 → `EggGroup` | 0x0F, 0x0F (Undiscovered) |
| 0x70 | `wild_item_1`, `wild_item_2` | u16 ×2 → `Items` | 0, 0 |
| 0x74 | `egg_moves` | 8 × u16 → `Moves` | all 0 |
| 0x84 | `base_stats` | `PokemonBaseStats` (6 × u16) | 50/150/50/150/50/150 |
| 0x90 | `ev_yields` | `PokemonBaseStats` | 0/1/0/1/0/1 |
| 0x9C | `evolutions` | 5 × `PokemonEvolution` (6 B) | all 0 |
| 0xBA | `level_up_moves` | 20 × `PokemonLevelUpMove` (4 B: level, pad, `Moves`) | 12 used |
| 0x10A | padding | 2 | 0 |
| 0x10C | `sprites` | `PokemonSprite` (8 B) | color 1, face 0x181, body 0x0AAA1200 (XD's live Deoxys row: 0x1BF53200) |
| 0x114 | `shiny_sprites` | `PokemonSprite` | color 1, face 0x303, body 0x0AAB1200 |

- Recommendation: type the chunk with a struct identical to Colosseum's `PokemonStat` (e.g. an XD-engine copy named `PokemonStatColosseumFormat`, since each engine resolves its own structs) — enums `ExpRate`, `GenderRatio`, `Type`, `Abilities` (uint8), `EggGroup`, `Items`, `Moves`, `PokemonSpecies` (in evolutions) all match field widths, and XD's species/move/item numbering is Colosseum's for these values. Height/weight descriptions must say "imperial on every region" here. No regional difference.

## Colosseum's flag tables, carried over

module-0 relocations (none of these globals is imported by any REL).

Common finding for the five small flag tables: **XD's flag code never reads
four of them.** They are leftovers of Colosseum's flag system, whose 8-byte
descriptor carries indices into them (`+1` → `flag_value`, `+2` → `flag_item`,
`+3` → `flag_etc`, which in turn indexes `flag_party`). XD's 6-byte descriptor
dropped those index bytes (`+0x1` is 0 in all 2324 entries), so nothing
indexes the tables any more. The Colosseum reader is
`zz_Script_function_0x52_get_flag` (Colo US; really a debug "set flag and
its prerequisites" routine — it walks the `+6` chain and *writes*), with Colo
`r13` offsets `flag_value` -0x794c, `flag_item` -0x792c, `flag_party` -0x793c,
`flag_etc` -0x7924, `flag_level` -0x7934, `flag_data` -0x7884 (Colo `common.rel`
idx 16/10/18/22/12/54). Field names below that come from Colosseum code are
marked as such; for XD they stay `unknown_*` by the evidence standard.

All five are **byte-identical on US/PAL/JP**, and the four in section 3
(`.rodata`-like, sec3) sit at the same offsets (0xCA0–0xCFC) on all three.

## FlagItemData — `flag_item` (idx 48, count idx 49)

- Record 4 bytes × **2** rows (US/PAL/JP) = 8 = span to next symbol (sec3 0xCA0..0xCA8). Tiles exactly.
- Data: row0 `0000 0000`, row1 `0018 0000` (0x18 = `REVIVE` in XD's `Items`).
- XD: **unread** (no `r13` -0x74ec / -0x74f0 reference).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `unknown_0x00` | u16, `Items` | unread in XD. Colo: `lhzx (idx*4)+0` → 2nd arg of `zz_0129a78_(0, item, 1, -1)` |
| 0x2 | `unknown_0x02` | u16, `Items` | unread in XD. Colo: `lhzx (idx*4)+2` → 2nd arg of `zz_01299c8_(0, item, 1, -1)` (calls `itemGetStatus`; item-grant path) |

Enum candidate: both are `Items` (uint16) — width matches. Colo calls the
`+2` routine first, then `+0`; which one adds vs. removes isn't established.

## FlagsMetaData — `flag_level` (idx 50, count idx 51)

- Record 8 bytes × **4** rows = 0x20 = span (US sec4 0x10EFC, PAL 0x12EBC, JP 0x10E90). Tiles exactly.
- **All zero on disc in every region — it is RAM state, not data.** It is the
  flag system's per-bank descriptor array, filled at boot by `GSflagInit`.
- Readers: `GSflagGet`, `GSflagSet`, `GSflagClear` (`lwz -0x74f4(r13)`, index
  `bank*8` via `rlwinm r0,r0,29,27,28` / `slwi r0,r3,3`); writer `GSflagInit`.
  Count word (`-0x74f8`) is never read.

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `wordCount` | u32 | `GSflagInit` stores the bank's word count (args r4/r6/r8 → +0x8/+0x10/+0x18); `GSflagClear` loads `lwzx [bank*8]` as its loop bound |
| 0x4 | `bankPointer` | u32 (RAM pointer) | `GSflagInit` stores bank pointers (r3/r5/r7 → +0xC/+0x14/+0x1C); `GSflagGet/Set` load `+4` as the bank base; `GSflagClear` logs if it is 0 |

Row 0 = bank 0, never initialised (no flag uses bank 0). Recommendation: type
it (two u32) for readability, but it is pure runtime scratch — editing it does
nothing because `GSflagInit` overwrites rows 1–3 at boot.

## FlagPartyData — `flag_party` (idx 52, count idx 53)

- Record 2 bytes × **4** rows = 8 = span (sec3 0xCA8..0xCB0). Tiles exactly.
- Data: `00 00 | 01 00 | 01 01 | 00 01` — every combination of two booleans.
- XD: **unread** (-0x74fc / -0x7500 only appear as `r1` stack offsets in `cBingo`).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `unknown_0x00` | u8 (bool) | unread in XD. Colo: `flag_party[etc.byte0*2 + k]` for k = 0,1; non-zero ⇒ `zz_012f1fc_(k)` (party/member enable) |
| 0x1 | `unknown_0x01` | u8 (bool) | as above, k = 1 |

## FlagPokemonData — `flag_pokemon` (idx 54, count idx 55)

- Record **12** bytes × **4** rows = 0x30 = span (sec3 0xCB0..0xCE0). Tiles exactly.
- **All zero in every region** (and in Colosseum, whose copy is also 4 × 12 zeros).
- **Unread in both games** (XD -0x7504/-0x7508, Colo -0x7944/-0x7948: no references).
- Fields: `unknown_0x00`…`unknown_0x0B` (or 3 × u32). The 12-byte stride is
  only the span ÷ count; nothing confirms the internal split. Suggest leaving
  it as 12 bytes of `unknown` or as a raw `.bin`.

## FlagValues — `flag_value` (idx 56, count idx 57)

- Record 4 bytes × **7** rows = 0x1C = span (sec3 0xCE0..0xCFC). Tiles exactly.
- Data: `0, 0, 1, 1, 9, 0x3FF, 0`.
- XD: **unread** (-0x750c / -0x7510 no `r13` reference).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `value` | u32 | unread in XD. Colo: `lwzx flag_value[desc.byte1*4]` is the value the debug routine writes into the flag (clamped to the flag's width) |

Not really a struct — a plain u32 list. One column CSV (`value`) is fine.

**Naming caveat (all flag tables):** the `relglobal.o` names (`flag_item`,
`flag_party`, `flag_pokemon`, `flag_value`) are map names only — no XD code
reads those globals, so they can't be confirmed from XD code. What *is*
code-confirmed is the Colosseum side: the four Colo globals the debug routine
reads through the descriptor's index bytes hold exactly these byte patterns
(`0000 0000 0018 0000`, `0,0,1,1,9,0x3FF,0`, `00 00 01 00 01 01 00 01`), so
the role of each table is established independently of the map. `flag_level`
is code-confirmed in XD (`GSflagInit/Get/Set/Clear`).


## RoomBGM — `floorsoundTbl` (idx 64, count idx 65)

- Record **0xC** × **235** rows on US, PAL and JP = 0xB04 = span to next symbol
  (US sec4 0x1C5DC, PAL 0x1E59C, JP 0x1B390). Tiles exactly.
- **Byte-identical on all three regions.**
- Record type is the game's own: `floorsound_dd_` (from the mangled
  `_playSound__FP14floorsound_dd_` / `_playEnvSound__FP14floorsound_dd_`).
- Readers (all in `floorsound.o`): `floorSound_SearchTable` (`lwz -0x7524(r13)`
  table, `-0x7528(r13)` count, `mulli 0xC`; linear search for `+0x2 ==
  floorGetCurrent()`, resumable from a given row so a room can have several
  rows), `floorSound_playSound` and `floorSound_playEnvSound` (walk every
  matching row; first whose flag gate passes and which plays wins),
  `_playSound`, `_playEnvSound`. Called from
  `_floorInitializeCommon__FUi14FloorEnterMode` (`playEnvSound(1)`) and
  `floorReadScriptPostFunc` (`playEnvSound(0)`).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `envTiming` | u8 | `floorSound_playEnvSound(r3)` plays a row only when `+0 == r3`; called with 1 at floor init, 0 after the room script. `playSound` ignores it. Data: **1 on all 235 rows** |
| 0x1 | `volume` | u8 | volume arg (r5/r6) of `soundOpenPlay`, `soundOpenPlayFadeOutIn`, `soundOpenPlayEnvFadeOutIn`; compared against `GSsndGetVolume` and passed to `GSsndSetVolume`. Data: 127 on 234 rows, 80 on one |
| 0x2 | `roomID` | u16 | search key, compared to `floorGetCurrent()` (`getCurrentFloorID`). Data: 151 distinct values, every one a `room_id` in `Rooms` on all three discs. Not sorted; a room can have several rows (flag-gated variants) |
| 0x4 | `soundID` | u16 | id passed to `soundCheckEnv`, `GSsndCheckSE`, `soundGetBGMID` compare, `soundOpen*`; bounds-checked against `snd_data_number` (`-0x7400(r13)`, = `NumberOfSounds` idx 103, 1507). Data: 2…1486 — index into `SoundsMetaData` |
| 0x6 | `fadeInTime` | u16 | 2nd arg of `_soundOpenPlay` (via `soundOpenPlay`, `…FadeOutIn` r5, `…EnvFadeOutIn` r5). Data: 0 on all rows |
| 0x8 | `envFadeOutTime` | u16 | `_playEnvSound` only: r4 of `soundOpenPlayEnvFadeOutIn` → `_soundFadeout(time)`. (The BGM path hard-codes 0x1F4.) Data: 0 on 234, 500 on one |
| 0xA | `flagID` | u16 | `GSflagTest(+0xA)` must be true for the row to play; 0 = unconditional. Data: 0 on 138 rows, else `GeneralFlags` ids 1977–2309 |

Enum candidates: none of `Items`/`PokemonSpecies`/`Moves`. `roomID` would take
a room enum if one existed; `soundID` a sound-id enum. Which of BGM vs.
environment sound a row is depends on the sound itself (`soundCheckEnv`), not
on a field.


## Ribbons — `ribbon_data` (idx 100, count idx 101)

- Record **8** × **32** rows on US/PAL/JP = 0x100 = span (US sec4 0x45EF0, PAL 0x47EB0, JP 0x44CA4). Tiles exactly.
- Readers (module `ribbon`): `getRibbonCnt` (`lwz -0x75b8(r13)` → count),
  `getRibbonMsgID(i)` (`-0x75b4(r13)`, `slwi 3`, `lwz +4`; returns 0 when
  `i >= count`). Sole caller of both: `menuPokemonStatusDrawRibbon`, which first
  maps the ribbon index through a DOL table at `lbl_80322948` — `-1` means
  "use `getRibbonMsgID`", 0–6 means an ExRibbon slot (`exribbonGetNo` →
  `lbl_803229C8` message table).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `unknown_0x00` | u16 | **unread** by any XD code. US 0x00FC…0x011B (252–283, +1 per row); PAL and JP 0x00FF…0x011E (every row +3). Region-dependent sequential id — looks like an index into a list that has three more entries before the ribbons on PAL/JP (a message/sprite id), but nothing confirms it |
| 0x2 | `unknown_0x02` | u16 | 0 on every row, all regions; unread (could equally be the high half of a u32 at +0) |
| 0x4 | `descriptionMsgID` | u32 | `getRibbonMsgID` `lwz +4`, result goes to `GSmsgPrintRect`. Rows 0–20 = 0x2AF9…0x2B11, +1 per row (global msg ids in `common.rel`'s string table: 0x2AF9 = Champion Ribbon "HALL OF FAME Member", 0x2AFA = Cool Contest Normal Rank, 0x2B11 = Effort Ribbon). Rows 21–31 = 0 (the event/gift ribbons, which the status screen routes through ExRibbon instead) |

- Region differences: only `+0x0` (US vs PAL/JP, constant +3). `+0x4` is
  identical on all three, so the description string ids don't move.
- Enum candidates: none. The row index is the Gen-3 ribbon bit number.


## PurificationChamberData — `relivehall_data` (idx 98, count idx 99)

- **Not a table: one 0x4C-byte settings record.** Count word = 1 on all three
  regions; 0x4C × 1 = 0x4C = span (US sec4 0x45EA4, PAL 0x47E64, JP 0x44C58).
  Tiles exactly. **Byte-identical on US/PAL/JP.**
- Every reader does `lwz -0x75ac(r13)` and reads fixed offsets of row 0; the
  count word (`-0x75b0(r13)`) is **never read** (the `-0x75b0` in
  `modelPokemonSetScale` is `r2`-relative, the 0x43300000 int→float constant).
- Readers: `heroWalkReliveCallBack__12CReliveStageFlb` (module `reliveHall`),
  and in `menuHologram`: `modelPokemonSetScale`, `renderOffscreenData`,
  `stageAllModelLoad`.

Raw (all regions): `ff 00 00a0 0064 | 00 02 04 03 06 04 05 08 05 06 07 0a 06 07 08 09 0a 06 07 08 09 04 03 06 04 05 08 05 06 07 0a 06 07 08 09 02 01 03 01 02 04 01 02 03 05 01 02 03 04 05 01 02 03 04 02 01 03 01 02 04 01 02 03 05 01 02 03 04 | 0000`

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `offscreenAlpha` | u8 | `renderOffscreenData`: written as the alpha of each vertex colour `(FF,FF,FF,a)` of a 640×480 quad sent to the GX FIFO. Data 0xFF |
| 0x01 | `unknown_0x01` | u8 | unread; 0 (alignment pad before the u16) |
| 0x02 | `stepsPerPurification` | u16 | `heroWalkReliveCallBack`: if the Shadow Pokémon's `darkPokemonBiosGetSteps` ≥ this, `pokemonAddDp(-getPassion())` (heart gauge drops by the set's flow) and steps -= this (`darkPokemonBiosSetSteps`); else steps += walked. Data **160** |
| 0x04 | `pokemonScalePercent` | u16 | `modelPokemonSetScale`: `scale = menuGetPokemonScale(species) × value / 100.0f` (the 100.0 is `-0x75b4(r2)`), applied via `Sequence_SetScale` to the hologram Pokémon. Data 100 |
| 0x06 | `stagePartIndices` | u8[0x44] | `stageAllModelLoad`: `lbz data+6+off` where `off` comes from two DOL tables `[4][5][5]` of u32 — `lbl_803C7A7C` (offsets 1–34 → `GSmodelGetPart` joint/part index for each pokemon slot) and `lbl_803C7C0C` (offsets 35–67 → `(byte−1)×0x34` material index for `GSmaterialSetModulate`, the affinity-colour tint). Index 0 (= 0x00) is the "none" entry every unused DOL slot points at. All 68 bytes are reachable |
| 0x4A | `padding` | 2 bytes | 0; not reachable by any DOL offset (max 67) |

Notes:
- The DOL tables are indexed `[mode][dancerCount][slot]` with a triangular fill
  (rows of 1–5 used slots), so `stagePartIndices` is really several small
  per-configuration lists packed back to back; splitting it further would mean
  importing the DOL tables' shape, so keep it one u8 array.
- Enum candidates: none.
- Typing it as a 1-row CSV works; a `.struct` JSON would read better.


## TutorialData — game global `tutorialdata` (idx 120, count idx 121)

- **Map disagreement, settled by code:** the US/PAL maps name this global
  `undertakerdata`, JP names it `tutorialdata` — one of the slot-misplaced map
  names. Its only readers are `menuScriptTutorial*`, so it is the tutorial
  list; `tutorialdata` is the right name.
- Record **2 bytes (u16)** × **13** rows on US/PAL/JP = 0x1A; span to next
  symbol (idx 122 `MirorBData`) is 0x1C. **Does not tile exactly: 2 trailing
  zero bytes** (4-byte alignment before the next table). The current
  "span ÷ count" of 2.15 is that pad. Section-4 offsets: US 0xA09D8, PAL
  0xA5854, JP 0x59D44. **Byte-identical on all three regions.**
- Data: `0x38 0x39 … 0x43` (56–67, the last twelve of `NumberOfBattleCDs` = 68)
  then `0x0000`; pad `0x0000`.
- Readers (module `menuScript`, the Battle Tutorial menu in Prof. Krane's lab,
  `M5_labo_2F`): `menuScriptTutorialHook` (`lwz -0x761c(r13)`, `slwi 1`, `lhzx`;
  id → `deckDataVirtualDB_GetTitle`, `_GetFlag`, `_GetExplanetion2`; id 0 →
  title msg 0xDECE "CANCEL"/"EXIT"), `menuScriptTutorial` (chosen row's id →
  `fightEncountDataBiosSetDiskId(0xD, id)`, i.e. battle 13 is the tutorial
  battle and this picks its Battle CD), `menuScriptTutorialCursor` (count via
  `-0x7620(r13)`; the last row is treated as cancel, returns -1; at most 8 rows
  shown at once). `deckDataVirtualDB_*` index `deckdata_virtual` (`-0x744c(r13)`,
  stride 0x3C) = `BattleCDs` (idx 24), bounds-checked against its count.

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `battleCDID` | u16 | see readers above; 0 = the CANCEL row (must be last — the cursor code treats row `count−1` as cancel regardless of value) |

- Not really a struct: a u16 list. A one-column CSV with the 2-byte pad as a
  `_tail.bin`, or declare count 13 explicitly so the tail is split off.
- Enum candidate: a Battle CD enum if one exists (none of `Items` /
  `PokemonSpecies` / `Moves`).

## MenuSFX — game name `menu_se` (ptr idx 78, count idx 79 = `menu_se_number`)

- Record 0x0C, count 11 on US/PAL/JP; 11 × 0x0C = 0x84 = chunk exactly. No relocations inside.
- Accessor `menuSeBiosGetPtr(i)` (`mulli r0, r3, 0xC`, bounds-checked against `menu_se_number`).
  Sole caller `menuPlaySe(menuId, event)`: row index = high nibble of byte +1 of the
  `menuDataBiosGetPtr` record (DOL table lbl_802FC8F0, stride 0x1C) — i.e. a *menu SE set id*.
  `menuSeBiosGetSndId(row, event)` switches on the event code; event meanings from call sites:

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `open_sound` | uint16 | event 4 → `lhz +0x0`; `windowOpen` passes 4 |
| 0x02 | `close_sound` | uint16 | event 5 → `+0x2`; `menuDaemon` closing state passes 5 |
| 0x04 | `cursor_sound` | uint16 | event 1 → `+0x4`; every cursor-move site (`menuTitleOptionCursorControl`, `menuFightCurIkousan`, `menuPokemonStatusCursor`) passes 1 |
| 0x06 | `decide_sound` | uint16 | event 2 → `+0x6`; confirm sites (`menuBingoSheetBtn`, `menuFightButtonIwaza1p`, `menuDaemon`) |
| 0x08 | `cancel_sound` | uint16 | event 3 → `+0x8`; back/cancel sites (`menuBattleDiskMain`, `menuDaemon`) |
| 0x0A | `page_sound` | uint16 | event 6 → `+0xA`; `menuBdisk_selectL_Btn` passes 6 when the L/R page index changes |

- 0 = no sound (`menuPlaySe` skips `GSsndPlayNow` when the id is 0). Row 0 is all zero.
- Values (0x10–0x4DF) are global sound ids — indices into `SoundsMetaData` (`snd_data`, 1507
  entries; the largest id in any sound table here is 0x5E2 = 1506). No sound enum exists; keep
  uint16. Data: e.g. row 1 = `14 15 10 11 12 10`, row 3 = `14 15 441 442 443 441`.

## MessageSFX — game name `message_se` (idx 80, count idx 81)

- Record 4, count 6 everywhere; 6 × 4 = 0x18 = chunk exactly. No relocations.
- Readers: `_msgMainSub__FP13MSG_TASK_WORKUcUlb` (per-character text sound) and `GSmsgKill`
  (stops it). Both do a **linear search, not indexing**: for each row compare `lhz +0x0` with
  `MSG_TASK_WORK` byte +3, on match `lhz +0x2` is passed to the sound call (`GSsndStopNow` in
  `GSmsgKill`). Byte +3 is `GSmsgExec`'s third argument (`stb r29, 0x3(r30)`), which
  `winMsgCtrl` supplies from window param 2 — the "WithSE" message-window openers.

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `message_se_type` | uint16 | search key, compared with MSG_TASK_WORK+3 (`_msgMainSub`, `GSmsgKill`) |
| 0x02 | `sound_id` | uint16 | `lhz +0x2` → played / `GSsndStopNow` |

- Data, rows: `0000 0000 | 0001 002C | 0002 002D | 0003 002E | 0004 002F | 0005 0030`. Row 0 is type 0 → no sound.
  Because the key is searched, row order is not load-bearing and the key must stay unique.

## SoundTestBGM / SoundTestEnvironmentSounds / SoundTestCries / SoundTestSoundEffects

Game names `snd_test_bgm` (108/109), `snd_test_env` (110/111), `snd_test_nakigoe` (112/113),
`snd_test_se` (114/115). All four are **plain uint16 arrays** (record 2), no relocations:

| Table | count (US/PAL/JP) | bytes | tiles |
|---|---|---|---|
| snd_test_bgm | 0x6A = 106 | 0xD4 | exact |
| snd_test_env | 4 | 0x08 | exact |
| snd_test_nakigoe | 0x184 = 388 | 0x308 | exact |
| snd_test_se | 0xBE = 190 | 0x17C | exact |

Readers: the debug sound test, `dbgMenuSoundTestBGM` / `…ENV` / `…NAKIGOE` / `…SE`
(dbgMenuSoundTest.o): `menuOpen` returns the picked row, bounds-check against `_number`,
`lhzx r3, table, row*2` → `sndPlay`. ENV first walks every other row and closes any still playing (`GSsndGetStatus` 1–3 → `GSsndClose`);
BGM walks them too but only queries `GSsndGetStatus`.

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `sound_id` | uint16 | `lhzx` → `sndPlay` in each dbgMenuSoundTest* routine |

- Values are sound ids into `SoundsMetaData` (as above). ENV = 9,10,11,12. NAKIGOE = 0x3E2…0x419
  then 0x1F8…0x350 (cries) then 0x4F4, 0x4F5. SE contains one 0x0000 entry (row 152) — a
  placeholder, kept as-is. Only reachable from the debug menu; edits affect nothing retail.
- Suggest one shared struct (`SoundID`, single uint16) for all four, like `ValidItem`.

## TableResData — game name `table_res` (idx 118, count idx 119)

- **A pointer array, not data**: record 4, count 8 everywhere, 0x20 = chunk exactly. Every word
  is 0 on disc; the content is the relocation (module = common.rel itself, section 4).
- Accessor `tableResBiosGetResPtr(i)` (tableResBios.o): bounds-check vs `table_res_number`
  (logs and returns NULL past it), then `lwzx table, i*4`. Callers: `zz_8005c71c_` (game boot:
  `tableRes(0)` → `GSmsgFontOpen`, `tableRes(1)` → `GSmsgOpen`) and `floorMappingCommonScript`
  (index from `zz_8005c8c4_`, result memcmp'd against a 4-byte magic → the common script).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `resource` | label (pointer) | `lwzx` in `tableResBiosGetResPtr`; relocation per slot |

Slot → target (GODDESS pointer index), from the relocations:

| slot | US / PAL | JP |
|---|---|---|
| 0 | 135 (8-byte blob `FFFF0000 00000000`) | null |
| 1 | 136 `StringTable1` (MSG) | 135 |
| 2 | 137 `Script` (TCOD scd) | null |
| 3 | 138 MSG (`sym_138`) | 136 `StringTable1` |
| 4 | 139 MSG | null |
| 5 | 140 MSG | null |
| 6 | 141 MSG | null |
| 7 | 142 MSG | 137 `Script` |

- **Region difference in slot assignment**: JP fills slots 1/3/7 and leaves 0,2,4,5,6 null
  (no relocation) — the JP DOL presumably calls different indices; not verified (no JP
  disassembly). US/PAL agree slot-for-slot. 138–142 are the five further language MSGs
  (header words `…078B554B`/`4745`/`4652`/`4954`/`5350` = UK/GE/FR/IT/SP tags; US header `5553`).
- Typing it as a one-column `.label` table works with the REL CSV rules (each relocation lands
  on the label field; null slots → empty cell). Value of typing is low (it only re-points
  resources); the main point is the column names the target symbols.
- Index 135's 8 bytes (`FFFF 0000 0000 0000`) are what `GSmsgFontOpen` receives on US —
  likely an empty, 0xFFFF-terminated font-id list; unverified.

> **Naming check (coordinator's correction).** Every common.rel reader above was located from
> the address the common.rel `_prolog` actually stores each table pointer into (`prolog_registrations()`
> → `-(0x804EFE20 - addr)(r13)`), not from map names: idx 78/79 → `-0x755c/-0x7560`, 80/81 →
> `-0x7564/-0x7568`, 108–115 → `-0x75e4…-0x7600`, 118/119 → `-0x7604/-0x7608`. The readers are
> `menuSeBiosGetPtr`, `_msgMainSub`/`GSmsgKill`, `dbgMenuSoundTest{BGM,ENV,NAKIGOE,SE}` and
> `tableResBiosGetResPtr` respectively, so the code confirms the names for these seven (the map
> happens to be right here). Names to use: from the accessors — `menuSe`, `messageSe`,
> `sndTest{Bgm,Env,Nakigoe,Se}`, `tableRes`.

## BattleBingo — ptr idx 0, count idx 1 (game: `bingo_data` / `bingo_data_number`; global `-0x742c(r13)`, count ptr `-0x7430(r13)`)

- **Record 0xB8**, count 11 on US/PAL/JP; 11 × 0xB8 = 0x7E8 = chunk exactly. No relocations.
- Accessor `getStaticSheet__10bingo_biosFv`: `mulli r0, idx, 0xB8` — confirms the stride. All
  field getters are `bingo_biosF…(BINGO_DATA*)`: `getNo`, `getLevel`, `getBall`, `getScore`,
  `getPanelType/Tokusei/No/Waza/HoseiKind/HoseiVal` (panel stride `mulli 0xA`, bound 0xE),
  `getGridGrid/GridPos` (stride 2, bound 3). Consumers: `_fightTrainerCreateDeckBingo`,
  `cBingo::SetupSheet`, `menuBingoSheetBtn`, `dispPanel`.
- Bytes identical US = PAL; JP differs **only** in `name_id` (JP 0xDB0A + 2n vs US 0xDB25 + n).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `card_number` | uint8 | `getNo` (`lbz +0x0`); 1..11. Used as `isClear(no)`, and `no-1` indexes the DOL's own card text table |
| 0x01 | `difficulty` | uint8 | unread; 0..3 (legacy-only name, data consistent: 3/4/3/1 cards) |
| 0x02 | `index_in_difficulty` | uint8 | unread; 0..3 (legacy-only name) |
| 0x03 | `pokemon_level` | uint8 | `getLevel` (`lbz +0x3`) → `pokemonCreate` level arg; 30 or 50 |
| 0x04 | `unknown_0x04` | uint8 | unread; 2 on every row |
| 0x05 | `master_ball_count` | uint8 | `getBall` (`lbz +0x5`) → `cBingo+0x129` → `setStaticBall`; same counter mystery panel kind 1 increments. 2 everywhere (legacy "Unknown 2") |
| 0x06 | `pokemon_count` | uint8 | unread (code hardcodes 0xE); 14 everywhere |
| 0x07 | `mystery_panel_count` | uint8 | unread (code hardcodes 3); 3 everywhere |
| 0x08 | `name_id` | uint32 msg id | unread by code — the menu prints from a DOL copy `{name, description, difficulty}` × 11 at `lbl_803C7DD8` (US), whose values equal these on US |
| 0x0C | `description_id` | uint32 msg id | unread, as above |
| 0x10 | `score` | uint16[10] | `getScore(n)` (`lhz +0x10 + 2n`, n < 10); legacy "Rewards" (coupons per line count). Data `0,10,10,10,20,30,40,50,50,200` ×1/×2/×4/×10 by difficulty |
| 0x24 | `pokemon` | `BattleBingoPokemon`[14] (0xA each) | panel getters, bound 0xE; **[0] is the starter** (`getStaticIdx` picks it in `_fightTrainerCreateDeckBingo`, `SetupSheet` creates panel 0 as the player's Pokémon) |
| 0xB0 | `mystery_panels` | `BattleBingoMysteryPanel`[3] (2 each) | `getGridGrid`/`getGridPos`, bound 3 |
| 0xB6 | padding | 2 bytes | 0 on every row (struct alignment) |

`BattleBingoPokemon` (0xA):

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `type_slot` | uint8 | `getPanelType` → `pokemonDataBiosGetZokuseiDataId(species, value % 18)`: which of the species' two types the panel shows. 0/1 |
| 0x1 | `ability_slot` | uint8 (bool) | `getPanelTokusei`; `_fightTrainerCreateDeckBingo` → `pokemonSetTokuseiFlag(value != 0)`. 0/1 |
| 0x2 | `nature` | uint8 → **`Nature`** | `lbz +0x26` → `pokemonCreateRndFit` arg 5; values 0/6/12/18/24 (the neutral natures) |
| 0x3 | `gender` | uint8 → **`Gender`** | `lbz +0x27` → `pokemonCreateRndFit` arg 4; 0/1/2 |
| 0x4 | `species` | uint16 → **`PokemonSpecies`** | `getPanelNo` (`lhz +0x28`) → `pokemonCreate`; 1..0x19D |
| 0x6 | `move` | uint16 → **`Moves`** | `getPanelWaza` (`lhz +0x2A`) → `pokemonWazaCreate(slot 0)` |
| 0x8 | `ev_bonus` | uint16 | `getPanelHoseiKind` = `(v >> 12) & 0xF`, `getPanelHoseiVal` = `v & 0xFF`. If v ≠ 0, `pokemonSetStatus(p, 0, kindTable[kind], 0, val)`, kindTable = DOL `lbl_802F89DC` = `{0, 0x8D … 0x92}` — the six EV status ids (the code also sets status 0x93–0x98, the IVs, to 16 for every bingo Pokémon). So high nibble = EV stat 1-6, low byte = EV amount. Bits 8-11 ignored (one row has 0x2246) |

Data: `ev_bonus` high nibbles seen 0/2/3/4, amounts 0x80/0xFF/0x46. If split into bytes (no
sub-byte support in StructData): +0x8 `ev_stat` uint8 (stat = value >> 4), +0x9 `ev_amount` uint8.

`BattleBingoMysteryPanel` (2):

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x0 | `kind` | uint8 | `getGridGrid`; `menuBingoSheetBtn` switch: 1 → master balls +1 (`cBingo+0x129`, `setStaticBall`), 2 → EP +1 (`+0x12A`), 3 → EP +2; 0/≥4 nothing. Each card has exactly one of 1, 2, 3. Enum candidate `BattleBingoMysteryPanel`: None 0, MasterBall 1, EnergyPlus1 2, EnergyPlus2 3 |
| 0x1 | `grid_position` | uint8 | `getGridPos` → `SetupSheet` writes into cell `pos` of the 4×4 board (`cBingo+0x8 + pos*8`); 0..15 |

Legacy errors: record is 0xB8, not 0xB6 (2 trailing pad bytes missing, so every card after the
first was read 2n bytes off); panel +0 is the displayed *type slot*, not a "show secondary type"
bool (same values, it's an index); +8/+9 are one u16 EV bonus (kind nibble + amount), not two
unknown bytes; byte +5 is the Master Ball count. Its nature/gender/ability/species/move are right.

## BattleCDs — ptr idx 24, count idx 25 (game: `deckdata_virtual` / `deckdata_virtual_number`; global `-0x744c(r13)`, count ptr `-0x7450(r13)`)

- **Record 0x3C**, count 68 on US/PAL/JP; 68 × 0x3C = 0xFF0 = chunk exactly. No relocations.
  **Byte-identical on all three regions.**
- Accessor `deckDataVirtual_GetPtr__FUs` (`mulli 0x3C`, bound by the count) plus one generated
  getter per field (`deckDataVirtualDB_Get*`). A CD battle reaches the table through a Battles
  row whose `+0x08` (u16) is non-zero: that value is the CD index
  (`fightEncountDataBiosGetFightTrainerDataId`, `fightEncountDataBiosGetPokemon`).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `unknown_0x00` | uint8 | unread; 0x00 ×24, 0x40 ×19, 0x80 ×25 (looks like a 2-bit category in the top bits; no reader) |
| 0x01 | `turn_limit` | uint8 | `GetTurnLimit` (`lbz +0x1`); 0 = none, else 1..13 |
| 0x02 | `battle_style` | uint8 → **`BattleStyle`** | `GetPokemonNum` and `fightEncountDataBiosGetPokemon` (`lbz +0x2`, the same "Pokémon out per side" the Battles row holds at +0x2); 0/1/2 (0 only on the 5 empty rows) |
| 0x03 | padding | 1 | 0 everywhere |
| 0x04 | `battle_field_index` | uint16 | `fightDataRewrite`: for battle kinds 0xE/0xF, a non-zero value → `fightEncountDataBiosSetFightFloorDataId` (the Battles field `fightFloorDataId`, index into `BattleFields`); 0 = keep the Battles row's field. Values 0..0x41 |
| 0x06 | padding | 2 | 0 everywhere |
| 0x08 | `player_deck` | uint16 → **`Deck`** | `GetAllyDeck` (`lwz +0x8`, low half used as the trainer data id); 4 (`Virtual`) on every row |
| 0x0A | `player_trainer_id` | uint16 | low half of that word; index into DeckData_Virtual |
| 0x0C | `opponent_deck` | uint16 → **`Deck`** | `GetEnemyDeck` (`lwz +0xC`); 4 everywhere |
| 0x0E | `opponent_trainer_id` | uint16 | low half of that word |
| 0x10 | `name_id` | uint32 msg id | `GetTitle` (`lwz +0x10`) |
| 0x14 | `description1_id` | uint32 msg id | `GetExplanetion1` (`lwz +0x14`) |
| 0x18 | `description2_id` | uint32 msg id | `GetExplanetion2` (`lwz +0x18`) |
| 0x1C | `clear_flag` | uint32 flag id | `GetFlag`, `GetFlagData` → `GSflagTest`, `SetFlagData` → `GSflagSet`; 0x6FD..0x733 (one per CD), row 0 = 0 |
| 0x20 | `player_status` | uint8[6] | `GetAllyJoutai(cd, slot<6)` (`lbz +0x20+slot`) → `Pokemon::setCondition` in `fightActionFlowKaisiNyuujouTrainer` — the non-volatile status each party slot starts with. Non-zero (6) on 1 row |
| 0x26 | `opponent_status` | uint8[6] | `GetEnemyJoutai` (`lbz +0x26+slot`), same use |
| 0x2C | `items` | `BattleCDItem`[4] (4 each) | `GetItemID/GetItemNum(cd, i<4)` (stride 4) → `heroItemAddItemDataId(id, num)` in `fightTrainerCreateFightTrainerDataIdToHero`: bag items lent to the player for the battle |

`BattleCDItem` (4): +0 `quantity` uint8 (`GetItemNum`, `lbz +0x2C+4i`); +1 padding (0 everywhere);
+2 `item` uint16 → **`Items`** (`GetItemID`, `lhz +0x2E+4i`; 0 = empty slot, skipped). Only one
row uses items (5 each of items 0x0F/0x12/0x0E/0x11). Strictly the value is an item *data id*
(`heroItemAddItemDataId`, resolved through `ValidItems` — see the mart goods section); it
equals the `Items` row for every id below 350, which covers all retail values.

Status values: only 0 and 6 occur. A `PokemonStatus`/condition enum does not exist in the XD
engine yet; keep uint8.

Legacy errors: it reads +0x00 as "Unknown" and +0x02 as battle style (right), but put the battle
field and its padding as a u16 at an unaligned +0x03 in its declaration order (it lands at +0x04
only if GoDStruct aligns); "Condition Text ID" (+0x18) is the second description line, not a
condition; "Unknown 4" (+0x1C) is the CD's clear flag; the 0x1C "Unknowns" bytes are 6+6 starting
statuses and four `{quantity, item}` slots.

## MirorBData — ptr idx 122, count idx 123 (game: `undertakerdata` / `undertakerdata_number` — named correctly only in the JP map; US/PAL relglobal names are off by one slot (`waza_data`); global `-0x7624(r13)`)

- **Record 0x6C**, count 1 on US/PAL/JP; 1 × 0x6C = chunk exactly. No relocations.
  **Byte-identical on all three regions.**
- No stride accessor (single record); fields read directly off the global by the
  `undertaker` module: `underTakerCallBackFunc` (per-step update), `_appearMirabo`,
  `undertakerSetPlace`, `undertakerGetPlace`, `underTakerGetMiraboPlace`, `underTakerMiraboDisAppear`,
  `undertakerGetStartFlagID`, `underTakerBios::getPlaceMsg`, `menuIntUnderTakerHook`,
  `menuUseItemEventMirraboradar`. All "flag" fields are GeneralFlags ids used as counters/values
  via `GSflagGet/Set` (multi-bit flags), not just booleans.

Step logic (`underTakerCallBackFunc`, `r5` = steps taken): runs only if `start_flag` set,
`end_flag` clear and `darkpokemonCheckUnderTaker`. If Miror B is absent (`place_flag` = 0):
`step_counter_flag += steps`; on reaching `steps_per_check` do `r = rand % chance_range`;
`r < signal_up_chance` → signal +1 (and if the new signal ≥ `signal_max − 1`, Miror B appears
via `_appearMirabo` unless story progress is inside the pause window, in which case the signal
is held back by 1); `r < up + signal_down_chance` → signal −1; else unchanged. If present: he
leaves (all three counters zeroed, msg 0x3E85) when story progress enters the pause window or
`stay_counter_flag += steps` reaches `stay_steps`.

| Off | Name | Type | Evidence (US value) |
|---|---|---|---|
| 0x00 | `steps_per_check` | uint16 | `lhz +0x0`, compared with the step counter, then subtracted (100) |
| 0x02 | `signal_up_chance` | uint16 | `lhz +0x2`, `rand % range < this` → signal +1 (16) |
| 0x04 | `signal_down_chance` | uint16 | `lhz +0x4`, added to +0x2 as the down threshold (8) |
| 0x06 | `chance_range` | uint16 | `lhz +0x6`, rand modulus (32) |
| 0x08 | `signal_max` | uint16 | `lhz +0x8`: appear when signal ≥ max−1; `_appearMirabo` resets the signal to max−2 when no place qualifies (10) |
| 0x0A | `stay_steps` | uint16 | `lhz +0xA`, steps Miror B stays before leaving (1000) |
| 0x0C | `start_flag` | uint32 flag | `GSflagTest`; `undertakerGetStartFlagID` returns it (0x4A7) |
| 0x10 | `step_counter_flag` | uint32 flag | `GSflagGet/Set` step accumulator (0x5A9) |
| 0x14 | `signal_flag` | uint32 flag | signal strength; `menuUseItemEventMirraboradar` picks the radar message from it (≤2 / ≤5 / …) (0x5AA) |
| 0x18 | `place_flag` | uint32 flag | where Miror B is: 0 = absent, else a room id from `places`; `underTakerGetMiraboPlace`, `getPlaceMsg` (0x5AC) |
| 0x1C | `stay_counter_flag` | uint32 flag | steps since he appeared, reset by `undertakerSetPlace` (0x5AB) |
| 0x20 | `end_flag` | uint32 flag | `GSflagTest`; set → whole system off (0x587) |
| 0x24 | `radar_display_flag` | uint32 flag | `menuIntUnderTakerHook`: radar sprite shown when set and floor kind = Field (0x5AD) |
| 0x28 | `pause_start_story_index` | uint32 | row index into **StoryProgressFlags** (`lwz +0x28`, `<<5`, reads that row's +0x08 progress value vs flag 0x3C4) (72) |
| 0x2C | `pause_end_story_index` | uint32 | same, upper bound (80) |
| 0x30 | `random_bit_flag` | uint32 flag | set to `rand & 1` whenever he appears (`_appearMirabo`, `undertakerSetPlace`); consumer not in this module (0x6E4) |
| 0x34 | `places` | `MirorBPlace`[7] (8 each) | loops bounded by 7 in `_appearMirabo`/`undertakerGetPlace`; `getPlaceMsg` unrolled over +0x36…+0x68 |

`MirorBPlace` (8): +0 `weight` uint16 (`_appearMirabo`: summed over the 7, `rand % total`
picks the place; 3,3,1,1,1,0,0), +2 `room_id` uint16 (stored into `place_flag`; compared in
`getPlaceMsg`; 0x77, 0x3A, 0x5A, 0x5B, 0x5C, 0xA3, 0xA2), +4 `name_id` uint32 msg id
(`getPlaceMsg` returns it for the matching room; 0x3C25-0x3C29, 0x3C31, 0x3C32). Note the code
also special-cases entries **by position**: entry 0's room triggers a random-empty-Pokéspot
choice, entries 2-4 are tied to Pokéspots 0-2 (`esabaGetPokemonID(0..2)`), entry 1 is gated by
flag 0x8D1 — so reordering rows changes behaviour.

Legacy: 0x6C and the 7-location tail are right. Corrections: +0x02..+0x0A are the up/down/range
chances, signal max and stay steps (legacy "Unknown 2-6"); flag names — +0x10 is the step
counter (legacy "Steps Walked" ok), +0x14 the signal (legacy "Radar Status" ok), +0x18 the
current place (legacy "Current Location" ok), +0x0C start (legacy "Has Encountered Miror B" — it is the system's enable flag), +0x1C
stay counter (legacy "Unknown Flag 5"), +0x20 end flag (legacy "Don't Lose Signal" — wrong:
when set the system is off), +0x24 radar display (legacy "Unknown Flag 7"), +0x28/+0x2C are
StoryProgressFlags row indices, not "unknown" hex; +0x30 is a flag. Location +0 is a selection
weight (legacy "Unknown").

## StoryProgressFlags — ptr idx 46, count idx 47 (game: `flag_etc` / `flag_etc_number`; global `-0x74e4(r13)`)

- **Record 0x20**, count 101 on US/PAL/JP; 101 × 0x20 = 0xCA0 = chunk exactly (section 3, the
  REL's first data section). No relocations. **Byte-identical on all three regions.**
- Row index is `id << 5` everywhere. The only full-row consumer is the debug menu
  `dbgMenuFlagSetEtc` ("warp to story point"), whose menu labels come from
  `_dbgMenuFlagGetMenuNum` (`+0x1C`). The game proper uses rows as **named story checkpoints**:
  it reads `+0x08` of fixed rows and compares it with story flag 0x3C4 — row 10
  (`menuSaveLoadHook`, `lwz 0x148`), row 33 (`menuColosseumBattleInit`, `CReliveHall::isOpen`,
  `reliveHall` callback, `lwz 0x428`), row 68 (`WorldMap::getScooterType`, `lwz 0x888`), rows
  72/80 via MirorBData +0x28/+0x2C, plus computed rows in `_esabaAppearPokemon`,
  `_checkWaza2`, `WorldMap::GetInfoLevel`. So **row order is load-bearing**.

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `follower` | uint8 | `dbgMenuFlagSetEtc`: `lbzx` switch 0-3 → `heroSetFollowerWithID(n, 0)`; ≥4 ignored. 0 ×90, 1 ×9, 3 ×2 |
| 0x01 | padding | 1 | unread, 0 everywhere |
| 0x02 | `room_id` | uint16 | `lhz +0x2` → `floorChangePos` room (0 = stay on the current floor, `GSfloorGetCurrent`) |
| 0x04 | `money` | uint16 | `lhz +0x4` → `heroBiosSetPokedoru` (Pokédollars); 10000 on every row |
| 0x06 | padding | 2 | unread, 0 everywhere |
| 0x08 | `story_progress` | uint32 | `lwz +0x8` → `GSflagSet(0x3C4, v)` (the story-progress flag); every other reader compares flag 0x3C4 with it. Non-decreasing over the rows: 0, 0, 10, 20 … 990 |
| 0x0C | `script_function` | uint32 | `lwz +0xC`, non-zero → `appScriptCommonCall`. 0x05960017 on 100 rows, 0x05960000 on row 0 (GS script id: 0x0596 = common script, low half = function index) |
| 0x10 | `position_x` | float | `lfs +0x10` → `floorChangePos` f1 |
| 0x14 | `position_y` | float | `lfs +0x14` → f2 |
| 0x18 | `position_z` | float | `lfs +0x18` → f3 |
| 0x1C | `name_id` | uint32 msg id | `_dbgMenuFlagGetMenuNum` counts rows with non-zero +0x1C and fetches the string; 0xF3DA… (all distinct) |

Legacy errors: its "Unknown 1" word (+0x00) is the follower byte, a pad byte and the warp room
id; "Unknown 2" (+0x04) is money + padding; legacy's "Progress Value" (+0x08)
and the script split (+0x0C marker / +0x0E index) are right; the three floats are the warp
position (legacy "Unknown 3-5"); name id right.

## WorldMapLocations — ptr idx 128, count idx 129 (game: `worldmapXD_data` / `worldmapXD_data_number` — JP map; US/PAL names are shifted one slot to `worldmapXD_msgdata`; global `-0x7644(r13)`)

- **Record 0x24**, count 18 on US/PAL/JP; 18 × 0x24 = 0x288 = chunk exactly. No relocations.
- Accessor `WorldMap::SearchData(i)` (`mulli 0x24`, bound `GetDataNum`); getters `GetNpcID`,
  `GetModelID`, `GetFlagData/SetFlagData`, `GetInfoMsgID`, `SearchFloorID`, `SearchDataFloorID`;
  debug `_getWorldMapFlagData/_setWorldMapFlagData`. Fixed rows are also read directly:
  row 4 and 11 flags (`_appearMirabo`, `undertakerGetPlace`: `+0x94`, `+0x190`), row 7 and 13
  floor/flag (`kyogreMoveDemo::GetNextFloorID`: `+0x118`, `+0x1D8`, `+0x1F0`), and
  `_getWorldMapFlag` (PDA searcher) indexes rows from a 3-entry table — **row order is load-bearing**.
- US = PAL byte-identical. JP differs only in `menu_item_id` (rows 14-17, +1) and
  `snap_texture_id` (every row, +3).

| Off | Name | Type | Evidence |
|---|---|---|---|
| 0x00 | `camera_id` | int16 | `lha +0x0` → `GetCameraData(id, …)` in `InitCamera`/`SelectIcon` (index into the world-map camera table); equals the row index on every row |
| 0x02 | `npc_id` | uint16 | `GetNpcID` (`lhz +0x2`) → `charNameBiosGetNameID` (0 → msg 0x1772) in `SetInfo` — the character shown for the location; 0 on 4 rows |
| 0x04 | `unlock_flag` | uint32 flag | `GetFlagData` → `GSflagGet`; 0 = always available (`Init`, `SearchDataFloorID`, `_getWorldMapFlagData` returns −1). 0x3DF…0x449, 0 on row 6 |
| 0x08 | `menu_item_id` | uint32 | `Init`: `menuItemBiosSetSelectFlag(0x54, value, 1)` for each unlocked location (menu 0x54 = world map). 0x147…0x154, 0x5E1, 0x38C-0x38E (JP +1 on rows 14-17) |
| 0x0C | `model_id` | uint32 fsys file id | `GetModelID` (`lwz +0xC`) → `InitModel`; 0x18531001-0x18531012 |
| 0x10 | `snap_texture_id` | uint32 | `SetSnap`: low 16 bits → `windowDrawSprite` sprite id (the location's preview picture); 0x32E-0x33E (JP +3) |
| 0x14 | `move_demo_model_id` | uint32 fsys file id | `moveDemo` (`lwz +0x14`) stored as the demo's model; 0x1B4A0400 (special-cased: sub-models 0x1B4A1000-1603) or 0x1FDA0400 |
| 0x18 | `name_id` | uint32 msg id | **unread** (no load of +0x18 from any table pointer); 0xEA74…0xF634 all distinct (legacy-only name) |
| 0x1C | `room_id` | uint32 | `SearchFloorID`/`SearchDataFloorID`/`MainSub` (`lwz +0x1C`): the floor warped to; also `kyogreMoveDemo` |
| 0x20 | `info_msg_id` | uint32 msg id | `GetInfoMsgID` (`lwz +0x20`) when WorldMap mode byte ≠ 0, else a per-level table at `-0x764c(r13)` (stride 0x4C); 0 on rows 6 and 13 |

Legacy errors: the table was declared with `doorStruct` (0x20) — every row after the first
misread. Its own unused `worldMapLocationStruct` is the right size (0x24) and nearly right:
"Character ID" (+0x02) is an NPC id fed to the character-name table; "Unknown ID" (+0x08) is
the world-map menu item id; "Image Texture ID" (+0x10) and "Mini Model" (+0x0C) are right;
"Name ID" (+0x18) is never read; "Unused Text ID" (+0x20) is the info message and **is** used.


## Strides corrected against the accessors

Eight tables carried legacy layouts whose size disagreed with the game's own
accessor, so they dumped more rows than their count word declared. Each now
uses the accessor's stride, and count × stride tiles its chunk exactly on
US, PAL and JP; every count is linked.

| Table | Game name | Was | Is | Rows | Accessor |
|---|---|---:|---:|---:|---|
| PeopleIDs | `char_name` | 6 | 8 | 288 | `charNameBiosGet*` (`slwi 3`) |
| TrainerClasses | `fight_trainer_kind_data` | 10 | 0xC | 51 (JP 42) | `fightTrainerKindDataBiosGetPtr` |
| AIPokemonRoles | `fight_trainer_pokemon_part_data` | 13 | 0x18 | 79 | `fightTrainerPokemonPartDataBiosGetPtr` |
| Doors | `floor_door_list` | 28 | 0x18 | 216 | `_floorInitDoor`, `floorEventCtrlDoor` |
| InteractionPoints | `floor_event_list` | 24 | 0x1C | 832 | `floorEventExecScript` |
| PokefaceTextures | `poke_face` | 5 | 8 | 838 | `_menuFaceBiosGetPtr` |
| PokemonMenuAnimations | `pokemon_menu_animation` | 3 | 4 | 7 | `menuModelGetPokemonAnimationIndexByID` |
| BattleFields (PAL) | `fight_floor_data` | 0x18 | 0x28 | 66 | PAL `fightFloorDataBiosGetPtr` |

Five of them were C-aligned structs transcribed without their padding.
`NatureMultipliers` was the one table with real trailing data: ten 2-byte
rows, then a 6 × 8 block whose own count (6) is the second word of the
`NumberOfNatureMultipliers` chunk. Nothing relocates to either and the
prolog registers neither, so no code can reach them; the type map gives the
table `count: 10` and the block stays raw as its tail.

## Enums

Fields typed as enums because the code switches on their values or compares
them with constants (or, where marked, because the value set is closed and
unambiguous):

| Field | Enum | Evidence |
|---|---|---|
| `Type.effectiveness[]` | `TypeEffectiveness` | status ids 0x3F-0x43; `zokuseiGetAisyouValue` branches on them |
| `Type.category` | `MoveCategory` | the same value space as `Move.category` (`waza_GetZokuseiKindData`); Counter/Mirror Coat test 1/2 |
| `Move.matchup_display` | `MoveMatchupDisplay` | a 16-way jump table in `menuPokemonStatusDrawWaza` |
| `StatusEffect.owner` (DOL) | `StatusEffectOwner` | `statusGetStatus`'s jump table |
| `StatusEffect.write_mode` (DOL) | `StatusWriteMode` | `checkWriteJoutaiDataId` / `writeJoutaiDataId` |
| `BattleCD.player_status`/`opponent_status` | `StatusCondition` | passed to `Pokemon::setCondition` |
| `StoryCheckpoint.follower` | `Follower` | `heroSetFollowerWithID` switches on it |
| `Treasure.kind` | `TreasureKind` | bits 7:5 read by `_floorInitTresure`; whole byte, as Colosseum's `RoomKind` |
| `DeckTrainerPokemon.moves`, `DeckShadowPokemon.shadowMoves` | `Moves` | `getWazaID`, `getDarkWaza` |
| `DeckTrainerPokemon.keyPlayer` | `DeckPokemonKeyPlayer` | AI switch-in and lead selection treat 1/2/3 apart (names interpretive) |
| `DeckShadowPokemon.aggression` | `ReverseModeRate` | indexes a 5-column Reverse Mode percent table; replaces the wrong `ShadowAggression` |
| `DeckTrainerAI.specialityPokemonType1/2` | `Type` | compared with the move's type; 9 = none |
| `FloorFieldCamera.area_shape` | `CameraAreaShape` | tested `== 0` |
| `FloorOffscreenData.source_kind` | `OffscreenSource` | tested `== 0` |
| `PokemonSprite.pokedex_color` | `PokedexColor` | data: Gen III colors + 1 |
| `Room.area` | `Area` | data: names from the rooms' place names; code compares for equality only |

Move flag bytes and `TM.is_hm` are `.boolean` (0/1 on every row). The DOL
`StatusEffect` fields are renamed after their accessors (`slot`,
`max_count`, `turn_count_id`, `status_id`, `same_status_id`), and
`DeckTrainer` +0x2A, which was declared padding, is `fixedActionID`
(`getFixedActionID`). Left as integers on purpose: indices into other tables,
message/resource/sound ids, and `DeckTrainerAI.specialityMoveType1/2`, which
hold `MoveEffectType` values but are 16 bits wide against an 8-bit enum.
