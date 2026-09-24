# GoD-Tool

## Overview

GoD-Tool is a CLI utility for unpacking, editing, and rebuilding GameCube and Wii ROM files. It replaces the [legacy GoD tool](https://github.com/PekanMmd/Pokemon-XD-Code.git) which was an AppKit GUI that edited ROMs directly via byte patching. The new tool instead exports ROMs into a structured, human-readable project filesystem and rebuilds from scratch.

**Primary targets:** Pokemon XD: Gale of Darkness, Pokemon Colosseum, Pokemon Battle Revolution — but the architecture is intentionally general for any GameCube/Wii title.

**Executable name:** `GODDESS`

## Philosophy

- **Pre-release: nothing is deployed, so nothing needs migrating.** There are no
  users and no real projects yet. A change that invalidates every project dumped
  so far is free — say "re-dump" and move on. Do not write migration paths,
  back-compat branches, version checks or "projects dumped before this keep
  their old names" fallbacks for a format or layout decision; delete the old
  behaviour and make the new one the only one. This is the moment to break
  things, and a fallback kept "just in case" is a second code path that has to
  be understood and tested forever. (Back-compat for *other people's* formats —
  the games' own data, real save files, retail discs — is a different thing and
  still absolute.)
- **Export → Edit → Rebuild**, not direct ROM injection
- **Data-driven engines**: Game-specific knowledge lives in JSON definitions (structs, enums), not hardcoded Swift. New games should be addable without code changes.
- **Minimal assumptions**: Don't couple to specific game structures. The legacy tool broke when making complex modifications because it assumed too much about the data.
- **Correctness, not byte-identical round-trip** (default): Rebuild recomputes/rederives everything from scratch. The goal is a *correct* rebuild, not one whose bytes match the original. Where practical, rederive native conventions (padding, alignment, ordering) so output looks native — but that is a nice-to-have, never the objective. A from-scratch rebuild that differs byte-for-byte but is functionally correct is a success. Do not add "replay original bytes for round-trip fidelity" logic; do fix genuine correctness bugs in writers (wrong values, dropped data, crashes).
- **Byte-identical formats are the exception, declared per format.** A format is promoted to a 1:1 target only once measurement shows the gap is a small number of *nameable* divergences rather than an unmatchable re-derivation (e.g. a compressor whose output can't be reproduced). Promoted formats get a named exception here and a real-corpus fidelity test. Current 1:1 targets:
  - **FSYS** — see "FSYS byte-identical rebuild" below.
  - **U8 / NARC** — see "Nintendo archives" below. Both formats' geometry is
    fully derivable from the entry list plus one alignment constant, so a
    repack that differs is a bug rather than an accepted re-derivation.
  - **MSG (Colo/XD)** — see "Colosseum / XD messages" below. The pool is
    contiguous and unpadded, so the entries plus one ordering carry the
    whole layout.
- **CLI-first**: GUI tools are wrappers that generate configs and invoke the CLI.

## Build & Run

```bash
cd "GoD Tool Package"
swift build                          # build all targets
swift build --product GODDESS        # build main executable
swift test                           # run tests
```

- Swift 5.7+, macOS 13+
- Swift Package Manager (no Xcode build required)
- External deps: TokamakUI/Tokamak (UI framework), kelvin13/swift-png

### Running GODDESS

Pass an ISO file to set up a new project, or a JSON config to run operations:
```bash
GODDESS path/to/game.iso              # creates project structure
GODDESS path/to/Dump-Config.json      # runs dump operations
GODDESS path/to/Build-Config.json     # runs build operations
```

## Project Structure

```
GoD Tool Package/
├── Sources/
│   ├── Products/                    # Executable entry points
│   │   ├── GODSDK/                  # Main SDK (GODDESS executable)
│   │   │   ├── main.swift           # Entry point & dispatch
│   │   │   ├── Config/              # GoddessConfig, GoddessSettings
│   │   │   ├── Logger/              # PrintLogger
│   │   │   ├── FileSystem/          # FileSystem singleton
│   │   │   └── Operations/          # All dump/build operations
│   │   │       ├── Gamecube/        # ISO dump & rebuild
│   │   │       ├── ColoXD/          # FSYS dump & rebuild
│   │   │       └── ProjectSetup/    # Project initialization
│   │   ├── GoD Tool CLI/            # CLI entry (stub)
│   │   ├── GoD Tool UI/             # UI entry (stub)
│   │   └── Discord Plays Orre/      # Discord bot (empty)
│   ├── Shared/
│   │   ├── Core/Engines/            # Game engine definitions
│   │   │   ├── Engine/              # Engine protocol
│   │   │   ├── Dolphin/             # GameCube system layer
│   │   │   ├── GameCube/            # ISO format
│   │   │   ├── GeniusSonority/      # FSYS archives, TOC, etc.
│   │   │   ├── Colosseum/           # Colosseum-specific
│   │   │   ├── XD/                  # XD-specific
│   │   │   ├── Pokemon/             # Pokemon data structures
│   │   │   ├── Wii/                 # Wii system
│   │   │   ├── Nintendo/            # Nintendo's own containers (U8, NARC)
│   │   │   └── PBR/                 # Battle Revolution
│   │   └── Dependencies/
│   │       ├── GoDFoundation/       # Core: Data, Files, FST, Logging, Extensions
│   │       ├── Structs/             # Binary struct mapping system
│   │       ├── Persistence/         # UserDefaults wrapper
│   │       └── Third Party/
│   │           ├── xxHash/          # Hashing
│   │           └── swift-png/       # Vendored PNG + LZ77 (one local fix)
│   └── Base/App/                    # Shared UI foundation
└── Tests/
```

## Architecture

### Engine System

The core abstraction. Each engine (Dolphin, GameCube, GeniusSonority, XD, Colosseum, etc.) provides:
- **Data** (Codable): Game-specific constants and metadata
- **Enums**: Type definitions loaded from JSON
- **Structs**: Binary structure layouts loaded from JSON

Engines are **composable, not hierarchical**. Different operations may depend on any combination of engines. For example, a ColoXD dump uses Dolphin + GameCube + GeniusSonority engines together, but none "owns" or inherits from the others. Engine definitions are serialized to/from JSON in the project's engine folders.

```swift
protocol Engine {
    associatedtype DataType: Codable
    associatedtype EnumsType: EngineEnums
    associatedtype StructsType: EngineStructs
    var name: String { get }
    var data: DataType { get }
    var enums: EnumsType { get }
    var structs: StructsType { get }
}
```

### Operations

Operations are the units of work, configured via JSON config files:
- `gamecubeDump` / `gamecubeBuild` — ISO ↔ filesystem
- `coloXDDump` / `coloXDBuild` — FSYS archives ↔ organized asset folders
- `compress` / `decompress` (+ `compressFiles` / `decompressFiles`) — one file
  or a folder ↔ Yaz0 / Yay0 / headered or raw LZSS streams; engine-free and
  hand-authored (see "Compression operations")
- `runExecutable` — run a program on the host machine; engine-free and
  hand-authored (see "Running external programs")

Each operation has its own `Config` type and is enabled/disabled via the `OperationConfig<T>` wrapper with a `Toggle`.

**Every operation also has a name and a doc marker.** `OperationName`
(`GODSDK/Catalog/`) lists the cases as strings and `Operations.name` is an
exhaustive switch, so a new case won't compile until it is named. The MCP
server's `list_operations` / `describe_operation` serve the Configuration
Reference, embedded verbatim as `OperationReference.generated.swift` (re-run
`scripts/gen_operation_reference.py` after editing the reference —
`OperationCatalogTests` fails while the two differ) and sliced by the marker
line that introduces each operation: `**\`name\`** *(flat|container)* — one
sentence.` under a `###` family heading. The same test fails for a name with
no marker, so documenting an operation is part of adding it.

### File Formats

| Format | Engine | Description |
|--------|--------|-------------|
| GameCube ISO | GameCube/Dolphin | Disc image with boot sector, FST, DOL, apploader |
| FSYS Archive | GeniusSonority (currently) | Proprietary archive with LZSS compression. Confirmed to be Genius Sonority-specific (not a Nintendo or middleware format). Used in Colosseum, XD, and PBR. May need its own engine or a more general home if non-GS games are found to use it. |
| FSYS TOC | GeniusSonority (currently) | Table of contents mapping group IDs to files |
| DOL | Dolphin | GameCube executable (text + data sections) |
| Yaz0 / Yay0 | none — `GoDFoundation/Data/Compression` | Nintendo's own LZ77 codec, GameCube through Switch. Not used by Colo/XD/PBR; present for general titles and as a prerequisite for RARC/U8. See "Nintendo LZ77 compression" below. |
| U8 (`.arc`) / NARC (`.narc`) | Nintendo | Nintendo's own containers, big **and** little endian. PBR ships both. Declared 1:1 targets — see "Nintendo archives" below. |
| MESG | PBR | Battle Revolution's string tables, addressed by a global id through a directory in `common.fsys`. Shares the `.msg` extension with the Genius Sonority MSG and nothing else — see "PBR strings" below. |

#### Species / move / item enums are per-game

`PokemonSpecies`, `Moves` and `Items` are generated per title into the Pokemon
engine (`Colosseum/Xd/PbrPokemonEnums.swift`) from the games' own data tables —
see `Documentation/Credits & References.md`. They cannot be shared: Deoxys is
species 410 in Colosseum and XD but 386 in Battle Revolution, and the item
lists diverge wholesale. `PokemonEngine.defaultEngine(for:)` picks the set, and
ProjectSetup keys it off the disc's game, so installing the wrong one — which
would put confident, wrong names in every abstracted column — isn't possible
through the normal path.

`Abilities` is generated the same way but grouped differently: Colosseum and XD
share one list (their ability names sit at the same message ids in the same
order), Battle Revolution has its own. It is `uint8`, matching the fields that
hold it.

The behaviour enums — `MoveTarget`, `MoveCategory`, `MoveEffectType`,
`ContestCategory`, `ItemPocket` — split the same way, and genuinely differ:
Colosseum/XD number move targets sequentially where PBR uses a bitmask, and
the two move-category schemes don't line up (0 is "no damage" in Colo/XD,
"Physical" in PBR).

The fixed cross-game enums (`Type`, `Nature`, `Gender`, `EggGroup`, `ExpRate`)
stay shared in `PokemonEnums.swift`.

**A game engine carries every enum its own structs reference.** XD's and
Colosseum's `Enums.allItems` include their species/moves/items, because the
save structs resolve through that engine alone rather than through the combined
engine the typed-data path builds. Adding an `.abstraction` to a struct means
checking its engine can resolve the enum standalone.

**An `.abstraction` must match the field's width.** The enum's `propertyType`
decides how many bytes the field occupies, so swapping a `uint8` field for a
`uint16` enum silently moves every later offset. The numbered enums are
`uint16`; `Type` and friends are `uint8`. Only convert where they already
agree.

#### GCI saves

**The card envelope is generic; only the body split is per-game.** A save's
0x40 directory entry says where its banner, animated icon and two comment
strings are and what format each is in, so all three are located, decoded and
made editable for **any** GameCube title — `CardImageBlock`, `CardComments`
(`GameCube/File Formats/`). `Project.setup(gci:)` therefore accepts any save,
not only Pokémon ones. Verified byte-identical on all 27 distinct real saves
on the dev machine, Luigi's Mansion included (`GCIRealCorpusTests`, env
`GODDESS_GCI_CORPUS`).

The body splits on a `CardSaveLayout` region list: **declared** by a game
engine (`GeniusSonorityEngine.Data.saveCard`) where boundaries aren't
derivable — XD's slots at 0x6000/0x2E000, Colosseum's three at
0x6000/0x24000/0x42000 — else **derived**, giving a `metadata` region over the
images and comments plus one `data` region. Exactly one region is
`cardMetadata`; the rest are written verbatim, and their names (`slot-a.bin`,
`slot-1.bin`) are the contract the per-game save ops read.

**Paletted images are written as indexed PNGs and must stay indexed.** The
reason is the animated icon, not the banner: a GameCube icon is up to eight
CI8 frames sharing **one** palette (XD's save is `icon word 0x5555` — eight
shared-palette frames), and an RGBA PNG cannot say which index held which
color. Re-index each frame on its own and you get eight palettes in
first-seen-color order, which `CardImageBlock.encoded()` rejects outright
(`sharedPaletteMismatch`); force them all onto the first frame's palette
instead and any color the first frame doesn't have lands on index 0, so the
animation renders wrong. An indexed PNG keeps one palette across the frames
and the round trip is exact. RGB5A3 is invertible either way — XD's banner is
RGB5A3, so it is an ordinary RGBA PNG and never takes this path. The dump
verifies by re-encoding and comparing before trusting an artifact.

(This is *not* the checksum argument an earlier version of this note gave:
the build recomputes the metadata checksum, so a changed banner byte would
get a valid checksum anyway.)

**The metadata region is rebuilt from scratch and has no file of its own.**
It is filled with the region's declared `fill` byte, then written over with
the images, the comments and any checksum — nothing of the dumped save is
carried across. The dump earns that by proving the region is fully derivable:
images and comments must re-encode to exactly their original bytes, and every
byte outside them must already equal the fill. A save failing either check is
**refused** with the offsets named (`metadataNotReproducible` and friends)
rather than dumped with a hidden copy. All 61 distinct real saves pass. Do not
reintroduce a stored copy to make a stubborn save "work" — model what lives
there instead.

**XD and Colosseum checksum their own metadata, and the rebuild recomputes
it.** A `u32` big-endian word sum of the first 0x3A40 bytes, stored at 0x3A40,
correct on 72/72 real saves. It is declared as engine data
(`CardIntegrityRule`), not known to the generic layer, because editing a banner
or comment invalidates it and replaying the dumped value would produce a save
the game rejects.

**An earlier split was wrong, and is gone.** It cut the body into
`banner.bin` / `header0.bin` / `header1.bin`, which ends the banner three
quarters of the way into the first icon and leaves both "header sectors"
empty. Re-dump anything that still has those files. Full format spec and the
corrected layout:
`Documentation/File Formats/Shared/GCI - GameCube Memory Card Save.md`.

#### GCI save slots (Colosseum / XD)

The **latest slot only** is decrypted and dumped into per-section artifacts,
and the build reconstructs that one slot from scratch and leaves the other
slot(s) byte-untouched. Measured on 62 real saves across
all six game/region pairs, re-run 2026-09-18 after the envelope work —
`Documentation/Save-Round-Trip-Audit-2026-09.md`, driver in
`scripts/save-audit/` (`GODDESS_BIN` overrides the binary path):

- **Colosseum round-trips byte-identically on US, PAL and JP** — 20/20 saves,
  rebuilt from its artifacts alone with the original file deleted first. Its 7
  sections have the same names, offsets and lengths on all three, which is why
  one engine serves every region.
- **XD does not, by a bounded ~19 KB of filler — which holds no data.** The
  declared sections cover 88.1 % of the slot and the 168-byte slot header
  covers another 0.1 %; both are dumped. What differs on rebuild is 315 bytes
  of inter-block runs plus a 19,080-byte tail, measured at **7.97 bits/byte**
  entropy against **3.52** for real sections, using all 256 byte values and
  sharing **zero** 32-byte chunks with any live section. It is random filler,
  not relocated save data: XD relocates its sub-blocks on every save and
  re-randomises the space they aren't using, so those bytes are a function of
  the save's history rather than its state. Nothing inside a declared section
  ever changes, every editable artifact survives a re-dump, and pass 2
  reproduces pass 1, and **0 bytes differ inside any declared section** on any
  of the 62 corpus saves. XD dumps 10 of its 16 sections typed, JP included —
  the 2026-09-14 audit's headline finding, that JP demoted 4 sections and lost
  `PCBox` editing entirely, is fixed. **No rebuilt XD save has been booted in an
  emulator yet**,
  so "the game doesn't read the filler" is still an assumption. See
  `Documentation/File Formats/XD/XD Save Slot - From-Scratch Rebuild Plan.md`.

**The save pipeline is region-blind except for XD's Japanese build.**
`ProjectSetupGCI` keys off the gamecode prefix (`GC6`/`GXX`) for the game and
passes the full gamecode to `XDEngine.defaultEngine(forGameID:)`. XD shipped in
Japan first and the international builds widened four sections, so a JP save
binds JP structs for indices 0, 2, 6 and 7 — `XDSaveConfigJP` (0x80, no f64
`playTimeIntl`), `XDSavePCBoxJP` (0xBC0C, no trailing flag word or 0x40
region), `XDSaveBattleModeJP` (0x2EC, 11-unit rule names not 21) and
`ShadowPokemonStatusJP` (0x3C, 6-unit trainer names not 11). `Trainer`,
`Daycare` and `StrategyMemo` are identical on every build and share one
definition — note that `Trainer`'s player names are international-width even on
a JP save, so name widths are per-struct, not per-region. Binding the wrong set
doesn't mis-decode anything (the dump catches the size mismatch) but it costs
those sections their editable JSON, `PCBox` included.

**XD's 16 save sections are the game's own list.** `_memcardStoreSaveData_multi`
— the routine that serializes the RAM save buffer onto the card — writes them in
this order, taking each size from a 16-entry `u16` table at slot `+0x20` and each
source from `savedataGetStatus`, whose jump table resolves to the named
`savedataBiosGet<Name>Ptr` accessors. All 16 sizes match position-for-position on
real US, PAL and JP saves. Full derivation in
`Documentation/Assembly Analysis/Overview/Save System.md`.

Three sections that used to dump as opaque `.bin` are now typed, and one more is
split into its real parts:

- **3 = Mailbox** (`0x4A`) — 32 received-mail ids, a count, a seen-bit field, a
  sort mode and a send count. An empty id slot reads `0x00FF`, not `0xFFFF`
  (`mailInitMailbox` does `li r0, 0xFF` then `sth`).
- **9 = ExRibbon** (`0xB`) — 11 once-writable ribbon slots, one byte each. Slot 4
  is the National Ribbon (`0x2C`), slot 5 the Earth Ribbon (`0x2D`).
- **14 = Purify Chamber** (`0x2298`) — 9 sets × `0x3D8`, each 4 dancers + the
  centre Pokémon (all `XDPokemon`, `0xC4`) plus a signed dancer index used by the
  flow calculation. Flow, tempo and set state are *computed* from the Pokémon
  each time, not stored.
- **8 = Flags** (`0x6B4`) — not one blob: FlagLevel0 (`0x20`), FlagLevel1
  (`0x80`), FlagLevel2 (`0x600`), battle-disk sell-out bits (8) and Battle Bingo
  state (8), then 4 bytes the game never writes. Each bank's size is exactly what
  `GSflagInit` hands the flag system (8 / `0x20` / `0x180` words).

**Sub-section typing is its own pass, not a section type.** Some sections aren't
describable by a struct: XD's flag bits are undelimited and what splits them
lives in `common.rel`; Colosseum's flags sit at an offset *inside* a larger
section. So the save dump/build stay dumb — a section they can't type is one
raw `.bin` — and **`saveSectionsDump` / `saveSectionsBuild`** run either side of
them, decomposing that binary against a `SectionLayout` and recomposing it. The
binary is never deleted: the flow is `xdSaveDump` → `saveSectionsDump`, and in
reverse `saveSectionsBuild` → `xdSaveBuild`.

`SectionLayout` is offset-keyed JSON — the same role `TypeMap` plays for a
DOL/REL data section, keyed by byte offset because a save section has no
symbols. Chunks are `flags`, `struct` or `table`; **bytes no chunk claims are
kept verbatim as `gap-<offset>.bin`**, so a partial layout is lossless and can
be extended later. Overlapping or out-of-bounds chunks are rejected rather than
clipped. The operations are generic across games — engine folders resolve the
structs, exactly as `convert` and the REL type maps do.

**A flag chunk can address properties instead of a byte range.** Colosseum's
flags sit inside `Tail`, which is itself a struct, so that section dumps as JSON
and has no `.bin` to slice: each bank names a `field` and the chunk omits its
`offset`. For those the CSV is authoritative — the build writes the decoded
values back into those properties and leaves every other one alone. XD's flag
section is the byte-range case; both go through the same codec.

XD's layout also types the header of **`CurrentMapState`** (`XDAnywaySaveHeader`,
`0x20` bytes, magic `"ANSW"`): the body after it is a `GSBinWriteStream` payload
rather than a record, so it stays raw as a gap file. The `Yobi` blocks stay raw
too — the serializer reserves their space and never writes them, so there is
nothing to type.

The flag schema is `common.rel`'s **`GeneralFlags`** table (2324 × 6 bytes,
`GeneralFlag` struct, typed in the common.rel map so the REL dump writes it as
CSV). A flag's bit position is *not* stored: `GSflagInitBitPos` assigns each one
its bank's running total in table order at boot, and `XDFlagTable` reproduces
that. 149 of the 2324 flags are 2-32 bits wide, so a flag is not always a
boolean. **`XDFlagTable` reads the table by column name, not byte offset**,
which is what lets XD's 6-byte and Colosseum's 8-byte descriptors share one
codec with no stride constant anywhere.

XD's table is byte-identical on US, PAL and JP, so one bundled copy serves every
build. Section 8 decomposes to `08-Flags/flags.csv` (columns **`id,value`** —
bank, width and position all come from the table, so putting them in the file
would only offer columns that look editable and aren't) and `08-Flags/tail.json`
(`XDSaveFlagsTail`: the Battle CD sell-out bits and the Battle Bingo state).

**Colosseum runs the same flag system.** Its `_flagGet`/`GSflagSetTrue`/script
`check_flag` index the descriptor table as `id * 8` (XD: `id * 6`) and read the
bit position from `+0x4` (XD: `+0x2`), but the packed bank+width byte and the
whole bit codec are identical, and its three banks are *exactly* XD's
(`0x20`/`0x80`/`0x600`, handed over by the same `savedataGetStatus` indices
4/5/6 + 7/8/9). Its table is in **`common.rel`**, 3593 × 8 bytes; US and PAL are
byte-identical and JP differs in one byte — flag 9 changes bank, which shifts
every later flag in two banks — so both tables are bundled and `ProjectSetup`
writes the disc's own. It is wired up: the banks are the `flagLevel0`/`1`/`2`
fields of `ColoSaveTail`, so the layout addresses them by **property** and needs
no internal offset (see "A flag chunk can address properties instead of a byte
range" above). One thing is still open, and it is about the *descriptor table*,
not the save: no relocation targets it, so it sits inside an untyped `.bin`
chunk in `common.rel` and would need the offset-keyed sub-section mechanism
rather than a symbol-keyed type-map entry to be typed in place — which is why
the CSV is bundled as a resource instead. Full derivation in
`Documentation/Assembly Analysis/Data Structures/Flags.md`.

**Yobi1-4 (10-13) are reserve blocks the game never writes.** The serializer
reserves their card space and returns without copying anything, so their bytes
are uninitialised packing-buffer memory — ~99 % non-zero and different in every
save. They stay `.binary`, and their contents mean nothing. ("Yobi" is 予備,
*spare*.) **15 = AnywaySave** stays `.binary` too, but for the opposite reason:
it is a `GSBinWriteStream` payload behind a `0x20`-byte header (`+0x04` non-zero
means a quicksave is present), so it is a stream, not a struct.

**XD's slot header dumps as typed JSON (`slot-header.json`), not a blob.** Its
168 bytes are real save data and are now a struct (`XDSaveSlotHeader`, in the
XD engine) with named fields, measured across 24 real saves spanning all three
regions:

| Offset | Field | Observed |
|---|---|---|
| `0x00` | `magic` | `01 01 01` on 23 of 24 |
| `0x03` | `reserved` | `0` everywhere |
| `0x04` | `saveCounter` | small `u32` |
| `0x08` | `cipherKey` | plaintext key seed, fresh per save |
| `0x10` | `checksumTags` | zero in a decrypted slot; the cipher rewrites them on encrypt |
| `0x20` | `subBlockSizes` | 16 × `u16`, region-dependent (JP Config 0x80 vs 0x88) |
| `0x40` | `subBlockOffsets` | 16 × two `u16`, **low half first**, relative to 0xA8 |
| `0x80` | `reservedConstant` | `00 20 00 80 06 00 00 08 00 00 00 08` on all 24, JP included |
| `0x8C` | `unidentified` | high-entropy; halfwords repeat at +16 offset by the cipher's own sbox biases, so it reads as leftover cipher state |

The size and offset tables match all 16 dumped sections exactly, which is the
check that no sub-block is missing. **Colosseum's 8-byte header is typed the
same way** (`ColoSaveSlotHeader`: `magic`, `reserved`, `counter`) — measured on
8 real saves, its magic is `01 01 00 00`, the same family as XD's rather than
the gamecode it looks like it should be. The dump falls back to
`slot-header.bin` with a warning only when the engine has no struct of the
right length.

**The body-checksum offset is engine data, and `nil` means don't checksum.**
`XDSaveSlot.Layout.checksumOffset: Int?` — the stock layout carries the retail
`0x10` explicitly, so ordinary saves are tagged exactly as before. A modified
format can move the region and the encrypt path clears and rewrites the tags
where they actually live; setting it to `null` says this format has no
checksum, so none is written and `decrypt` returns `nil` for "not checked"
rather than a pass or a fail. Writing four sums at a guessed offset would
corrupt whatever lives there, which is why the absence of a value is not a
licence to use the default.

An absent `checksumOffset` in a hand-written engine therefore means no
checksum, which is the natural reading of "this format declares none" — the
stock engine writes the key, so this only bites someone authoring one by hand.
A relocated region must stay inside the encrypted range or the cipher throws,
since the game reads its tags from inside it.

**A section only dumps as editable JSON when its struct tiles it exactly.**
Otherwise the dump warns and writes a raw `.bin`, and the section's manifest
entry says `"type": "binary"` — the manifest reports what was written, never
the type the section would have had. A demotion is a `.warning`, not `.info`,
because the generated `Settings.json` has `verbose: false` and a section
silently dropping out of the editable set is the user's problem.

**A blank, never-saved card is rejected at dump time in both games.** A fresh
card is `01 01 …`, zeroes to the end of the first 0x2000 block, then `0xFF`
fill; decrypting it yields garbage whose checksums fail. Colosseum's fixed
section layout used to "parse" that garbage and round-trip it into a save whose
checksums were now *valid*, and XD used to emit an empty section list and fail
much later at build. Both now throw `noValidSlot` when no slot validates, and a
slot that failed its checksum is never picked as "latest" over one that passed.

#### Struct tables as CSV

A table of struct entries dumps as one CSV file, not JSON: a header row of
flattened property paths, then one row per entry. `StructCSVSchema` derives the
columns from the `StructDefinition` and is the single source of offsets for both
directions, so a header and an offset can't disagree.

| property | columns |
|---|---|
| scalar primitive / enum / `.label` | `name` |
| `.subStruct` | dotted path — `base.attack` |
| char array | one column, the whole string |
| other array | `name[1]`…`name[n]`, **1-indexed** |
| padding, `.primitive(.void)` | none |

Values are the *abstracted* form — an enum is its case name, a bool is
`true`/`false`, a pointer is its label name. **A raw value the enum doesn't name
falls back to the integer**, never a synthesized `Enum_<raw>`: every cell is
text, so a synthesized name could only be told from a real one by rebuilding the
enum's current name. Non-finite floats are `NaN`/`Infinity`/`-Infinity`, except a
NaN carrying a payload, which keeps its `0x`-prefixed bit pattern because the
spelling can't carry one.

Decoding builds each entry from scratch in a zeroed buffer — the CSV plus the
definition are sufficient, nothing is read back from the original binary — and
matches columns **by header, not position**, so a file can be reordered or
partially filled. Absent or blank cells leave their bytes zero.

Row-level metadata stays out of the file: a row is the struct's fields and
nothing else. Per-entry symbol names ride in the section `manifest.json` as
`entryLabels`, keyed by entry index.

A pointer field in a REL table is a **relocation, not a stored address**: the
word on disc is 0 and the target lives in the relocation table. A `.label`
column therefore resolves through the relocations that fall inside the table
(`TypedDataExporter`'s `pointerLabels`), and a word with no relocation is a
null pointer that gets an empty cell rather than `lbl_00000000`. XD's `Rooms`
is the motivating case — 785 relocations over nine pointer fields, all to DOL
addresses, so the CSV names the room's pre/main/post functions and data
blocks — and `Pokespots` the small one. The DOL path is unchanged: there the
stored word is the address and names it.

Two shapes deliberately don't survive, and the dump checks for both by decoding
its own CSV back and comparing bytes before writing it (mismatch ⇒ the chunk
demotes to a raw `.binary` chunk): a **padding run that isn't zero** (padding has
no column, so it rebuilds as zeroes) and a **string field with bytes after its
terminator**. Both mean the struct definition doesn't describe the data — the fix
is to type that run as a real field, not to special-case the codec. Label fields
are excluded from that comparison by design: their four bytes are a pointer the
assembler re-derives, so they are zero on the way back in and *should* change
when the layout moves; the symbol names are compared instead.

#### REL source tree

A disassembled REL is a folder the assembler reads back in full. The
`<name>.rel.json` manifest (`RelManifest`) carries the header scalars, the
import order, one chunk list per data section — each chunk's file path,
relative to the module folder, and the type it was mapped to (`table` +
`structType`, `file` + `fileExtension`, `assembly`, `binary`) — a symbol
table, and at-rest words. It carries **no bytes**: every byte of the module
lives in a file it points at, so editing that file is editing the module.
There is no per-section `manifest.json`; the REL's one list spans every
section.

| section | on disk |
|---|---|
| text | `textN.s`, PPC assembly with relocations spelled as `sym@ha` / `sym@l` / `.4byte sym` |
| data, nothing points into it | `dataN.s` |
| data, with self symbols | `dataN/` — one file per chunk, cut at every symbol the module's relocations target: `<sym>.bin` (no pointers inside), `<sym>.s` (pointers, as `.4byte sym`), `<sym>.csv` (a typed table), `<sym>/…` (a typed file, through the format registry), `<sym>_tail.bin` (bytes after a table or file, before the next symbol), `dataN_start.bin` |

**Relocations are re-derived from the source, not stored.** `RelAssembler`
assembles each section with `PPCSectionAssembler.assembleRelocatable`, which
leaves every `@ha`/`@h`/`@l`/`.4byte sym` field at rest and reports the
site, then resolves the symbol: a label defined in any section of the module
first, the manifest's `symbols` table second. So moving a definition moves
its references, and only targets the source cannot define — the DOL, other
modules, this module's BSS — need the table. A branch to a label in the same
section is PC-relative and never relocated; `_prolog`/`_epilog`/`_unresolved`
labels set the entry points. The one thing that is positional is
`restWords`: the at-rest word at a relocation site when it isn't zero-field
(87 pointer slots in Colosseum's `common.rel`, nothing else in either game).
An `lbl_XXXXXXXX` name that is not a known symbol is a literal word, which is
how a typed exporter spells a pointer slot it could not name.

**Typing policy.** A table becomes CSV only if every relocation inside it
lands on a field the struct declares as a `.label`, and the CSV decodes
back to the same bytes; otherwise it is written as assembly, with a warning,
so no relocation is lost. A pointer cell holds the relocation target's name;
a slot with no relocation is a null pointer and stays empty (a non-zero
unrelocated word keeps an `lbl_` literal). A typed file is dumped through
the registry only if no relocation lands inside it. A table with an explicit
`count` may run across later symbols, which become its `entryLabels`; one
without ends at the next symbol like any other chunk. The assembler needs the
same `engines` list the dump used to resolve `structType` names —
`commonRelBuild`/`mapRelsBuild` carry it, and `ProjectSetup` fills it in.

`RELFile.outputs`/`init(outputs:)` are this same layout with no type map, so
the format-level round trip and the golden fixture exercise the real
disassembler and assembler. Verified byte-identical on all 430 XD US +
Colosseum US RELs (every map, `common.rel`, `mail.rel`, `tableres2.rel`)
untyped, and on typed `common.rel` dumps. A typed dump reassembles its
module byte-for-byte, XD's and Colosseum's alike
(`CommonRelRoundTripCorpusTests`, skips without a module,
`GODDESS_COMMON_REL_ROUNDTRIP`). It used to come out 8-65 bytes short,
which the 2026-09 audit put down to the MSG codec; the actual cause was the
4-byte alignment padding a container puts after an embedded string table,
and `MSGFile` now carries it.

#### A rebuilt DOL keeps its layout

A data chunk runs from its own symbol to the next one, so its length is part
of the section's layout rather than a property of its contents. Let one
re-encode longer or shorter and every symbol after it in that section moves —
and the DOL's symbol map is keyed by **address**, with the type map layered on
it naming chunks by **label**, so the next dump then types the wrong bytes.
That is what cost XD US 10 of its 13 DOL CSV tables in the 2026-09 audit and
had `Abilities.csv` decode from an address 31 bytes off. (`common.rel` never
had the problem: `common_rel_symbols.json` is keyed by relocation pointer
*index*, an ordinal, so a shift carries its symbols with it.)

Four things hold the layout now, and each was a measured failure first:

- **An embedded file's length comes from the format, not from the next
  symbol.** `FileFormat.measuredLength(of:)` (default nil, reached through
  `FileFormatRegistry.measuredLength(of:extension:)`) lets a format say where
  it ends. GTX reads it off the palette offset and entry count; MSG walks from
  the last entry's string to its terminator. The gap to the next symbol is a
  **floor** it may raise and never lower — lowering it would take a chunk's
  trailing alignment padding away from the owner that re-emits it, and the
  type map's explicit `size` is still how you shorten a file. Two real cases:
  XD's health-warning texture names its palette `tex_warning` 0x6C0 bytes in,
  so the texture was cut 32 bytes short and its PNG dumped blank; XD PAL's
  Spanish message table has a symbol 31 KB into a 98 KB table, so **584 of its
  859 strings fell outside the dump entirely**.
- **Symbols a file swallows are kept.** They are relocation targets, so the
  manifest carries them as `interiorLabels` (offset from the chunk start →
  name) and both assemblers re-emit each at that offset inside the rebuilt
  file.
- **A chunk is held to the size it was dumped at.** Every chunk type records
  a `size` now (it used to be `.binary` and `.file` only, and nothing read
  it). One that rebuilds **short** is zero-padded back — the formats that own
  those bytes carry their own lengths, so nothing reads the padding — and one
  that rebuilds **long** stops the assembly, naming itself, unless
  `allowResizedChunks` says the shift is intended. The section total is
  checked against `sections.txt` the same way. A manifest from before sizes
  were recorded has nothing to check and assembles as it always did.
- **A deliberate shift rewrites the symbol map.** `dolAssembly`'s
  `outputSymbolMapPath` re-emits the map at the addresses the assembly
  produced; project setup points it at the input map, so the next dump reads
  the shifted addresses. Input symbols keep their size, section and object
  file (those columns decide how text splits into per-object folders) and take
  the address of the label of that name; every data-section chunk and
  table-entry label is added whether or not the map had it, because on XD the
  type map's tables are named by `lbl_XXXXXXXX` auto-labels that were never in
  the map and are exactly what a shift strands. Verified on XD US: 20,714
  symbols in, 22,200 out — 0 moved, 0 lost, 1,486 added. Not covered: a map symbol
  the disassembler kept out of the chunk boundaries for being misaligned — it
  defines no label, so it keeps its old address. Those are already documented
  as not shiftable.

**Measured on all six GameCube discs.** `main.dol` → disassembly → `main.dol`
now comes back at exactly its original length and section table on Colosseum
US/PAL/JP and XD US/PAL/JP, where before it was Colo −3/−9 and XD +31/+22/+1164.
`DolLayoutCorpusTests` pins that (skips without a project,
`GODDESS_DOL_CORPUS`). What still differs is the body of an
**indexed** texture, and it is cosmetic: GTX dumps its pixels as an RGBA PNG,
so the re-encode rebuilds the palette in first-seen-color order and collapses
duplicate entries (XD's `lbl_803FA760` uses 125 indices carrying only 56
distinct colors). Three textures per XD disc, 7,398 bytes; 23-24 KB on
Colosseum. **Nothing moves** — a palette's entry count is fixed by the format,
so the texture keeps its length — and every pixel renders the same color it
did, because each GTX carries its own palette and nothing indexes into it by
number. Unlike the GCI icon frames, which share one palette across eight
images, there is no correctness argument here, so this is left alone.

**Alignment is separate from the offset multiplier.** `fstOffsetMultiplier`
says how a stored FST offset is scaled (1 on GameCube, 4 on Wii); it was also
being used as the FST's disc alignment, so on GameCube the FST landed wherever
`main.dol` happened to end — an odd byte offset once a rebuilt DOL changed
size. `fstOffsetAlignment` is the real constant and 0x100 reproduces retail
exactly: `align(end of main.dol, 0x100)` is the FST offset on all five
GameCube discs measured. `dolSectionAlignment` (0x20) does the same inside the
`.dol`; every section of every retail Colosseum and XD build is already a
multiple of 32 bytes long, so it changes nothing until an edit resizes one.

#### DOL data tables

Both games keep data tables in `main.dol` as well as in `common.rel`, and the
split differs: XD's DOL holds 13 (menu sprites, status effects, abilities,
TMs and the PKX/WZX model references), Colosseum's holds 15 — the same
families plus items, the two valid-item lists, types, the menu-sprite draw
list and the script builtin dispatch table, because Colosseum keeps in the
DOL much of what XD keeps in `common.rel`. All 84 were measured dumping as
CSV on all six GameCube discs; `DolTableCSVCorpusTests` repeats that for one
disc per game (skips without a project — `GODDESS_DOL_TABLE_CORPUS` /
`GODDESS_COLO_DOL_TABLE_CORPUS` point it at one).

**A table's address is per-region and none of it is derivable.** A
`common.rel` chunk is named by pointer-index symbol, which is an ordinal and
survives a rebuild; a DOL chunk is named by **address**, so every table has
to be located on every build. Three sources, in descending order of trust:

- **The symbol map**, where the table has a name. `joutai_data` (status
  effects), `pokemon_tokusei_data` (abilities) and `item_waza_machine_no`
  (TMs) are named on all three XD builds, at the same sizes.
- **The game's own accessor.** `menuSpriteBiosGetPtr` is a generated
  four-instruction routine — `mulli` by the row stride, then `lis`/`addi` of
  the table — so it gives the address *and* the stride. That is what pinned
  the menu-sprite record's two shapes: 0x48 with five languages, 0x18 with
  one. XD is multi-language except JP; **Colosseum is the other way round**,
  single-language except PAL.
- **A content signature**, for a table nothing names and no accessor was
  found for: match every non-pointer column of a known build against the
  others. Colosseum's script builtin table and its menu-sprite draw list were
  located that way on PAL and JP, and both end exactly where the Dolphin SDK
  version string begins — the check that the match is the whole table, not a
  prefix of it.

**The legacy tool's per-region constants are a starting point, not an
answer.** Its XD values reproduce the shipped US addresses exactly, which is
what makes them worth porting — but four of its PAL addresses are 4 bytes
out, its JP menu-sprite table 12, two of its Colosseum addresses 8; its
Colosseum status-effect count is XD's (the real one is 86, not 87), its
second valid-item list is given the first's count (548, not 1220), and its XD
`Abilities` count of 123 is what the shipped type map carried — where the
game's own count word, the symbol's size and the first non-ability byte all
say **78**. A wrong count doesn't fail: it types 540 bytes of the next thing
as ability rows and swallows the chunks that follow. Every address and count
here is held to the same test — the table tiles its declared count exactly
into the space between its own label and the next.

**A type-map chunk whose address has no label is skipped in silence**, which
is what made a four-byte error look like "this region has no tables". So a
table's presence and row count are asserted against the map rather than
eyeballed in the output.

**A table that declares no count runs to the next label** — the rule the REL
side already used, and the only one that can be right when a DOL chunk's end
*is* the next label. It used to default to zero, which wrote an empty CSV and
pushed every byte of the table into the gap chunk behind it without saying so.
Declaring the count anyway is still worth it where the next label is far off:
after XD's `Abilities` the next one is 0x53A8 bytes on, so a derived count
would be wildly wrong — and a declared count is what the symbol-size check has
something to compare against.

**Colosseum's symbol maps ship too.** `GC6E`/`GC6P`/`GC6J.map` sit beside
XD's three, so a Colosseum DOL disassembly gets named functions and
per-object text folders like XD's, and `dolAssembly` rewrites the map after a
shift the same way. They are thinner than XD's — ~7,800 of Colosseum's
symbols are positional `zz_` names against ~500 of XD's — but a positional
name is still a chunk boundary, and the boundaries are what the data sections
need.

#### FSYS byte-identical rebuild

FSYS is a declared 1:1 target (see Philosophy). Measured against the real US
corpora (Colosseum + XD, `scripts/*/Build/Contents/files`):

- **LZSS re-compression is exact.** Re-compressing the decompressed payload of
  1205 real compressed entries reproduced the original stream byte-for-byte in
  **1205/1205** cases. The encoder matches Genius Sonority's, so compression is
  not an obstacle to 1:1 — this is why FSYS gets the exception.
- **Repack divergences are nameable and fixed:**
  - *Colosseum entry-metadata filler* — the packer leaves 12 bytes of `0x11` at
    `+0x34` in every entry-metadata block (constant across all 1028 entries of
    299 archives; XD zeroes the region). Modelled as
    `GeniusSonorityEngine.Data.FSYS.fileMetaDataFill`.
  - *Zero-entry archives* — the offset table and string table each occupy one
    0x10 unit even when empty (identical layout in all 33 such archives across
    both games). The writer reserves the minimum.
  - *Full filenames* — `Entry.filename` is a derived pretty form (stripped
    `_col`/`_cam`/`_scd`, mapped extensions) and is lossy. The archive's own
    string is preserved verbatim in `Entry.MetaData.fullFilename` and re-emitted.
  - *Unnamed file types* — `FileTypes` raw values are sparse and real archives
    carry values the enum doesn't name. The enum is `allowUnknownCases: true`
    so those round-trip as `FileTypes_<raw>`; previously they resolved to
    nothing and were written back as type 0.
- **Known exception:** the 33 zero-entry archives (14 Colo / 19 XD) hold 16
  bytes of uninitialised packer memory in their reserved string-table window
  — RAM addresses and fragments of unrelated filenames, different in every
  file and derivable from nothing the archive contains. Their *layout* is
  reproduced exactly; that window is not. Reproducing it would mean storing
  and replaying those bytes, which the default philosophy rules out. Revisit
  only if a zero-entry archive turns out to matter.

Verified by `FSYSRealCorpusFidelityTests`, which skips cleanly without ROMs
(`GODDESS_FSYS_LIMIT` raises the sample size, `GODDESS_FSYS_CORPUS` points it
at other dumps). 500 archives across both games currently repack byte-identically.

When adding FSYS behaviour, keep the pretty/raw split: derived names are for the
project filesystem, the stored raw string is what gets written back.

#### FSYS entry names

**An entry's stored name is not unique and was never meant to be.** Two things
follow, and getting either wrong silently loses files:

- **Duplicate names are ordinary.** A map's archive groups its files under one
  name — `D2_valley_1.fsys` holds six entries called `D2_valley_1`, told apart
  by file type — and a few archives repeat a name *and* type (`people_archive`
  stores two `agent_m_a2.dat`; XD JP repeats three more). The games' packer
  gives each entry its own copy of the string rather than pointing several at
  one, so `FSYSArchive`'s name table is built per entry and the pointers are
  kept **by index, never by name**. Keying them by name collapsed duplicates
  onto one offset, which is why the writer used to reject these archives
  outright and no Colosseum or XD disc could be rebuilt.
- **Unnamed entries carry the literal `(null)`.** Genius Sonority's packer
  printed an absent name through `%s` with a null pointer, so that string is
  what reached the disc: every PBR entry, and 1105–2104 per XD disc (all the
  streamed sound, the movies, the flash menus, some textures). Those are named
  `<archive stem>_<index>.<ext>` — `stm_bgm_ev_6brothers_000.ish` — via
  `scrubbedFilenamePlaceholderValue` / `projectFilename`, which applies to all
  three games. Two details are load-bearing: the **archive's own stem** is used,
  not the language-stripped base the folder routing works from (stripping makes
  `battle_disk_fr` and `battle_disk_ge` collide — 27 names on XD US, 84 on PAL;
  with the stem, nothing collides on any of the six GameCube discs), and an
  entry that is nameless but still carries a **full filename** keeps that real
  name (154 entries on XD US do, which is where `00seaside32.ish` comes from).

**Fonts are not pooled; every entry keeps its own file.** A `.fnt` is written
like any other entry, named `<stored name>_<index in its archive>.fnt`
(`D1_labo_1F_003.fnt`, `pda_menu_001.fnt`). The index is there because a stored
font name is only unique inside its own archive and is usually the archive's
name rather than the font's: `fight`, `world_map` and `M2_enter_1F` each name
two different fonts on the XD US disc. Entries that agree on name, bytes *and*
folder still share one file through the collision pass above, which is why XD
US's 205 font entries come to 194 files and Colosseum's 162 to 136.

They used to be pooled by content under a serial `Font_Data_<n>` — 26 files for
XD US — but that name renumbered whenever the set of fonts changed, taking the
atlas a user had been editing with it, and it could only ever name one of the
archives a font came from. Un-pooling costs under a megabyte per disc (XD US
919 KB → 1727 KB, Colosseum 951 KB → 1653 KB) and what it gave up is mostly one
336-byte file holding a single space glyph that 83 XD archives carry; the real
fonts (`jis_1`, `fight`, `world_map`) appear once or twice each. A project
dumped before this keeps its old names until it is dumped again.

**A font files under the fonts folder whichever archive it came from.** That is
rule 0 of `resolveFolder`, ahead of the per-archive rules that keep a misc or
scene archive's contents together, because `dumpFonts` and `pbrFontsDump` work
over that one folder and a font routed elsewhere would silently drop out of the
font pipeline — 7 of XD US's fonts and 1 of Colosseum's are in archives those
rules catch. Language variants keep their language subfolder
(`Data/Text/Fonts/French`), which the dump and build ops mirror.

#### Font atlases

The editable form of a `.fnt` is a greyscale PNG of every glyph plus a JSON
manifest. Three rules make that survive the trip back, and each cost real
fonts before it was one:

- **Cells are sized to the glyphs, not to the block header.** A block declares
  a glyph size, but it is nominal: Colosseum's 2920-glyph kanji sheet says
  21x21 while every glyph in it advances 22px. Cells a pixel too narrow put
  each glyph's last column in the next cell, where the glyph drawn there
  overwrote it. The cell a dump drew in is written into the manifest
  (`cellWidth`/`cellHeight`) rather than re-derived; metadata without them
  predates the field and was drawn at the header's size.
- **A glyph's stored width is its advance rounded up to a whole byte.** 4bpp
  rows are whole bytes, so an odd advance stores one column past itself in the
  low nibble of each row's last byte, and real fonts put stray values there —
  133 of Colosseum JP's 137 carry some. Drawing only `advanceWidth` columns
  dropped them.
- **A PNG is read back before it is handed out.** The encoder can emit a
  deflate stream that ends early — Colosseum JP's `D4_dome_4` atlas (528x40)
  comes back 19 660 bytes of the 21 160 it should, deterministically — so
  `GreyscaleImage.pngData()` decodes its own output and retries at another
  compression level, and `exportAtlas` throws instead of writing the zero-byte
  file a failed encode used to leave.

A batch build reports every failure at the end rather than stopping at the
first, the same way an FSYS pack does (`AssetBatchError.buildFailures`): one
unbuildable atlas used to leave 103 of Colosseum JP's fonts unbuilt, and the
game-side file a failed member would have replaced is left as the dump wrote
it, which is valid.

**ISD and ISH are the other way round from the type codes.** Type 0x28 is the
`I_SF` header and 0x2A the ADPCM stream it describes — every entry of each type
that stores a filename says so (48 of each per XD disc). The enum had them
swapped, so synthesized extensions described the wrong half. The two are paired
by filename stem downstream, so an archive holding exactly one of each gives
both the header's index; `stm_se_nakigoe_archive`'s 388 pairs are left
unpaired on purpose, because their halves interleave rather than running in
step (the first header's stream is the second stream entry) and numbering them
in parallel would pair them confidently and wrongly.

**The table of contents owns the group ID; the header only repeats it, and
whether it does is per-game.** `FSYSRegistry.groupID` comes from the table and
nothing else — the header's own value disagrees on real discs, so on rebuild it
is written from the table. Whether the word is written at all is
`writesGroupIDInHeader`, because the games differ absolutely rather than at the
margins: XD US populates it in 2,533 of 2,540 archives, Battle Revolution
leaves it zero in **all 1,095** of its own. So PBR sets the flag false and Colo
and XD leave it at the default `true`. Writing the table's value into every PBR
header cost 1,037 of its 1,095 archives their byte-identical repack, for a word
the game reads out of the table anyway.

A project carries its own serialized copy of both the enum and the engine data,
so one dumped before any of this stays self-consistent and repacks as it always
did. What it won't have is the fix: re-run setup to pick it up, and don't mix a
refreshed engine folder with registries dumped against the old one.

**A build reports every failure at the end, not the first one.** `packProject`
records what it couldn't write and carries on, so one bad member costs its own
file rather than leaving `Contents` half old and half new, and one run names
everything that needs fixing (`FSYSPipelineError.packFailures`).

**An artifact the pack can't turn back into game data stops its entry.** The
texture branches of `resolveArchiveEntries` used to fall through on a nil,
which left the entry's payload holding the *PNG's own bytes* — so the archive
was packed with a PNG file where the game expects a GTX, and the run reported
success. They now throw `unreadableTexturePNG` or `textureEncodeFailed`,
naming the file, and the failure joins the end-of-run list above; the bad
entry costs its archive rather than the disc. This was reachable: the
truncated PNGs the vendored swift-png bug produced are exactly the input that
triggered it, and a rebuilt `pda_menu.fsys` really did ship `\x89PNG` in place
of a texture.

#### Project output routing

**A disc path is unique; a basename isn't.** Everything a dump writes outside
an archive keeps the directory it sat in on the disc, nested under whatever
folder its file type routed it to (`FSYSProjectPipeline.outputFolder`). PBR
ships `homeBtn.arc` and five loose files under both `hb/HomeButton2` and
`hb/HomeButton3`; routing on basename alone had each pair overwrite itself and
the rebuild wrote one copy's bytes into both. A file at the root of `files/`
keeps its plain path.

**`platformDirectories` is the exception that skips type routing entirely.**
A disc directory named there mirrors its disc path under `platformBaseFolder`
(`/Platform`, a sibling of `/Assets`), so `hb/HomeButton2/homeBtn.arc` becomes
`/Platform/hb/HomeButton2/homeBtn.arc.json`. That content belongs to the
console rather than the game — PBR's two copies of the Revolution SDK's Home
Menu library, one per System Menu version, identical directory names on all
three discs — so it doesn't sort into the game's asset folders. Matching is by
prefix, so listing `hb` would catch every `hb/HomeButtonN`. Colosseum and XD
list none: the GameCube has no equivalent.

The rest of the PBR disc is game data in platform-shaped wrappers, and stays
routed as content: `opening.bnr` is the Wii channel banner (IMET at +0x40, U8
at +0x600) holding PBR's own art, and `wifi/child0*.srl` are DS Download Play
child binaries whose DS headers read `NINTENDO`/`NTRJ01` but whose payload is
the game's own Pokétch code. `zzzzzzzz.zzz` is 32 KB of zeroes, the disc
layout's filler.

**Where two entries still want one path, content decides.** Archives route by
type, per-archive subfolder, misc/scene category and per-archive flash-menu
folder first; whatever still collides is compared byte-for-byte, and a genuinely
different file becomes `filename (2).ext`. Identical files share the one path.

#### Nintendo LZ77 compression (Yaz0 / Yay0)

Lives beside LZSS in `GoDFoundation/Data/Compression/`, because a codec is a
pure byte-level algorithm with no game knowledge — same reasoning that puts
AES and SHA-1 in `Data/Crypto/`.

The two formats make **identical compression decisions** and differ only in
how the operations are written down: Yaz0 interleaves them into one stream,
Yay0 splits them across a mask/link/chunk table trio. So the search lives
once in `LZ77Encoder`, which emits a format-neutral `[LZ77Token]`, and each
codec is reduced to serializing that list. The CX family (`0x10`/`0x11`, for
NARC/GARC) is the same shape with different bounds and can reuse it.

`CompressionFormat` sniffs a stream by magic and hands back its codec. It is
a closed enum, not a registry: unlike file formats — which engines extend
with game-specific handlers — the set of compressed stream formats is fixed
knowledge about Nintendo's tooling, so there is no mutable state to inject.
Only self-describing formats belong in it. The bare LZSS stream
`LZSSCompressor` speaks does not qualify — it has no magic, and `FSYSArchive`
knows an entry is compressed from the entry's flags — but the 16-byte `LZSS`
header the archive puts in front of it does: `LZSSHeaderedCompressor` is
that form and `.lzss` names it, so one `detect` covers all three.
`FSYSArchive` keeps its own header code (it is a 1:1 target) and
`FSYSLZSSHeaderCrossCheckTests` pins the two to the same bytes.

`LZSSCompressor`'s EI/EJ/P geometry is honored in both directions. The
encoder used to hard-wire the 12/4/2 packing and the decoder's ring start
assumed a threshold of 2, so any other geometry silently mis-decoded; the
defaults are now the named `default*` constants, and the geometry has to
satisfy `EI + EJ ≤ 16` (a back-reference is two bytes) and
`1 << EI ≥ 2 × ((1 << EJ) + P)` (the encoder primes a lookahead below the
start). Default output is unchanged — `LZSSGoldenTests` and the FSYS corpus
test guard that.

**Not a 1:1 target,** and deliberately so — see Philosophy. Yaz0 is a
plausible future candidate (the reference encoder is known to reproduce many
retail `.szs` files exactly), but nothing is measured, because no game this
tool currently opens uses the format. Promoting it means acquiring a corpus
first, exactly as FSYS did. `LZ77Encoder` documents the one place it
knowingly diverges from the reference encoder.

Validation is by cross-check rather than round-trip: `ReferenceLZ77Decoders`
in the test target is a deliberately independent decoder pair written from
the spec, and every round-trip test also decodes its stream through those —
the same trick `WiiDiscFixtures` uses on the Wii crypto. A round trip alone
would pass if the encoder and decoder were wrong in matching ways. Full spec
in `Documentation/File Formats/Shared/Yaz0 Yay0 - Nintendo LZ77 Compression.md`.

#### PNG encoding (vendored swift-png)

`LZ77` and `PNG` are **vendored** under `Third Party/swift-png/`, a verbatim
copy of 4.5.1 carrying one local fix — not a SwiftPM dependency. The fix is in
the deflator's final flush: upstream picks the last block's type from the
leftover input count alone, so when the matcher stops with 0-2 bytes still
queued it writes a stored block for those and **silently discards every term
already in the match buffer**, along with the 3 bytes held in the window
pipeline. The result is a structurally valid PNG carrying the Adler-32 of the
whole input, so the only symptom is that it fails its own checksum when read
back.

Three real images, one flash-menu texture and two font atlases, lost between
1,500 bytes and everything-but-one. Which images it hits depends on where the
matcher happens to stop, so it moves with the compression level *and* the
caller's chunk sizes: the three had failing levels {0,1,2,3}, {0,1} and
{5,6,7}. **There is no safe level, and raising the level is not a mitigation** —
`GreyscaleImage.pngData()`'s old retry-and-decode ladder only ever caught the
cases that failed at whichever level it tried first. All three images are
checked-in fixtures (`PNGDeflateTruncationTests`).

All three encoders — `GoDImage`, `GoDIndexedImage`, `GreyscaleImage` — encode
at level 0 and do not verify. Details, measurements and how to re-sync with
upstream: `Third Party/swift-png/README.md`.

#### Editable asset layout

**A format's nesting is one fact, and both directions read it.** `AssetLayout`
(`GODSDK/Operations/ColoXD/Assets/AssetSupport.swift`) says whether a format's
artifacts get a folder each — `.perAssetFolder` for GSW and ATX, whose
companion files are named after something *inside* the asset (a menu's
textures by tag id, a texture's frames from zero) and would otherwise
overwrite each other — or sit flat beside their neighbours, which is
everything else. The dump nests by it and the build un-nests by it.

It is a shared constant rather than a flag on each side because when only the
dump knew, `buildFlashMenus` mirrored the per-menu folder into its output too
and wrote `<out>/French/title_fr_010/title_fr_010.gsw`, one level below the
game-side file it was meant to replace. 167 of XD PAL's 168 rebuilt menus
landed where the packer never looks, and the run reported success. `buildATXs`
had the same shape and no disc to expose it.

A batch build also **warns when there is nothing at the path it is about to
write**, since these operations replace files the dump unpacked: an output
path with nothing at it means the two sides disagree about where the game-side
file lives, which is what that bug looked like from the outside.

#### Compression operations

`compress` / `decompress` and the bulk `compressFiles` / `decompressFiles`
(`GODSDK/Operations/Compression/`) are engine-free, hand-authored flat
operations over the codecs above. `CompressionOps.Format` names `yaz0`,
`yay0`, `lzss` (headered) and `lzss-raw` (bare stream — undetectable, so it
must be named). `decompress` sniffs the format when none is given, checks a
named one against the magic, and takes an optional `range` for a stream
embedded in a larger file; the bulk form skips and counts files that aren't
streams. `Options` is one flat object whose fields are validated per format
and direction — a field the format doesn't read is an error, never ignored —
because the codecs only `assertionFailure` on bad values. Derived names
append the format's extension on the way out and strip a known one (or
append `.bin`) on the way back, so a folder can be decompressed onto itself.
Documented in `Documentation/GODDESS Configuration Reference.md`.

#### Running external programs

`runExecutable` (`GODSDK/Operations/Executable/`) launches a program at a
given path with a list of arguments and a list of standard-input lines, so a
chain can reach a tool GODDESS doesn't implement — a converter, a patcher, an
emulator, a project's own script — without leaving the config file. It knows
nothing about what it launches, which is the point: no engine, no format, no
interpretation of the output.

Three decisions are load-bearing. **There is no shell**: arguments are passed
one array element per argument and verbatim, so `/bin/sh -c` is how a config
asks for globbing or pipes, and nothing is ever re-split on spaces behind the
user's back. **The child never inherits GODDESS's streams** — it gets pipes
for all three, so it can't swallow keystrokes meant for the tool, and its
printing doesn't interleave with the log; standard input is closed after the
configured lines, which is what makes a program that reads to EOF return.
**A non-zero exit stops the chain** unless `failOnNonZeroExit` says
otherwise, but a program killed by a signal is always an error: it never
chose a status, so there is nothing to tolerate.

The launcher itself is `ExternalProcess` in `GoDFoundation/Environment/`, next
to the other host facts (byte order, path convention) for the same reason the
codecs sit in `Data/Compression/`: spawning a process is not game knowledge.
It drains stdout and stderr on their own threads — draining them in turn, or
only after `waitUntilExit`, deadlocks on any program that prints more than a
pipe buffer — and ignores SIGPIPE on first use, since a child that exits
without reading its input would otherwise kill the tool.

`FileSystemTree.resolvedPath(of:)` exists for this operation: a `./` path in
a config resolves against `rootFolder`, but a child process would resolve it
against its own working directory, so the path is extended before it leaves
the tree. It is a no-op on every tree without a current directory.

#### Nintendo archives (U8 / NARC)

A `Nintendo` engine, separate from the game engines, holding Nintendo's own
container formats. It carries **no game knowledge** on purpose: an archive's
layout is identical whichever title it came from, so per-game routing of what
comes *out* of an archive stays in the game engines.

**Byte order is read off the direction the magic is spelled.** Nintendo's
tooling writes a four-character code as a machine word, so porting a format
to the opposite endianness reverses its own magic. The two formats run
opposite ways round, which is the trap:

| Format | Native to | Forward | Reversed |
|---|---|---|---|
| U8 | GameCube (BE) | `55 AA 38 2D` → **big** | `2D 38 AA 55` → **little** |
| NARC | DS (LE) | `NARC` → **little** | `CRAN` → **big** |

So `NARC` forwards means *little*-endian, and PBR's big-endian port is the
one reading `CRAN`. NARC's section codes flip too (`BTAF`/`BTNF`/`GMIF` ↔
`FATB`/`FNTB`/`FIMG`). `NintendoArchiveSignature.detect` answers both
questions from those four bytes; `ArchiveReader`/`ArchiveWriter` take the
byte order as a parameter, so neither endianness is a bolt-on to the other.

**Both are 1:1 targets, verified on the real corpus.** All 30 PBR PAL
archives (24 U8 + 6 NARC) repack byte-identically. Geometry is fully
derivable — U8's data region is `align32(rootOffset + headerSize)`, every
file starts on that boundary, gaps are zero, and names are written in node
order with no de-duplication. Only the alignment and pad byte are engine
data.

**The one exception:** a nameless NARC's 8-byte name-table body puts its two
16-bit fields in the opposite order on the two platforms. Nothing in the
corpus disambiguates which field is which, so the parser keeps the original
bytes (`rawNameTable`, carried through the manifest) and replays them.

**Entry order is load-bearing.** A U8's node table is a preorder walk, and a
nameless NARC addresses files purely by index — in `waza_seq_rev.narc` the
index is the move ID. `U8Archive` therefore models the tree as a flat ordered
list rather than reconstructing it, and the manifest preserves order.

**Project layout** follows FSYS: `<name>.json` manifest beside a `<name>/`
folder of contents. `FSTRegistry.EntryType.nintendoArchive` points at the
manifest, and the FST rebuild repacks from it. Four operations —
`nintendoArchive{Dump,Build}` and `nintendoArchives{Dump,Build}` — cover
single and bulk. One pair for both formats, because the magic already says
which format it is; the bulk dump identifies by magic, not extension.

Full spec in `Documentation/File Formats/Shared/U8 NARC - Nintendo Archives.md`.

#### Colosseum / XD messages

A `.msg` is a 0x10 header, an 8-byte entry per string (`id`, `offset`) and a
string pool. Declared a 1:1 target, measured on **every MSG entry on all six
GameCube discs** — 2312 entries, 427,420 strings (Colosseum US 168 / PAL 811
/ JP 169, XD US 211 / PAL 770 / JP 183): binary → `MSGFile` → binary
reproduces every byte, and so does the round trip through the editable JSON
(`MSGRealCorpusFidelityTests`, skips without a corpus, `GODDESS_MSG_CORPUS`).

**The pool is not written in entry-table order.** 1339 of the 2312 files lay
their strings out in some other order, so writing the pool in table order
produced the right bytes in the wrong places — a file of the same length that
differed throughout, which is what 60 of Colosseum US's 131 messages did on
the last audit. An entry therefore carries `poolOrder`, the rank of its string
in the pool, and the writer lays the pool out in that order. It is omitted
from the JSON when the pool already runs in entry order, and an entry without
one — a string the user added — is laid out after every ranked string.

Three smaller facts from the same corpus: the pool is **contiguous, unpadded
and unaligned** (rounding string starts up to an even address is what used to
cost the DOL-embedded XD tables +546 bytes), **no two entries share a
string**, so each entry gets its own pool slot, and **16 files declare no
entries at all**.

**An entry owns every byte up to where the next string starts.** That is what
bounds the read, and it is load-bearing rather than tidy: the pool is
contiguous, so the next string's address *is* this one's end, and a parser
that instead trusts its own reading of the characters will run past the end
the moment it misreads a control code. Only two runs are genuinely
unclaimed — before the first string and after the last — and those are where
`detachedStrings` and `trailingBytes` come from.

**A string the codec can't reproduce keeps its bytes.** After reading one,
the parser re-encodes it and compares; on a mismatch the bytes win
(`Entry.rawBytes`), the same verify-before-you-trust rule the typed table
exporters follow. Two strings on the six discs need it, both in Colosseum
JP's move viewer: one ends on a parameterless `FFFF 09` where all 239 other
appearances of that code carry a parameter byte, and without the check the
parser ate the terminating null word as that parameter and swallowed the
next string — 50 bytes of duplicated text in a file that had been reported
as round-tripping.

**A pool string that no entry points at is kept.** XD JP's `M6_tower_1F.msg`
declares one entry and carries 450 bytes of unreferenced strings ahead of it;
they are parsed out of the leading run and held as `detachedStrings` — text,
not opaque bytes — because dropping them would shrink the file and move every
later offset.

**An embedded table keeps its container's padding.** A `.msg` file ends on
its last terminator, but a table inside a DOL or REL is padded out to a
4-byte boundary and that padding reaches the parser as part of the chunk —
1, 2 or 3 zero bytes between consecutive tables in XD's `common.rel`. It is
held as `trailingBytes` and written back, so a rewritten chunk is the same
length as the one it replaces. All 9 tables embedded in XD's and
Colosseum's `common.rel` round-trip byte-identically at their chunk extent,
through the binary and the JSON alike — and with them, a typed dump of the
whole module does too (see "REL source tree"), which is where the 8-65
bytes such a dump used to lose were going.

#### PBR strings

Battle Revolution's text is a `MESG` string table, which shares the `.msg`
extension with the Genius Sonority MSG and nothing else — different header,
different addressing, different terminator, unrelated control codes.
`MSGFile` now rejects a `MESG` rather than misparsing one: PBR keeps its
count at +0x06 where the GS parser reads +0x04, so a PBR file used to parse
as **zero strings and no error**, and building from that would have written
an empty file over every string on the disc.

**Game data never names a table.** A message field holds a global string id;
`common.fsys` member **91** (US/PAL) or **119** (JP) is a dense array over
those ids saying which table holds each one and at what index. The mapping
is a bijection — 21,812 ids over four tables on the PAL disc, accounting for
every string exactly once. Both halves of a lookup are array indexing, so
nothing depends on a table's strings being in id order; retail happens to
be, but a rebuild may place a string anywhere as long as the directory
follows it.

**Where the tables live is per-region, and nothing about it is guessable.**
Tables 2 and 3 ship a byte-identical second copy in another archive, so
there are always more entries than files: PAL has 30 entries for 20 files
(`mes_*`, `menu_btutorial*`), US has 34 — four more English copies in
`menu_bpass2`, `menu_name2` and `menu_fight_s` (that US set is PBRHex's
hardcoded list, which is why it doesn't match a PAL disc) — and **JP has no
`mes_*` archives at all**: its one language lives in `common.fsys`[35],
`menu_bpass2` and `menu_fight_s`/`menu_name2`. Write only one copy and the
game reads stale text from whichever it loads. German is `GRGR` and Spanish
`SPSP` — the legacy tool had those two swapped.

**A declared table needn't be shipped.** JP's directory declares four tables
and the disc has three (no battle tutorial), with no id pointing at the
fourth. It still occupies its slot — dropping it would renumber the tables
after it — so the catalogue keeps an empty section for it and the build
writes nothing there while still counting it.

**A table's languages need not be the same length.** On the US disc English
runs past the others — 9995 strings to 9991 in table 1, 9233 to 8737 in
table 2 — with the shorter copies simply stopping, their last entries empty,
and only four ids reaching past the French end. Index N still means the same
id in every language, so a language may end early but may not skip a string
and resume; the catalogue models that as a row carrying text only for the
languages that reach it, and the build rejects a language that resumes after
a gap. PAL has every language at the same length, which is exactly why this
had to be checked on more than one disc.

**One document, `Source/Text/Strings.json`** (`pbrStringsDump` /
`pbrStringsBuild`): a section per table, a row per id, and that id's text in
every language on the row — which makes "one index per id, shared by every
language" structural instead of a rule to check. Everything derivable is
derived: a table's id is its position, a string's index is its row's
position, and the directory is rebuilt from the rows. **Ids are the only
stable reference and indexes are the build's business**, so a row can be
inserted anywhere without changing what an existing id means. Ids must stay
dense from 1 (the directory is indexed by id): new strings go at the end,
and a string is retired by blanking its text, not by deleting its row.

The operations read and write only the loose binaries in the unpacked tree —
`packPBR` remains the only thing that writes archives, so a strings build
belongs ahead of it, like the font build. Each target is read before it is
written: it carries the one header field the document doesn't (the id
high-bits word at +0x04, zero on every retail table) and it declares its own
table and language, so writing over the wrong file fails instead of
shipping.

`gsPBR` in `GSCharacter` is the character codec, shared with nothing
Colo/XD-specific. Parameter lengths are `{0x0001: 2 + characters, 0x0002: 2,
0x0003: 2, 0x0005: 2, 0x8011: 4}` and zero for everything else, which is
what makes the bodies tile exactly on all three discs — a wrong length
desynchronises the walk rather than failing. The ~90 unidentified
substitution codes round-trip as `{xx xx}` hex tokens.

**Furigana is `{Furigana:けん:剣}`** — reading, then what it annotates. The
separator can't be a space: 58 of the JP disc's 6,441 markers have a *space*
as their kana or kanji, so a space-separated token was indistinguishable
from its content and those strings silently failed to re-encode. No marker
on the disc contains a colon, and one that did would fall back to raw bytes
rather than round-trip wrongly. JP is the only disc with furigana at all,
which is why this only showed up once all three were tested.

Verified on **all three discs** by `PBRStringRealCorpusTests` (format) and
`PBRStringsRealCorpusTests` (operations): every entry and the directory
repack byte-identically — PAL 30 entries / 156,100 strings, US 34 / 170,616,
JP 5 / 29,982 — and the whole disc → document → disc round trip through the
operations reproduces every one. Both skip without a dump and are
region-agnostic; `GODDESS_PBR_FILES` points them at a `DATA/files` folder.

Full spec in `Documentation/File Formats/Battle Revolution/MESG - String Tables.md`.

### Nintendo Archive Formats (future support candidates)

**GameCube/Wii:**
| Format | Extension(s) | Description |
|--------|-------------|-------------|
| RARC | `.rarc`, `.arc`, `.szs` | JSystem resource archive (Mario Sunshine, Zelda Wind Waker). Often Yaz0-compressed. |
| U8 | `.arc`, `.szs`, `.app` | **Implemented.** Primary Wii archive for non-JSystem games (NSMBW, MKWii). Magic: `U\xAA8-`. |
| WAD | `.wad` | Installable Wii channel/title container (ticket + TMD + content). |
| WBFS | `.wbfs` | **Implemented (read).** Block-mapped Wii disc container; setup restores it as a lazy `GoDReadable` view (`WBFSDiscImage`), never a buffer. See `Documentation/File Formats/Shared/WBFS - Wii Backup File System.md`. |
| WIA/RVZ | `.wia`, `.rvz` | Compressed GC/Wii disc images. RVZ is the newer variant. |
| BRRES | `.brres` | NW4R resource container (models, textures, animations). |
| BRSAR | `.brsar` | NW4R sound archive. |

**DS/3DS:**
| Format | Extension(s) | Description |
|--------|-------------|-------------|
| NARC | `.narc` | **Implemented** (both endiannesses). Nitro ARChive. Primary DS archive with FNTB + FATB sections. |
| GARC | `.garc` | Game ARChive. Used heavily in Pokemon X/Y, ORAS, Sun/Moon. |
| DARC | `.arc` | 3DS successor to NARC. |
| SARC | `.sarc`, `.szs` | Replaced U8 on 3DS/Wii U/Switch. Often Yaz0-compressed. |

**Wii U / Switch:**
| Format | Extension(s) | Description |
|--------|-------------|-------------|
| SARC | `.sarc`, `.pack`, `.szs` | Ubiquitous archive across Wii U and Switch first-party titles. |
| BFRES | `.bfres` | Models, textures, animations, shaders. Version varies by platform. |
| BARS | `.bars` | Audio resource archive (BFWAV/BFSTP entries). |
| NCA | `.nca` | Switch encrypted content archive (holds ExeFS, RomFS). |
| XCI/NSP | `.xci`, `.nsp` | Switch cartridge dump / eShop download containers. |

**Cross-platform compression:**
| Format | Platforms | Description |
|--------|-----------|-------------|
| Yaz0 | GC, Wii, 3DS, Wii U, Switch | **Implemented.** LZ77 variant, wraps archives as `.szs`. Nintendo's standard for 20+ years. |
| Yay0 | GC (early) | **Implemented.** Predecessor to Yaz0. |
| LZ10/LZ11 | DS, 3DS | Nintendo SDK LZ variants. |
| ZSTD | Switch (newer) | Replaces Yaz0 in newer titles (e.g., TotK). |

### Wii ISO Encryption (implemented)

Wii discs use **AES-128-CBC** encryption. Structure:

1. **Unencrypted disc region:** disc header at 0 (Wii magic `0x5D1C9EA3` at 0x18),
   partition table at 0x40000, region settings at 0x4E000, and a second magic
   word `0xC3F81A8E` at 0x4FFFC. The magic at 0x4FFFC lives outside every file
   the dump exports, so a rebuild has to re-emit it from a constant
   (`WiiISO.discMagicWord2`).
2. **Each partition contains:**
   - **Ticket** (unencrypted): holds the title key (AES-encrypted with the Wii common key, IV = title ID)
   - **TMD** (unencrypted): content hashes
   - **H3 hash table** (unencrypted): 0x18000 bytes, top-level integrity hashes
   - **Partition data** (encrypted): game content in 0x8000-byte clusters
     (`dataGroupSize` in the engine, "group" in some call sites)

3. **Cluster structure** (each 0x8000 bytes):
   - 0x000-0x3FF: hash block (H0 table @0x000, H1 table @0x280, H2 table @0x340)
     — encrypted with the title key, IV = all zeros
   - 0x400-0x7FFF: user data — encrypted with the title key, IV = bytes
     0x3D0-0x3DF of the **ciphertext** hash block (not the decrypted one)

4. **Hash chain**: H0 = SHA-1 of each 0x400 chunk (31 per cluster) → H1 = SHA-1 of
   a cluster's 31 H0 → H2 = SHA-1 of a subgroup's 8 H1 → H3 = SHA-1 of a group's
   8 H2, stored in the H3 table. A cluster's hash block carries its own 31 H0, its
   subgroup's 8 H1 and its group's 8 H2. The TMD's content-0 SHA-1 (TMD +0x1F4)
   covers the H3 table, which is what links the tree to the signed metadata.

**Decryption flow:**
1. Read encrypted title key from Ticket (offset 0x1BF)
2. Read title ID from Ticket (offset 0x1DC) — used as IV
3. Decrypt title key with AES-128-CBC using Wii common key + title ID IV
4. Decrypt each 0x8000-byte cluster using the title key

**Offsets are stored >> 2 inside a partition.** This is the single easiest thing
to get wrong, and it applies to the partition header (TMD/cert/H3/data offsets,
data size), boot.bin (`main_executable_offset`, `fst_offset`, `fst_size`,
`max_fst_size`, `user_data_offset`) **and** each FST entry's `file_offset`. FST
entry *sizes* are plain byte counts on both platforms. `DolphinFST` takes an
explicit `offsetMultiplier` for this — the Dolphin engine's value is 1, so the
Wii engine's `disc.fstOffsetMultiplier` (4) must be passed in from
`WiiPartition`; forgetting it silently reads user files at a quarter of their
real offset.

**What a rebuild does:** re-lays the DATA partition's filesystem, rebuilds the
whole H0/H1/H2/H3 tree, relinks the TMD content hash to the new H3 table and
fakesigns the TMD. The ticket is re-emitted verbatim (its signature covers the
title key, which doesn't change). Partition data is zero-padded up to a whole
64-cluster group. UPDATE/CHANNEL partitions have no game filesystem: they are
dumped and rebuilt as one opaque decrypted blob (`/sys/partition_data.bin`).
`encryptedData` does **not** pad to disc capacity — the separate `fillISO`
operation does that, and the generated build config already chains it.

**Validation:** `WiiISORoundTripTests` (engine level) and
`WiiOperationTests.testWiiDumpThenBuildRoundTripsASyntheticDisc` (operation
level) run decrypt → rebuild → decrypt over a synthetic encrypted disc built by
`WiiDiscFixtures`. That fixture is a deliberately independent encoder — written
from the spec with raw writes at canonical offsets, not by calling `WiiCrypto` —
so the tests cross-check the production code instead of round-tripping against
themselves. They also verify the rebuilt hash tree and TMD link with their own
AES/SHA walk.

Validated on a real retail disc too: decrypt → rebuild → decrypt of Pokemon
Battle Revolution PAL (RPBP01, 4.7 GB) produced 1716/1716 files with identical
names and sizes, **1711 byte-identical**. The five that differ are the ones that
have to: `boot.bin` and `fst.bin` (layout re-derived), `h3.bin` (tree rebuilt)
and both `tmd.bin` (content hash relinked to the new H3, then fakesigned). Not
yet booted in an emulator. Release build: ~58 s to decrypt, ~3 min to rebuild,
~4.8 GB peak RSS — the encrypt path holds whole partitions in memory, so a
dual-layer disc would need streaming.

**Implementation notes:**
- Pure Swift implementations of AES-128-CBC and SHA-1 (no CryptoKit/CommonCrypto — those are Apple-only, not cross-platform)
- Common key must NOT be in source code — load from user config file
- Reference: Dolphin `VolumeWii.cpp`, Wiimm's wit `lib-std.c`
- wit obfuscates the key via XOR masks + SHA-1 derivation at startup (effectively hardcoded but not as plaintext)
- AES throughput is ~32 MB/s release / ~0.25 MB/s debug, so anything touching a
  whole disc needs a release build, and tests must stay near the one-group
  (2 MB) minimum

### ISH/ISD Audio Format Spec

Implemented: `ISFFile` + `ISFDSPADPCM` (decode and encode), reachable as `dumpAudio{,s}` / `buildAudio{,s}` in the ColoXD chains and as `convert` format `ish`. The spec below is what they implement.

The `.ish` (header) + `.isd` (data) pair uses **Nintendo GameCube DSP ADPCM** (4-bit ADPCM with linear prediction). Magic bytes: `I_SF`. Already registered as file types in the GeniusSonority engine (ISD = 0x28, ISH = 0x2A).

**ISH header (big-endian):**
| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Magic: `I_SF` |
| 0x04 | 4 | Tool date (hex, e.g. `0x20040109`) |
| 0x08 | 4 | Sample rate |
| 0x0C | 4 | Sample count |
| 0x10 | 4 | Stream size (bytes) |
| 0x14 | 4 | Channel count |
| 0x18 | 4 | Interleave size |
| 0x1C | 4 | Loop flag (0 = no loop) |
| 0x20 | 4 | Loop start (byte offset) |
| 0x24 | 4 | Loop end (byte offset) |
| 0x40+ | 0x40/ch | 16 coefficient pairs (int16 BE) per channel |

**DSP ADPCM decode (per 8-byte frame -> 14 samples):**
1. `scale = 1 << (frame[0] & 0x0F)`
2. `coef_index = (frame[0] >> 4) & 0x0F` -> select coefficient pair
3. For each of 14 nibbles: `sample = ((nibble * scale) << 11 + 1024 + coef1 * hist1 + coef2 * hist2) >> 11`, clamped to Int16 range
4. Maintain 2 history values per channel across frames

**Encoding** requires LPC coefficient calculation (see gc-dspadpcm-encode by jackoalan, MIT license).

**ISD data:** Raw interleaved DSP ADPCM frames. Channels alternate in blocks of `interleave_size` bytes.

**The workflow this replaced:** extract from FSYS -> use vgmstream CLI or Audacity with vgmstream plugin -> WAV. The "Audacity fork with Nintendo support" is actually standard Audacity + the vgmstream input plugin.

**Reference implementations:**
- vgmstream `src/coding/ngc_dsp_decoder.c` + `src/meta/ish_isd.c` (decode, MIT-like)
- gc-dspadpcm-encode (encode, MIT)
- VGAudio C# (both encode + decode, MIT)

**Implementation notes:**
- Pure integer arithmetic (bit shifts, multiplies, clamps) — no external deps needed
- Core decoder is ~30-40 lines, main complexity is interleaved channel handling
- WAV output: standard 44-byte RIFF header + interleaved 16-bit LE PCM
- Loop offset to sample: `samples = (byteOffset * 14) / 8 / channelCount`

### Data Layer

- **GoDData**: Core data wrapper with endian-aware reads/writes, position tracking, string encoding
- **FileSystemTree protocol**: Unified abstraction over on-disk (`FileSystem`) and in-memory (`InMemoryFST`) filesystems
- **StructData / StructDefinition / StructMap**: Binary structure mapping system — defines layouts in JSON, reads/writes binary data accordingly

## Coding Conventions

### Naming
- **American spelling, everywhere.** Identifiers, comments, doc comments, log
  messages and Markdown all use `-ize`/`-ization` and `color`, not `-ise` or
  `colour`. Swift's own APIs are American (`initialize`, `serialized`,
  `normalized`), so mixing the two means guessing which convention a given
  symbol follows.
- **Types**: PascalCase (`FSYSArchive`, `GoddessConfig`)
- **Properties/methods**: camelCase (`fileMetaDataPadding`, `readFile`)
- **Constants in engine data**: SCREAMING_SNAKE_CASE
- **Abbreviations**: `GS` (Genius Sonority), `XD`, `Colo`, `PBR`, `FST` (File System Tree), `FSYS`
- **Struct property names are matched exactly.** A property declared
  `file_data_pointer` is read as `header.file_data_pointer` — lookup does not
  fold underscores, spaces or case, and names are stored and serialized
  verbatim. (Folding them used to make `maxHP`, `max_hp` and `maxhp` the same
  field, so a write could land on the wrong offset; it also meant a serialized
  engine reloaded with different names than it was written with.) A name must
  start with a letter or `_` and contain only letters, digits and `_`;
  `Engine.getStruct` rejects anything else, and rejects duplicates, at load
  time. A near-miss lookup logs a "did you mean" warning in debug builds and
  carries the suggestion in `StructError.MissingKey`.
- **Enum case names are looser than property names**, deliberately: a property
  name is a JSON key and a `@dynamicMemberLookup` member, so it has to be an
  identifier, while a case name is only ever a *value*. A case name must start
  with a letter or `_` and contain no whitespace — punctuation is fine, and real
  enums depend on it (`FsysGroupIDs` names its cases after archive filenames,
  `B1_1.fsys`). The two restrictions each close an ambiguity: a leading digit or
  sign would be indistinguishable from the raw value the name stands for (an
  unnamed value serializes as its integer), and whitespace would break
  `Enum.Case`'s `"<name> = <rawValue>"` codec. Enforced by
  `Enum.isValidCaseName`, checked when an engine folder loads and when a struct
  resolves an `.enumeration` reference.

### File Organization
- One primary type per file
- Engine subdirectories: `Constants/`, `Enums/`, `Structs/`, `File Formats/`, `Extensions/`
- Each engine subfolder has an `entries/` directory for individual definitions
- Operations organized by game: `Gamecube/`, `ColoXD/`

### Patterns
- **No type casting.** `as?` / `as!` / `is` against a concrete type are not
  allowed without an explicitly cleared exception. A cast is a capability
  question asked at runtime, and the answer belongs in the type system: add the
  requirement to the protocol with a default implementation, or take the
  concrete type as a parameter so the caller supplies it. `GoDReadable.allData`
  is the worked example — it replaced `self as? GoDData`, and now a readable
  says for itself whether it can hand over a whole buffer.
  `FileSystemTree.setExecutable` is another: a default no-op on the protocol
  instead of `(fileSystem as? FileSystem)?.setExecutable(…)`.
  Not covered by this rule: narrowing `Any` that came out of
  `JSONSerialization` (there is no static type to recover), Foundation
  bridging, and `as` coercions that can't fail.
- **Don't collapse a `GoDReadable` to `GoDData` unless the work needs a
  buffer.** The point of the opaque readable is that it can optimize behind the
  caller's back — `GoDStreamedData` reads windows off disk, and
  `WiiDecryptedPartitionView` decrypts groups on demand. Calling `allData`
  throws that away, so it should appear where whole bytes are genuinely
  required (writing the file elsewhere, feeding a compressor) and nowhere else.
  A parser that only needs `read(atAddress:length:)` should take a
  `GoDReadable`.
- Protocol-based abstractions (`Engine`, `FileSystemTree`, `FileFormat`, `Logger`)
- Associated types for engine customization
- `Codable` for all config/persistent types
- `@_exported import` in engine modules for re-exporting dependencies
- `guard let ... else { throw }` for error handling
- `ErrorTrace` for call stack context on errors
- Operations return `Void` and `throw` on failure
- **Operations are thin wrappers**: GODSDK operation files map config values to engine function parameters and call engine functions. All domain logic (parsing, encryption, data transformation) lives in the appropriate engine module. Operations load engines from config paths, invoke engine functions, and write results via FileSystemTree.
- **Cross-platform by default**: Avoid Apple-only frameworks (CryptoKit, CommonCrypto, etc.) in the CLI/SDK. Prefer pure Swift implementations for algorithms (AES, SHA-1, etc.) to maintain Linux/Windows portability.

### Documentation
- **Credits & references**: When referencing the work or documentation of others during implementation, update `Documentation/Credits & References.md` with proper attribution. TODO: retroactively add credits for the PowerPC disassembler/assembler implementation.
- **Assembly Analysis**: XD's PowerPC disassembly (in `scripts/Disassembly-XD/`) is progressively documented under `Documentation/Assembly Analysis/`. Layout: `Files/` per-source-file breakdowns, `Data Structures/`, `Globals/`, `Enums/`, `Lifecycle/`, `Overview/`. Machine-readable indexes live in `_index/`. Two helper scripts under `scripts/analysis/` back this up: `index_disasm.py` rebuilds the indexes, `xref.py` answers callers/callees/data-ref questions. When doing deep analysis on a new module, start by upgrading its auto-generated stub at `Files/<module>.md`.

### Testing
- Tests in `Tests/Shared Tests/` (dependency + engine targets) and `Tests/Products Tests/` (GODOps)
- Target: as close to 100% coverage as possible
- **Corpus tests** (anything reading a real ROM, dump or sample from disk) must `throw XCTSkip` when the file isn't there, never `return` silently or assert — a vacuous pass hides a broken corpus and a failure blocks every other machine. Each takes a `GODDESS_*` environment override for the path (`GODDESS_FSYS_CORPUS`, `GODDESS_REL_CORPUS`, `GODDESS_WBFS_SAMPLE`, …) with the on-disk default as fallback.
- **Operation tests** (`GODOpsTests`): two layers, both required when adding an operation.
  1. *Routing*: `DispatchRoutingTests` feeds a JSON config through `GODOps.runConfig` with a `SpyOperationHandler` (the `OperationHandler` seam in `Dispatch.swift`) and asserts the case + decoded parameters. Adding a `GoddessConfig.Operations` case means extending the handler protocol, `EngineOperationHandler`, the spy, adding a routing test, an `OperationName` case, and a marker line in `Documentation/GODDESS Configuration Reference.md` (see "Operations").
  2. *Operation body*: `<Domain>OperationTests` runs the real operation against an `InMemoryFST` (absolute paths only) with synthetic inputs — engines serialized via `installEngine` (`Helpers/OperationTestSupport.swift`), input bytes built in-memory or from `FixtureCatalog` models — and asserts output tree contents byte-exactly where guaranteed.

## Current Progress

### Done
- [x] Core infrastructure (GoDFoundation, GoDData, Structs, FST)
- [x] Engine protocol and all engine shells
- [x] GameCube ISO dump (extract boot.bin, fst.bin, main.dol, bi2.bin, apploader, user data)
- [x] GameCube ISO rebuild
- [x] FSYS archive parsing and extraction
- [x] LZSS compression/decompression
- [x] Yaz0 + Yay0 compression/decompression, shared `LZ77Encoder`, and
      `CompressionFormat` magic sniffing (see "Nintendo LZ77 compression")
- [x] `compress` / `decompress` / `compressFiles` / `decompressFiles`
      operations over Yaz0, Yay0, headered LZSS (`LZSSHeaderedCompressor`,
      `CompressionFormat.lzss`) and raw LZSS, with per-format options and a
      decompress byte range (see "Compression operations")
- [x] `runExecutable` — run a program on the host with launch arguments and
      standard-input lines, capturing its output (see "Running external
      programs")
- [x] Nintendo engine: U8 (`.arc`) + NARC (`.narc`) parse/rebuild, big and
      little endian, byte-identical on all 30 real PBR archives; manifest +
      FST `nintendoArchive` entry type + single/bulk dump & repack ops
      (see "Nintendo archives")
- [x] Generic GameCube card metadata — banner, animated icon and comment
      strings derived from any save's own directory entry and dumped as
      PNGs plus readable text; per-game body regions and metadata
      checksums declared as engine data; 27/27 real saves round-trip
      byte-identically (see "GCI saves")
- [x] Project setup from ISO (auto-detect game, create folder structure, generate configs)
- [x] Configuration system (JSON configs, operation chains, toggle enable/disable)
- [x] Logging framework
- [x] GTX texture decode + encode (all pixel formats, palette rebuild)
- [x] ATX wrapper decode + encode (1:1 roundtrip on wrapper; texture body reuses GTX)
- [x] GSFont parse + rebuild (byte-identical) and atlas export/import — `.fnt` → PNG atlas + JSON → `.fnt` is byte-identical on every font of XD US (194), Colosseum US (136) and Colosseum JP (137), at both the format level (`GSFontAtlasCorpusTests`, skips without a dump, `GODDESS_FONT_CORPUS`) and through `dumpFonts`/`buildFonts`
- [x] GSW flash menu parse + serialize (byte-identical non-texture bytes)
- [x] ColoXD dump ops: `dumpXD` / `dumpColosseum` (FSYS unpack, every member routed by type into the asset folders `GeniusSonorityEngine.Data.FSYS` names), fonts, flash menus (GSW → PNG + metadata), messages (MSG → JSON), ATX, audio (ISH/ISD → WAV), Colosseum scripts
- [x] ColoXD build ops: `buildXD` / `buildColosseum` (FSYS repack from the FST registry), FST, GSfsys TOC, fonts, flash menus, messages, ATX, audio
- [x] ISH/ISD audio decode + encode (DSP ADPCM ↔ WAV) and THP video (THH + THD joined into a standard playable `.thp`, bit-identical both ways)
- [x] WBFS read — setup restores a `.wbfs` as a lazy block-mapped view, validated byte-for-byte on a real container (see the format table)
- [x] MSG (Colo/XD) parse + rebuild — byte-identical on all 2312 MSG entries of all six GameCube discs and on all 9 `common.rel`-embedded tables, through the binary and the JSON artifact alike, once an entry carries its rank in the string pool, is bounded by the next string, keeps its bytes where the codec can't reproduce them, and the table keeps its container's padding (see "Colosseum / XD messages")
- [x] FileFormat protocol + FileFormatRegistry — inject-at-use-site; builtins registers MSG, FNT, GTX, ATX, GSW; DOL/REL disassembly `.file` chunks route through it
- [x] DOL typed data reassembly — a `.struct` chunk is JSON (`StructData(definition:json:)`), a `.table` chunk is **CSV** (see "Struct tables as CSV"). Pointers resolve through `LabelTable`; edits land in the built DOL; the dumped artifact is the only source for typed chunks (no `.bin` sidecars, no legacy fallback). A chunk that can't round-trip demotes to a raw `.binary` chunk. `ProjectSetup` emits a disabled `dolAssembly` ahead of the disc build on both platforms, mirroring the dump's symbol and type maps, and pointing `outputSymbolMapPath` back at that symbol map so a rebuild that moves anything stays re-dumpable (see "A rebuilt DOL keeps its layout")
- [x] Colosseum script decompiler + compiler: full binary ↔ source-text round trip byte-exact on all 142 US scripts (four verified stages; `ColoScriptSourceEmitter`/`ColoScriptTextParser`/`ColoScriptCompiler`; `ColoScriptDecomp --roundtrip` + `ColoScriptRoundTripTests`). Dialect + GS code-gen conventions in `Documentation/File Formats/Shared/SCD - Script Bytecode.md`; engine-declared builtin signatures (246, int/float/bool/string only) generated into `defaultBuiltInFunctions` with reference doc `Documentation/File Formats/Colosseum/Script Builtin Functions.md`
- [x] REL disassembly + reassembly — a module dumps to a source tree the assembler reads back in full (see "REL source tree"): the `<name>.rel.json` manifest carries header, imports, per-section chunk lists with each file's path and mapped type, a symbol table and at-rest words, but **no bytes**; text is `textN.s` with symbolic relocations, data is per-chunk `.bin`/`.s`/`.csv`/embedded-file artifacts, and relocations are re-derived from the source. Edits to any chunk file land in the rebuilt `.rel`. `RelOperationsGate` is kept as the one place that turns the whole family off if a regression appears
- [x] Per-region type maps — the DOL and `common.rel` maps ship as `_us`/`_eu`/`_jp` variants for both XD and Colosseum, and `ProjectSetup` installs the disc's own region under a single fixed name, so operations stay region-blind. `GeniusSonorityEngine.Data.chunkTypeMapRoutes` adds any further typed file (`tableres2.rel`) as data rather than a new branch. PBR has no DOL type map on purpose: the same header scan over its US/PAL/JP `main.dol` (`scripts/analysis/scan_dol_textures.py`) finds no embedded textures — the Wii System Menu draws the health warning and the disc is readable from boot, so PBR loads everything from FSYS
- [x] Both games' DOL tables typed in every region — XD's 13 and Colosseum's 15 (Colosseum had none before, in any region) dump as CSV on all six GameCube discs, with the row counts the game's own count words declare (see "DOL data tables"). Colosseum gained `Structs/entries/DolStructs.swift` and its three DOL symbol maps; XD's `Abilities` count was corrected from 123 to 78
- [x] XD `common.rel` fully typed — the last four tables (`PokemonStats`, `Battles`, `Pokespots`, `Rooms`) have struct definitions taken from the game's own accessors (`pokemonDataBios*`, `fightEncountDataBios*`, `esaba*`, `floorDataBios*`; docs under `Documentation/Assembly Analysis/Data Structures/`), and the four Pokespot encounter lists are typed too. Two tables change stride between builds, so the region maps name distinct structs: PAL `Battles` → `BattleEU` (four extra per-language intro ids, 0x4C not 0x3C) and JP `Rooms` → `RoomJP` (one fsys id up front, 0x30 not 0x40). Verified on the real US/PAL/JP discs: all 31 declared tables dump as CSV with the row count the REL's own `NumberOf*` word declares (`CommonRelTableCSVCorpusTests`, skips without a dump; `GODDESS_COMMON_REL_CORPUS` points it at a project). The five legacy-derived definitions that used to demote — `Items`, `Moves`, `Natures`, `Types`, `TreasureBoxData` — were re-derived from the accessors: `Treasure` is 0x1C not 0x28, `Nature` 0x28 not 0x20, `Move` carries a `fightKoukaDataId` word and three effect-type bytes, `Item` has two flag bytes and a 32-bit parameter where padding was declared, and `Type`'s matchup array starts at +0x0C. The DOL's `ShinyPKXModel` is 12 bytes (two pad bytes after the species), which is why its CSV read `VENUSAUR` then nonsense
- [x] Colosseum `common.rel` fully typed — all 28 tables have struct definitions (`Colosseum/Structs/entries/CommonRelStructs.swift`; reference in `Documentation/File Formats/Colosseum/common.rel Tables.md`), derived from byte scans of all three discs against the legacy layouts, with the Colosseum disassembly used only where a routine's stride identified it (its function names are positional matches from XD's map). Colosseum keeps its trainers here rather than in deck files. PAL widens three records by per-language copies of one field, so its map names `RoomEU`, `BattleEU` and `BattleFieldEU`; `Trainers` and `Keyboard3Characters` declare explicit counts because the next symbol isn't their end. `CharacterModel` is 0x2C, not the 0xDC an earlier derivation claimed (150 × 0x2C is exactly the chunk). Verified on the real US/PAL/JP discs: 28/28 tables dump as CSV with the row counts the count words declare (`CommonRelTableCSVCorpusTests`, env `GODDESS_COLO_COMMON_REL_CORPUS`). Two findings worth knowing: the US disc stores species height and weight in feet/inches and tenths of a pound where PAL and JP are metric, and a room's shadow cutoff distance is not a table field — the room's floor kind selects one of three constants (0, 70, 80 units) and the shadow-map size at load. Both games' `Room` structs type that kind as the `RoomKind` enum (None, Field, Battle, MoveViewer, Scene, SystemMenu…, named from the rooms that carry each value); Colosseum keeps it in the top three bits of the record's first byte, and since the low five bits are zero on every room of every disc the whole byte is the enum with raw values kind × 32 — there is no sub-byte field support in `StructData`, and this case doesn't need it
- [x] PBR fonts — `.FNT` bitmap glyphs (byte-identical on all 21 shipped fonts / 20,898 glyphs) and the `.f3d` 3D font (contours are the only stored geometry; strips and bounding boxes are re-derived on write), plus atlas/SVG artifacts and `pbrFont{,s}{Dump,Build}` operations
- [x] PBR dump + build operations (`pbrDump` / `pbrBuild`)
- [x] PBR strings — `MESG` tables + the `common.fsys` string directory
      parse and rebuild (30 real entries / 156,100 strings byte-identical),
      dumped as one editable document by `pbrStringsDump` and written back
      by `pbrStringsBuild` (see "PBR strings")

### In Progress
- [ ] Validate GSW rebuild end-to-end on full ROM (unit tests pass; need project-level validation)
- [ ] Colosseum script pipeline follow-ups: `pushVar` semantics (73 corpus sites, rendered as `&x`), decompile the DOL-embedded common-script libraries (kinds 0–4), name the ~100 `<module>UnknownN` builtins via handler analysis, port the pipeline to XD scripts
- [ ] Wii disc decrypt/rebuild — round trip validated on synthetic discs (engine
      + operation level) and on the real PBR PAL disc (see "Wii ISO Encryption");
      remaining: boot a rebuilt ISO in an emulator, and note that Wii engine
      `Enums`/`Structs` are still empty shells with the five struct defs under
      `Wii/Structs/entries/` unreferenced (parsing is hand-rolled, so partition
      metadata isn't JSON-editable yet)
- [ ] PBR `common.fsys` data tables — `PBREngine` is a real `Engine` and
      `ProjectSetup` writes it for PBR discs. It declares the container
      format (`PBRCommonTableHeader` + string pool + name table + relocation
      table, geometry verified on all 33 PAL tables), the Pokémon model body
      map (`PBRPokemonModel` / `PBRModelBoneMap` / `PBRModelAnimationMap`,
      slot roles derived by resolving 321 model rows against the bone and
      action names in the `.sdr` each points at), and a typed entry struct
      for every one of the 33 tables. Table→file-index registry covers the
      US/PAL and JP orderings.

      **Three of the JP disc's 32 tables lay their records out differently,
      and one of them keeps the stride.** `Countries` and `ColosseumsUnknown`
      drop a per-language array and are simply shorter, so a stride check
      finds them. `PokemonStats` is 0x34 either way: the international record
      carries a second name id at +0x1A holding the *Japanese* species name
      (PAL id 21278 → table 2 index 8739 → フシギダネ, shipped in the USUK
      copy of that table as much as the others), the JP disc has no use for
      a second copy and drops it, so every field after +0x18 sits two bytes
      earlier and the record ends on two bytes of `0xD0` filler. It tiles the
      entry array perfectly while decoding every stat two bytes late, which
      is why the geometry checks passed and only the values said anything was
      wrong. A JP record is bound through `japaneseStructName` on the table
      descriptor, and the guard for this shape is the padding assertion run
      over the JP disc with JP records bound
      (`testDeclaredPaddingRunsAreFillerOnTheJapaneseDisc`).

      Layouts come from the game's own generated accessors: PBR reaches every
      table through a 33-slot pointer array at **0x8063CE34** (PAL), and each
      table has a row-getter whose stride is a compile-time constant plus a
      set of one-line field getters. Mining those and resolving their call
      sites back to a pointer-array slot resolved 26 of the 33 tables, every
      one with a stride matching its header word. Two rules fell out and are
      load-bearing: **intra-entry alignment gaps are filled with `0xD0`, not
      zero** (14 tables have such runs — this is what separates a live
      unknown field from a hole, and it corrected several fields the legacy
      tool had mislabelled), and inter-region padding is zero.

      **That filler has to be carried, because a CSV has no column for
      padding.** A row rebuilt from a CSV is zero across its gaps, so those
      14 tables were rebuilding with `0x00` where the disc has `0xD0` — and
      nothing said so, since a re-dump produced the identical CSV. The fill
      is *per run*, not per table (`PBRColosseum` has `0xD0` at +0x41 and
      zero at +0x44), so the dump measures each run across every row
      (`StructPaddingFill.measure`), the registry entry carries the runs it
      found, and `StructTableCSV.decode(paddingFills:)` writes them back.
      A run whose bytes differ between rows is not padding but an unnamed
      field, so the dump **refuses to type the table** and keeps the raw
      `.bin` rather than writing a CSV that drops data — the same
      verify-before-you-trust rule the DOL/REL exporters follow, and the
      dump now checks the whole table that way: decode its own CSV back,
      compare the entry bytes, demote on any mismatch. All 33 PAL tables and
      all 32 JP ones rebuild byte-for-byte from their CSVs
      (`PBRCommonTableDumpTests`, `testEveryTableRebuildsFromItsCSVOnTheJapaneseDisc`).

      The dump/build operations exist (`dumpCommonTables` under `pbrDump`,
      repacked by `pbrBuild`). `TypeMatchups` is typed column by column
      against the `PBRTypeEffectiveness` enum — the PAL chart is Gen 4's
      matchups exactly, which is what pins both the axis order and the
      enum's values, and the 14 rows past the 18 types are the battle code's
      override rows (neutral but for an ability's immunity: Ground for
      Levitate, Fire for Flash Fire). Remaining: the name-pool 16-bit hash is
      unidentified (see below); `PokemonModelEffects`, `FightAIBattlePass`
      and `FightAIPokemonPartData` have no field accessors so their interiors
      stay byte arrays, as does `FightAIExpectData`'s, whose one accessor
      (+0x2A) is the ability *slot* the AI assumes — 1 or 2 on every row,
      which is what rules out the ability id it is sometimes taken for. See
      `PBRCommonTableStructTests` and `PBRCommonTableRealCorpusTests` — the
      latter skips without a PBR dump (`GODDESS_PBR_COMMON` points it
      elsewhere) and includes a guard that fails if any run declared as
      padding carries live bytes on the disc.

#### PBR common.fsys name pools

7 of the 33 tables carry a string pool + name table + relocation table;
26 carry none. The pool holds `{u16 hash, NUL-terminated ASCII name}`
records; the name table maps each to an entry index and is sorted ascending
by that hash (binary search by name); the relocation table lists the words
holding file offsets that the loader converts to RAM pointers — one per name
record, since those are the only variable pointers in the file (the header's
own `entries_offset` is fixed and needs no entry).

Five tables name every row — `Abilities` (`TOKUSEI_000`…), `FightAIExpectData`
(species romaji), `FloorEvent` (`bf_00`…), `TrainerEvent` (trainer
archetypes), `ExperienceTables` — and those names are the natural key column
for a CSV dump. `Moves` and `FightAIMoveData` carry a single degenerate
record with an empty name. **The 16-bit hash is not reproducible yet**: no
standard hash matches, and a brute force over the whole CRC16 poly/init space
found nothing, so a dump has to carry the hash alongside the name. Editing
existing rows round-trips; inventing a new *named* row does not, until the
hash function is recovered.

### TODO

Carried over from three implementation plans deleted once their work landed
(`Completing-Half-Wired-Pipelines`, `CISO`, `GCI`). These are the only parts
that were still open.

- [ ] **`ish` and `thh` are registered as single-extension formats and can't
      be built that way.** `FileFormatRegistry+Builtins` registers them, but
      `ISFFile.init(binaries:)` and `THPFile.init(binaries:)` need both
      siblings (`.ish`+`.isd`, `.thh`+`.thd`), so the single-binary path
      always throws while `isRegistered("ish")` says yes — a generic caller
      is lured into a guaranteed failure. Either drop the registrations so
      the registry tells the truth, or give it a paired-format concept that
      gathers the sibling from the same folder.
- [ ] **`TypedDataImporter` and `LabelTable` look dead.** The second
      JSON→binary importer was meant to go when `StructData.populate` became
      canonical; `DataSectionImporter` and `DataSectionExporter` did. Confirm
      nothing reaches these two and delete them, so there is no second,
      incomplete implementation to drift.
- [ ] **A GCI dumps under two artifact layouts.** The `FileFormat`
      conformance writes `<name>.gci.json` + `<name>.gci.body.bin`; the
      operation writes `gci-manifest.json` + region bins. Two layouts for one
      format is a wart, though unifying them changes the golden fixture.
- [ ] **`.gcs` / `.sav` save intake.** Both wrap the same directory entry and
      body behind a larger header, and `.sav` byte-swaps eleven field pairs —
      cheap to add at the parse boundary, but no sample of either is on hand
      to test against.

### Planned (in order)
- [ ] XD script compiler — `XD/Script` has the parser and expression builder only; no source emitter, compiler or operation. The Colosseum pipeline (`ColoScriptSourceEmitter` / `ColoScriptTextParser` / `ColoScriptCompiler`) is the template
- [ ] Model file export (DAT/PKX)
- [ ] WAD and RARC containers. WBFS and U8 are done.
- [ ] WIA/RVZ restore — the header, partition and group tables and the
      RVZ packing codec parse, but the payload is zstd/bzip2/LZMA and the
      package has no decompressor for any of them. The plan
      (`Documentation/File Formats/Shared/RVZ - Implementation Plan.md`)
      vendors the C libraries through SwiftPM; that is a dependency
      decision, not plumbing. Setup names this in its error.
- [ ] Wii NKit restore — needs partition re-hashing and re-encryption on
      top of the GameCube decoder's junk regeneration (`WiiCrypto` now
      exists), and a Wii `.nkit.iso` sample to validate against. Setup
      names this in its error.

### Separate Tools (planned)
- Randomizer — wrapper around CLI
- Basic data browser/editor GUI — cross-platform (web or Java), invokes CLI with configs
- Advanced map/script editor — SwiftUI + Metal, interactive 3D map rendering with character models

## Game Support Priority

1. **Pokemon XD: Gale of Darkness** (primary)
2. **Pokemon Colosseum**
3. **Pokemon Battle Revolution** (Wii)
4. General GameCube/Wii titles

## Legacy Tool Reference

The original tool lives at `../GoD tool` (with space). Key features to eventually replicate or surpass:
- Pokemon/Move/Item/Type/Ability/Trainer editors
- Shadow Pokemon editor (XD & Colosseum), Pokespot editor (XD)
- Gift Pokemon, Treasure, Interaction editors
- Message/String table editor
- Script compiler (XD working, Colosseum incomplete)
- Randomizer
- ROM patcher with PowerPC ASM injection
- 3D collision viewer (Metal)
- ISO explorer, table editor
- Save file editor (GCI format)

Key reference paths in legacy tool:
- `Objects/data types/enumerable/` — all game data structure definitions
- `Objects/struct tables/` — 27 table definitions
- `Objects/file formats/` — FSYS, ISO, REL parsers
- `enums/` — 50+ game data enums
- `Objects/managers/XGPatcher.swift` — ROM patch implementations
