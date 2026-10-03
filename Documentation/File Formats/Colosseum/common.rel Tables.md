# Colosseum `common.rel` data tables

`common.rel` is the shared game-data module Colosseum loads at boot. Its
data section holds 28 fixed-stride tables, each paired with a count word
(`NumberOf…`) that the code reads before indexing. The Colosseum engine's
`Structs/entries/CommonRelStructs.swift` defines every one of them, the
region type maps (`Resources/common_rel_typemap_{us,eu,jp}.json`) bind the
tables to those structs, and `commonRelDump` writes each table as one CSV.

Every stride below is the table's chunk length divided by its count word,
and it agrees on the US, PAL and JP discs unless a PAL column is given.
Field offsets come from byte scans of all three discs (which bytes are
always zero, which carry relocations, how value sets group into 16- and
32-bit fields) checked against the legacy tool's Colosseum layouts and,
where a routine could be identified by its stride, against its loads. The
Colosseum disassembly's function names are positional matches from XD's
symbol map, so a name is only trusted where its body was read.

## Tables

| Table | Struct | Count word | Rows | Stride | PAL stride |
|---|---|---|---:|---:|---:|
| `LegendaryPokemon` | `LegendaryPokemon` | `NumberOfLegendaryPokemon` | 22 | 2 | |
| `PokefaceTextures` | `Pokeface` | `NumberOfPokefaceTextures` | 830 | 8 | |
| `PeopleIDs` | `PeopleID` | `NumberOfPeopleIDs` | 607 | 8 | |
| `Rooms` | `Room` / `RoomEU` | `NumberOfRooms` | 196 (PAL 197) | 0x4C | 0x5C |
| `TrainerClasses` | `TrainerClass` | `NumberOfTrainerClasses` | 41 (PAL 42) | 12 | |
| `BattleFields` | `BattleField` / `BattleFieldEU` | `NumberOfBattleFields` | 50 | 0x18 | 0x28 |
| `Doors` | `Door` | `NumberOfDoors` | 183 | 0x18 | |
| `BattleTypes` | `BattleType` | `NumberOfBattleTypes` | 19 | 0x20 | |
| `Keyboard{,2,3}Characters` | `KeyboardCharacter` | `NumberOfKeyboard…` | 119 / 9 / 386 | 2 | |
| `BattleStyles` | `BattleStyle` | `NumberOfBattleStyles` | 7 | 8 | |
| `Trainers` | `Trainer` | `NumberOfTrainers` | 820 | 0x34 | |
| `TrainerAIData` | `TrainerAIData` | `NumberOfTrainerAIData` | 261 | 0x28 | |
| `TrainerPokemonData` | `TrainerPokemon` | `NumberOfTrainerPokemonData` | 5510 | 0x50 | |
| `Battles` | `Battle` / `BattleEU` | `NumberOfBattles` | 566 | 0x38 | 0x48 |
| `SoundFiles` | `SoundFile` | `NumberOfSoundFiles` | 79 | 8 | |
| `AIWeightEffects` | `AIWeightEffect` | `NumberOfAIWeightEffects` | 553 | 0x14 | |
| `AIPokemonRoles` | `PokemonAIRole` | `NumberOfAIPokemonRoles` | 79 | 0x14 | |
| `TreasureBoxData` | `Treasure` | `NumberOfTreasureBoxes` | 74 | 0x1C | |
| `Moves` | `Move` | `NumberOfMoves` | 358 | 0x38 | |
| `Natures` | `Nature` | `NumberOfNatures` | 25 | 0x28 | |
| `PokemonStats` | `PokemonStat` | `NumberOfPokemon` | 413 | 0x11C | |
| `NatureMultipliers` | `Multiplier` | `NumberOfNatureMultipliers` | 8 | 2 | |
| `CharacterModels` | `CharacterModel` | `NumberOfCharacterModels` | 150 | 0x2C | |
| `ShadowData` | `ShadowData` | `NumberOfShadowPokemon` | 97 | 0x38 | |
| `PokemonMetLocations` | `MetLocation` | `NumberOfMetLocations` | 505 | 8 | |
| `InteractionPoints` | `InteractionPoint` | `NumberOfInteractionPoints` | 594 (JP 595) | 0x1C | |

### Tables typed from their XD counterparts

Nine more tables carry no name in the legacy symbol list and were named
here because each has an XD counterpart with the same record size, the same
count word and the same value pattern on all three discs. Their count words
equal their row counts on every region, and each is linked as a derived
count. Structs: `Structs/entries/CommonRelXDCounterpartStructs.swift`.

| Index | Table | Struct | Rows | Stride | Evidence |
|---:|---|---|---:|---:|---|
| 8 | `TableResData` | `TableResEntry` | 8 (PAL 20, JP 3) | 4 | pointers to the embedded fonts, string tables and script — XD's `table_res` |
| 10 | `FlagItemData` | `FlagItem` | 2 | 4 | read by Colosseum's debug set-flag routine through descriptor byte +2 |
| 16 | `FlagValues` | `FlagValue` | 7 | 4 | descriptor byte +1 |
| 18 | `FlagPartyData` | `FlagParty` | 4 | 2 | indexed by a story checkpoint's byte 0 |
| 22 | `StoryProgressFlags` | `StoryCheckpoint` | 54 | 0x18 | descriptor byte +3. **Shorter than XD's 0x20**: party index, room, money (10000 on every row), then x/y/z at +8 and a debug-name message id at +0x14 — no story-progress or script word |
| 26 | `BattleSideData` | `BattleSide` | 5 | 0x14 | XD's layout and row pattern exactly (null row, two player-side, two opponent-side) |
| 54 | `GeneralFlags` | `GeneralFlag` | 3593 | 8 | the flag descriptor table. Its count word sits in an 8-byte chunk whose second word (2451) stays raw |
| 66 | `ShadowPokemonFilterData` | `HeartGaugeChange` | 6 (explicit) | 1 | the same bytes as XD's, `ff ff fd fd ff ff` |
| 88 | `ContestData` | `ContestEffect` | 51 | 8 | appeal and jam as XD; **+6 is a description message id** (sequential from row 1) where XD has zeros |

`FlagsMetaData` (12, 4 × 8) and `FlagPokemonData` (20, 4 × 12) are named
too but stay raw, as in XD: the first is filled at boot, the second is all
zero. The flag-table roles come from the Colosseum routine that reads them
(`zz_Script_function_0x52_get_flag`, really a debug "set a flag and its
prerequisites" walk); see `Documentation/File Formats/XD/common.rel Tables.md`.

`GeneralFlags` used to be described as untargeted and is still bundled as
`general_flags_{us,jp}.csv` for the save pipeline, but the module's own
pointer index bounds it exactly, so it now also dumps in place.

Two embedded fonts are typed as `.fnt` file chunks besides the one already
known: index 94 (US and PAL, the large 22×22/18×18 kanji font) and index 97
(US). Their blocks carry 1 in the header word at +0x0A, which the font
writer used to zero; `GSFont` now carries it (`unknown0A`).

Colosseum keeps its trainers in `common.rel` (XD moved them to the deck
files): a `Trainer` names the index of its first Pokémon in
`TrainerPokemonData`, and its team is the six consecutive entries from
there. Items and types live in the DOL, not here.

## Regional differences

Colosseum's PAL build stores one field per language in three tables, and
in each case it does so by widening the record rather than appending:

- **Rooms** — US and JP keep a single FSYS group id at `+0x06` and the room
  id at `+0x0C`. PAL drops the id at `+0x06`, moves the room id to `+0x08`,
  shifts every later field down by four bytes, and appends five FSYS group
  ids (US/UK, German, French, Italian, Spanish) at `+0x48`. Stride 0x4C →
  0x5C.
- **Battles** — after the colosseum round id at `+0x14`, PAL inserts four
  more round ids (one per extra language) before the four participant slots.
  Stride 0x38 → 0x48.
- **BattleFields** — the message id at `+0x08` moves to the end and becomes
  five, one per language. Stride 0x18 → 0x28.

Two more quirks that are not layout changes:

- **US stores height and weight imperially.** `PokemonStat.height` is
  `feet × 100 + inches` and `weight` is `pounds × 10` on the US disc
  (Bulbasaur: 204 and 152), while PAL and JP store `meters × 10` and
  `kilograms × 10` (7 and 69). XD stores metric on every build.
- **TrainerClasses** has one more row on PAL, and **InteractionPoints** one
  more on JP.

## Rooms and the shadow cutoff distance

A room record's first byte holds the *floor kind* in its top three bits.
The low five bits are zero on every room of every disc and no routine reads
them, so the struct types the whole byte as the `RoomKind` enum (raw values
are the kind × 32); a modded value with low bits set still round-trips as
`RoomKind_<n>`. XD stores the same kind as a whole byte at `+0x01`, with the
same partition of rooms:

| Kind | Colosseum raw | Case | Rooms |
|---:|---:|---|---|
| 0 | 0x00 | `None` | room 0, `fight_demo`, `auto_demo` |
| 1 | 0x20 | `Field` | every overworld map the player walks in |
| 2 | 0x40 | `Battle` | colosseums and the per-town battle arenas |
| 3 | 0x60 | `Unused3` | handled by the floor code, no room uses it |
| 4 | 0x80 | `MoveViewer` | room 999, `waza_viewer` |
| 5 | 0xA0 | `Scene` | menus, logos, demos, and cutscene-only rooms (the Snagem Hideout intro, XD's ending event) |
| 6 | 0xC0 | `SystemMenu` | `title`, `topmenu`, the battle-mode menu, XD's `flashmenu` |
| 7 | 0xE0 | `Unused7` (XD: `BingoSheet`) | XD's room 907 only |

The kind is what the room-load routine uses to choose the shadow cutoff
distance and the shadow-map resolution. The routine (`zz_01129cc_` in the
US disassembly) reads it through `zz_0115ac8_`, Colosseum's copy of XD's
`floorDataBiosGetFloorKind` — it returns `(flags >> 5) & 7`, reporting a
Battle room as Field when no battle is in progress — and then:

| Kind | Shadow cutoff | Shadow map |
|---|---|---|
| Field, room ids 0x72–0x74 | 0 (no cutoff) | 640 × 480 |
| Field, other rooms | 70 units | 384 × 384 |
| Battle and MoveViewer | 80 units | 640 × 480 |
| the rest | unchanged | unchanged |

`GSmodelSetShadowCutoffDist` stores the *square* of the distance in a small
data global (`-0x5C98(r13)`, 0x8047AB88 on US); the shadow renderer compares
squared distances against it. The three constants sit in the DOL's small
data 2 section at `r2 − 0x6730`, `− 0x6728` and `− 0x6724` (0.0, 70.0 and
80.0 on US). So there is no per-room distance field: the cutoff is a
property of the room *kind*, and editing a room's flags byte changes it.

The rest of the record mirrors XD's `FloorData`: four pointers to DOL data
(render setup, characters, warp points, cameras), a name id, five
`{script, function}` pairs, and pointers to the pre/main/post lifecycle
functions plus one more data block. Pointer fields are 0 in the file and
carry a relocation to a DOL address where set — 162 / 126 / 125 / 25 rooms
for the four data pointers and 28 / 28 / 27 / 12 for the function and
extra-data pointers, the same counts on all three discs — and the typed CSV
names the target of each.

## Species, moves and natures

`PokemonStat` (0x11C) is XD's record with the fields rearranged: exp yield
and friendship are 16-bit at `+0x06`/`+0x08`, egg groups sit at `+0x6E`
where XD keeps tutor-move flags, the level-up moves start at `+0xBA`
immediately after the five evolution slots (twenty 4-byte slots, though no
species uses more than 13), and the two sprite blocks close the record at
`+0x10C`. The bytes at `+0x03` (5 for every real species) and `+0x04` have
no XD counterpart and no identified reader.

`Move` (0x38) shares XD's nineteen flag bytes and then diverges: the effect
is a 32-bit field at `+0x18`, the animation id follows at `+0x1C`, a
second animation id sits at `+0x32`, and the three effect-type bytes at
`+0x34` match XD's. `Nature` (0x28) is identical to XD's.

## Verification

`CommonRelTableCSVCorpusTests` runs the real dump over a real `common.rel`
(`GODDESS_COLO_COMMON_REL_CORPUS` names the project folder) and checks that
every table above came out as CSV with the row count its count word
declares. All 28 do, on the US, PAL and JP discs; with the nine above the
shipped maps type 37 tables and link 33 counts per region.

## Known gaps

- `Trainers` and `Keyboard3Characters` carry an explicit `count` in the type
  maps (820 and 386): the next symbol does not fall on the table's end on
  any disc — `Trainers` chunks short of its last rows without it, and the
  third keyboard has two stray bytes after its last key.
- `MetLocation`, `TrainerAIData` and the trailing halves of `ShadowData` and
  `CharacterModel` are typed by shape only; their field meanings are still
  the legacy tool's guesses. Two trainers carry a fourth message id after
  their loss text (`Trainer.unknown_text_id`); what it is for is unknown.


## Enums

| Field | Enum | Evidence |
|---|---|---|
| `Battle.battle_style` | `BattleStyle` (**corrected**) | a row of `BattleStyles` (`fightTypeDataBiosGetPtr`): Single, Double, Multi, None, SingleThreeEntered, DoubleFourEntered, MultiTwoEntered. The old XD-style names printed Colosseum's 557 doubles as "Single" |
| `InteractionPoint.interaction_method` | `InteractionMethod` | the event code logs "pass/touch/check/menu event" by value |
| `InteractionPoint.script`, `RoomScriptFunction.script` | `ScriptKind` | the loaded scripts' header ids (map 0x100, menu 0x200, title 0x201, battle 0x300, common 0x596) |
| `BattleField.terrain` | `BattleTerrain` | a row of the DOL terrain table (camouflage type, Secret Power, Nature Power) |
| `MetLocation.sighting_state` | `ShadowSightingState` | the Shadow Pokémon screens switch on 0/1/2 (names read from the branches) |
| `Type.effectiveness[]`, `Type.category` (DOL) | `TypeEffectiveness`, `MoveCategory` | as XD |
| `Item.hold_effect` (DOL) | `HoldEffect` | Gen III order; evolution tests 38, friendship 27 |
| `StatusEffect.owner`/`write_mode` (DOL) | `StatusEffectOwner`, `StatusWriteMode` | as XD |
| `ScriptBuiltinFunction.arg_types[]` (DOL) | `ScriptArgType` | `callStandard` marshals by it |
| `PokemonSprite.pokedex_color` | `PokedexColor` | data |
| `Room.area` | `Area` | data; compared for equality only |

Renamed on the same evidence: `Battle.wipe_id`, `TrainerClass.bgm_id`,
`BattleField` `room_id`/`intro_wzx_id`/`bgm_id`/`environment_sound_id`/
`side_ids`, `MetLocation` `required_flag_value`/`flag_id`/`text_id`, and
`ShadowData.first_sighting_index`. Move flag bytes and `TM.is_hm` are
`.boolean`. Not done: a 214-case `MoveEffect` (the numbering matches Gen III,
but the battle code's dispatch on it hasn't been traced) and a
`NatureMultiplierRate` (it would name rows of an editable table).
