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

## WIA / RVZ disc images

### Specifications
- **Dolphin `docs/WiaAndRvz.md`** ([dolphin-emu/dolphin](https://github.com/dolphin-emu/dolphin/blob/master/docs/WiaAndRvz.md))
  — the authoritative description of both formats, including the Lagged
  Fibonacci junk generator and the RVZ packing scheme.
- **Wiimms WIA documentation** (<https://wit.wiimm.de/info/wia.html>) — the
  original WIA reference, for the pre-RVZ half of the format.

### Reference Implementations
- **Dolphin Emulator** — `Source/Core/DiscIO/WIABlob.cpp` and
  `LaggedFibonacciGenerator.cpp` (GPLv2+). Consulted for the exact layering
  of a group payload (compression, then exception lists, then RVZ packing),
  for the rule that a group's junk generator is advanced by its offset
  modulo 32 KiB, and for the observation that the format's odd `>> 18` byte
  extraction can be folded into the generator's state at initialization.

## NKit disc images (GameCube)

### Specifications
- **NKit wiki** (<https://wiki.gbatemp.net/wiki/NKit>) and the
  [format page](https://wiki.gbatemp.net/wiki/NKit/NKitFormat) — the header
  block at `0x200` and the general shape of the format.

### Reference Implementations
- **Nanook's NKit v1** ([Nanook/NKitv1](https://github.com/Nanook/NKitv1),
  C#). The GameCube codec here is a direct port of its behaviour, read from
  the source rather than inferred:
  - `NKit/FilesAndStreams/JunkStream.cs` — the disc junk PRNG. Confirms the
    generator carries no leading-zero behaviour of its own, which is what
    located the rule in the gap layer instead.
  - `NKit/Conversion/Gaps.cs` — the gap encoding, its four types and four
    block kinds, and `blockCompare`'s allowance for leading nulls at the
    start of a gap (the comment "larger than 0x1c + 3 padding which can be
    nulls" is what named the constant).
  - `NKit/Conversion/NkitFormat.cs` — `GetConvertFstFiles` (files paired
    with the gap that follows, each file occupying its length rounded up to
    4 bytes) and `ProcessGap` (the `nulls` derivation).
  - `NKit/Conversion/Readers/NkitReaderGc.cs` — the restore walk, including
    `nullsPos = dstPos + 0x1c` after each file and the
    `size >= 0x40000 && !firstOrLastFile` rule that drops the allowance to
    zero for a large interior gap.
  - `NKit/Conversion/Writers/NkitWriterGc.cs` — the write order, the
    `0x800` tail padding and the CRC-force call.
- **Nayuki's "Forcing a file's CRC to any value"**
  (<https://www.nayuki.io/res/forcing-a-files-crc-to-any-value>) — the
  algorithm behind `CRCForce`, reached via NKit's `Checksums/CrcForce.cs`.

### Verification
- Pokemon XD US (`GXXE01`) `.nkit.iso` restored against the Redump ISO it
  was made from, with NKit's own recorded CRC-32 as the gate. The junk
  start rule was cross-checked independently against six retail GameCube
  discs before the source was consulted.

## Zstandard

### Specifications
- **RFC 8878** — Zstandard Compression and the `application/zstd` Media Type.
  The decoder in `GoDFoundation/Data/Compression/Zstd/` is written from this.
- **facebook/zstd `doc/zstd_compression_format.md`** — the same format with
  worked examples; used for the Huffman weight-to-code assignment and the
  repeat-offset rules.

### Reference Implementations
- **facebook/zstd** ([facebook/zstd](https://github.com/facebook/zstd), BSD/GPLv2)
  — `lib/decompress/zstd_decompress_block.c`'s precomputed default FSE
  tables are transcribed into `ZstdPredefinedTableTests` as the reference
  the built tables are checked against. The `zstd` CLI produced every
  compressed fixture, so the decoder is validated against an independent
  encoder rather than against itself.

### Documentation
- **Cyan4973/xxHash `doc/xxhash_spec.md`** — XXH64, which a Zstandard frame
  uses for its optional content checksum.

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

## PNG encoding and decoding

### Vendored Implementation
- **swift-png** by Diana Ma (tayloraswift) — Apache 2.0, version 4.5.1. The
  `LZ77` and `PNG` targets are vendored verbatim under
  `Sources/Shared/Dependencies/Third Party/swift-png/`, with the license
  alongside them. One local patch to `LZ77.DeflatorBuffers.Stream`'s final
  flush, documented in that folder's README; everything else is unmodified.

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

## ISH / ISD streamed audio (Colosseum, XD)

### Reference Implementations
- **vgmstream** (`src/meta/ish_isd.c`, `src/coding/ngc_dsp_decoder.c`) —
  the ISH header field list and the Nintendo GameCube DSP ADPCM decoder.
- **gc-dspadpcm-encode** (Jack Andersen, MIT) — the encoder and the
  order-2 LPC coefficient analysis.
- **VGAudio** (Ethan MacDonald, MIT) — a reference for both directions in
  C#.

### Verification
The published field list describes `0x20` and `0x24` as byte offsets into
the ISD and `0x28` onward as reserved. Measurement against 565 real ISH
headers, and then the game's own stream setup, says otherwise on both
counts, and the writers follow the game:

- They are **nibble addresses** into one channel's ADPCM stream, not byte
  offsets. The `-2` that `GSsndStreamPostFunc` applies to the loop start,
  and the 14/16 multiply inside `_sndStreamNibble_HeaderON2OFF`, are what
  identify the unit; the first sample lives at nibble 2, which is the value
  477 of 477 non-looping real headers carry at `0x20`.
- `0x28` is **live on 565/565 headers** and is the stream end. The roles of
  `0x24` and `0x28` cannot be inferred from the stored values — the
  inequality that holds on every looping header reads the wrong way round —
  and were settled by `GSsndStreamPreFunc` returning `stream + 0x40` as the
  ISH load buffer, which binds the header's words to the stream struct
  fields `GSsndStreamPostFunc` consumes.

Only `0x2C..0x3F` is reserved, and it is zero on all 565. See
`ISFHeaderRealCorpusTests` and
`Documentation/File Formats/Shared/ISH ISD - Streamed Audio.md`.

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

## Symbol maps (Colosseum, XD)

### Data Sources
- **Colo-XD-PBR-symbol-maps** ([StarsMmd/Colo-XD-PBR-symbol-maps](https://github.com/StarsMmd/Colo-XD-PBR-symbol-maps)) —
  community symbol maps in Dolphin `.map` format. `GXXE`/`GXXP`/`GXXJ.map` and
  `GC6E`/`GC6P`/`GC6J.map` are bundled in the XD and Colosseum engines and
  installed by `ProjectSetup` for the disc's own region. XD's carry the
  original CodeWarrior names and object files; Colosseum's are mostly
  positional (`zz_XXXXXXX`), which still supplies the chunk boundaries the
  data sections are split on.
- **NXXJ01** (the XD demo's development map, in the same repository) — the
  source of the names `match-symbols.py` propagates to the retail builds.

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
and XD's table is 78 rows — 0 blank, then 1–77 — which is what the game's own
count word, the size of `pokemon_tokusei_data` (0x3A8 ÷ 12) and the first
non-ability byte all say. (An earlier version of this note read "123 rows of
which only 1–77 hold real entries"; that came from the shipped type map's
count, which was wrong. The extra 45 "rows" were the next object.)

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

## Colosseum / XD battle-data enums

- **pret/pokeemerald** ([github.com/pret/pokeemerald](https://github.com/pret/pokeemerald))
  — `include/constants/hold_effects.h`. Colosseum's `Item.hold_effect` values
  follow Gen III's `HOLD_EFFECT_*` order exactly, so the `HoldEffect` case
  names are taken from it. The Pokédex color and battle terrain orders were
  checked against the same Gen III constants.
