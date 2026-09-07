# Credits & References

This document lists the reference implementations, specifications, and documentation used during development.

## Wii ISO Encryption/Decryption

### Specifications
- **FIPS 197** — Advanced Encryption Standard (AES). Used for AES-128-CBC implementation.
- **FIPS 180-4** — Secure Hash Standard. Used for SHA-1 implementation.

### Reference Implementations
- **Dolphin Emulator** — `VolumeWii.cpp` (GPLv2+). Referenced for Wii disc partition structure, encryption layout, and data group format.
- **Wiimm's ISO Tools (wit)** — `lib-std.c`. Referenced for Wii disc format details and common key handling approach.

### Documentation
- **WiiBrew Wiki** — Wii disc format documentation including partition table layout, ticket/TMD structures, and encryption scheme.

## Yaz0 / Yay0 compression

### Documentation
- **WiiBrew Wiki** and **CloudModding Wiki** — Yaz0 and Yay0 stream layouts:
  header fields, the flag/group structure, the three-table Yay0 split, and
  the two- and three-byte back-reference encodings.

### Reference Implementations
- **`simpleEnc` / `nintendoEnc`** — the widely-mirrored community reference
  encoder for Yaz0, carried by many GameCube/Wii toolchains. Referenced for
  encoder *semantics* rather than code: longest-match-wins with the furthest
  back winning a tie, two-byte matches degrading to literals, and the
  one-byte deferral heuristic (take a literal here if the next position can
  then take a match at least two bytes longer). `LZ77Encoder` reproduces
  those decisions over a hash chain instead of a linear window scan, and
  documents where it knowingly diverges.

## U8 / NARC archives

### Documentation
- **WiiBrew Wiki** — U8 archive layout: the 0x20 header, the 12-byte node
  records with their packed type/name-offset word, and the directory node's
  parent-index / subtree-end pair.
- **GBATEK** and the **DS homebrew documentation** — Nitro (NARC) container
  layout: the `BTAF`/`BTNF`/`GMIF` section trio, the file-allocation table's
  start/end pairs, and the name table's length-prefixed sub-table encoding.

### Verification
The layouts were re-derived from Battle Revolution's PAL disc rather than
taken on trust, which is what made byte-identical repacking possible: the
U8 data-region alignment, the no-de-duplication rule for the string table,
and the NARC section geometry were all measured across the disc's 24 `.arc`
and 6 `.narc` files before the writers were written. The big-endian NARC
variant — which announces itself by spelling its own magic `CRAN` — is not
covered by the DS documentation and was characterized from those files. See
`NintendoArchiveRealCorpusTests`.

## PowerPC Disassembler/Assembler

### Specifications
- **IBM PowerPC 750CL User's Manual** — Instruction set architecture specification for the Gekko (GameCube) and Broadway (Wii) processors. Used as the authoritative reference for instruction encodings, field layouts, and simplified mnemonics.

### Reference Implementations
- **ppc750cl** by encounter ([encounter/ppc750cl](https://github.com/encounter/ppc750cl), MIT license) — ISA definition YAML used as reference for complete instruction set coverage. All 222 PPC750CL instructions verified against `ppc750cl_isa.yaml`.
- **decomp-toolkit (dtk)** by encounter ([encounter/decomp-toolkit](https://github.com/encounter/decomp-toolkit)) — Symbol map format (`symbols.txt`) referenced for dtk symbol map parser support.
- **Dolphin Emulator** ([dolphin-emu/dolphin](https://github.com/dolphin-emu/dolphin), GPLv2+) — Symbol map format (`.map`) referenced for Dolphin symbol map parser support.

### Conventions
- **GNU Binutils/GAS** — PowerPC assembly syntax conventions. Formatter outputs GNU assembler-compatible syntax.

## Pokémon Battle Revolution — `common.fsys` data tables

### Reference Implementations
- **PBRHex** by Sean Miller / bgsamm ([bgsamm/PBRHex](https://github.com/bgsamm/PBRHex)) — `Tables/ModelTable.cs` and `Commands/ModelCommands/SetModelCommand.cs`. Referenced for the Pokémon model table's row layout (archive/file ids, bone-slot and animation-slot offsets) and for the bone/animation slot roles: its `BoneFilters` / `AnimFilters` name-matching lists are what the tool uses to re-point an imported model's slots, and were the starting point for `PBRModelBoneSlot` / `PBRModelAnimationSlot`. Its slot 0x15 reading (`ct_bust`) is the one the disc confirms, against the legacy tool's `ct_move`.
- **pbr-models-import-export** by Sean Miller / bgsamm ([bgsamm/pbr-models-import-export](https://github.com/bgsamm/pbr-models-import-export)) — Blender add-on. Referenced for the `.sdr` skeleton layout (skeleton pointer, bone/action counts, bone tree child/sibling links, action list stride) used to resolve slot indexes back to bone and action names, and for the `ct_all` camera-positioning note.
- **pbr-dtk** by Sean Miller / bgsamm ([bgsamm/pbr-dtk](https://github.com/bgsamm/pbr-dtk)) — matching decompilation project. Its `config/RPBP01/symbols.txt` (same region as the disc analysed here) supplied the named entry points — `SpeciesData_LoadSpecies`, `Item_LoadParam`, `Pokemon_LoadExperienceTableOf` — that located the `common.fsys` table pointer array at `0x8063CE34` and, through it, the generated row-getter / field-getter library that the entry layouts were mined from.
- **Legacy GoD Tool** ([PekanMmd/Pokemon-XD-Code](https://github.com/PekanMmd/Pokemon-XD-Code)) — `Revolution Tool CL/structs/*.swift`, `objects/PBRDataTable.swift`, `objects/PBRAbilitiesManager.swift`, and `Revolution Tool CL/PBR common pointers.txt`. Source of the table-name ↔ `common.fsys` index mapping (including the JP permutation), the RAM jump-table note, and the ported entry layouts for stats, evolutions, level-up moves, moves, items, TMs, type matchups, experience curves, icons/faces/bodies, trainer models/customisations/titles, colosseums and the Poké Coupon shop.

### Verification
Slot roles, entry strides and the container-format geometry were re-derived
from the PAL disc (RPBP01) rather than taken on trust: header invariants
across all 33 tables, and every bone/animation slot of 321 model rows
resolved against the bone and action names inside the `.sdr` each row points
at. See `PBRCommonTableRealCorpusTests`.

## Species / move / item enums (Colosseum, XD, Battle Revolution)

### Data Sources
- **PDA (Pokémon Discord Assistant)** by Stars Momodu — the bot's per-game
  JSON dumps (`json/data CM.json`, `data XD.json`, `data PBR.json`), which
  were themselves generated from each game's own data tables. Each entry
  carries the raw in-game `index` alongside its display name, which is what
  the generated `PokemonSpecies` / `Moves` / `Items` enums are built from.
  `js_modules/info.js` supplies the file ↔ game mapping (the other three
  dumps — XG, Grand Colosseum, Remix — are romhacks, not base games).

### Notes
The three lists are per-game and cannot be shared: Deoxys is species 410 in
Colosseum and XD but 386 in Battle Revolution, and the item lists diverge
wholesale. Entries the games ship with no usable name (`????`, `-----`,
`???`) and names that collide (Colosseum's 18 `DNA SAMPLE` items, the Deoxys
and Wormadam forms) are given `<Name>_<index>` case names so every raw value
stays addressable.

### Abilities
Ability ids come from neither source above: PDA carries ability *names* with
no index, and the legacy tool's `XGAbilities` is `case index(Int)` that reads
names out of the ROM at run time. They were instead derived from the games'
own data — each game's ability table stores a **message id** per ability, so
the table was dumped and joined against the game's message table:

| | ability ids | message ids | table |
|---|---|---|---|
| Colosseum / XD | 1–77 | 3101–3177 | XD DOL `Abilities` |
| Battle Revolution | 0–123 | 2990–3113 | `common.fsys` index 23 |

Colosseum and XD share one definition because their ability names occupy the
same message ids in the same order, verified run-for-run — not merely because
both are Generation III. Two things the derivation corrected: the list runs to
**77 (`AIR LOCK`)**, not 76 — PDA omits `CACOPHONY`, which no Pokémon has —
and XD's table is 123 rows of which only 1–77 hold real entries, the remainder
carrying uninitialised `name_id`s.

### Behaviour enums (move target / category / effect type, contest category, item pocket)
Ported from the legacy tool's `enums/XG*.swift` and
`Revolution Tool CL/enums/PBR*.swift`, then checked against the discs where
the two generations disagree — which they do more than the names suggest:

- **Move targets** are sequential in Colosseum/XD (0...7) but a 16-bit
  *bitmask* in Battle Revolution (0x001...0x400). Every move on the PAL disc
  carries exactly one flag (12 distinct values over 468 rows), so an enum
  reads correctly there.
- **Move categories** renumber entirely. Colosseum/XD are None/Physical/
  Special (0/1/2); Battle Revolution is Physical/Special/**Status** (0/1/2).
  The legacy `PBRMoveCategory` declares only the first two, but the PAL disc
  uses a third value 170 times and named moves settle it — Tackle, Body Slam
  and Earthquake are 0; Ember, Surf and Thunderbolt are 1; Growl and Swords
  Dance are 2. The enum here adds the missing case.
- **Item pockets** are one list: Colosseum has seven (0...6) and XD adds
  Battle CDs at 7, so the extra case simply never occurs in Colosseum data.

### Reference Implementations
- **Legacy GoD Tool** ([PekanMmd/Pokemon-XD-Code](https://github.com/PekanMmd/Pokemon-XD-Code)) —
  `Objects/struct tables/*.swift`. Used to decide *which* struct fields are
  enumerable rather than plain integers: its `.moveID` / `.itemID` /
  `.pokemonID` / `.typeID` property types are the mapping the
  `.abstraction` backfill follows. `AbilitiesTable.swift` supplied the
  ability entry layout (`Name ID` / `Description ID` as `common.rel` message
  ids) that made the join above possible.
