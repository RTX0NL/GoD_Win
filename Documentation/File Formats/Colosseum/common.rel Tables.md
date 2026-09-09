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
declares. All 28 do, on the US, PAL and JP discs.

## Known gaps

- `Trainers` and `Keyboard3Characters` carry an explicit `count` in the type
  maps (820 and 386): the next symbol does not fall on the table's end on
  any disc — `Trainers` chunks short of its last rows without it, and the
  third keyboard has two stray bytes after its last key.
- `MetLocation`, `TrainerAIData` and the trailing halves of `ShadowData` and
  `CharacterModel` are typed by shape only; their field meanings are still
  the legacy tool's guesses. Two trainers carry a fourth message id after
  their loss text (`Trainer.unknown_text_id`); what it is for is unknown.
