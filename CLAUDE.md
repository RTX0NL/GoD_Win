# GoD-Tool

## Overview

GoD-Tool is a CLI utility for unpacking, editing, and rebuilding GameCube and Wii ROM files. It replaces the [legacy GoD tool](https://github.com/PekanMmd/Pokemon-XD-Code.git) which was an AppKit GUI that edited ROMs directly via byte patching. The new tool instead exports ROMs into a structured, human-readable project filesystem and rebuilds from scratch.

**Primary targets:** Pokemon XD: Gale of Darkness, Pokemon Colosseum, Pokemon Battle Revolution — but the architecture is intentionally general for any GameCube/Wii title.

**Executable name:** `GODDESS`

## Philosophy

- **Export → Edit → Rebuild**, not direct ROM injection
- **Data-driven engines**: Game-specific knowledge lives in JSON definitions (structs, enums), not hardcoded Swift. New games should be addable without code changes.
- **Minimal assumptions**: Don't couple to specific game structures. The legacy tool broke when making complex modifications because it assumed too much about the data.
- **Correctness, not byte-identical round-trip** (default): Rebuild recomputes/rederives everything from scratch. The goal is a *correct* rebuild, not one whose bytes match the original. Where practical, rederive native conventions (padding, alignment, ordering) so output looks native — but that is a nice-to-have, never the objective. A from-scratch rebuild that differs byte-for-byte but is functionally correct is a success. Do not add "replay original bytes for round-trip fidelity" logic; do fix genuine correctness bugs in writers (wrong values, dropped data, crashes).
- **Byte-identical formats are the exception, declared per format.** A format is promoted to a 1:1 target only once measurement shows the gap is a small number of *nameable* divergences rather than an unmatchable re-derivation (e.g. a compressor whose output can't be reproduced). Promoted formats get a named exception here and a real-corpus fidelity test. Current 1:1 targets:
  - **FSYS** — see "FSYS byte-identical rebuild" below.
  - **U8 / NARC** — see "Nintendo archives" below. Both formats' geometry is
    fully derivable from the entry list plus one alignment constant, so a
    repack that differs is a bug rather than an accepted re-derivation.
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
│   │       └── Third Party/xxHash/  # Hashing
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

Each operation has its own `Config` type and is enabled/disabled via the `OperationConfig<T>` wrapper with a `Toggle`.

### File Formats

| Format | Engine | Description |
|--------|--------|-------------|
| GameCube ISO | GameCube/Dolphin | Disc image with boot sector, FST, DOL, apploader |
| FSYS Archive | GeniusSonority (currently) | Proprietary archive with LZSS compression. Confirmed to be Genius Sonority-specific (not a Nintendo or middleware format). Used in Colosseum, XD, and PBR. May need its own engine or a more general home if non-GS games are found to use it. |
| FSYS TOC | GeniusSonority (currently) | Table of contents mapping group IDs to files |
| DOL | Dolphin | GameCube executable (text + data sections) |
| Yaz0 / Yay0 | none — `GoDFoundation/Data/Compression` | Nintendo's own LZ77 codec, GameCube through Switch. Not used by Colo/XD/PBR; present for general titles and as a prerequisite for RARC/U8. See "Nintendo LZ77 compression" below. |
| U8 (`.arc`) / NARC (`.narc`) | Nintendo | Nintendo's own containers, big **and** little endian. PBR ships both. Declared 1:1 targets — see "Nintendo archives" below. |

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
untyped, and on typed `common.rel` dumps across XD US/PAL/JP — exact on JP;
US and PAL come out 10 and 8 bytes short only where the MSG writer
re-encodes the five embedded string tables, which is the MSG codec's known
re-derivation, not the REL layout.

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
Only self-describing formats belong in it; FSYS's LZSS does not qualify,
because its magic lives in the archive's entry header rather than in the
stream the codec is handed.

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

### ISH/ISD Audio Format Spec (for future implementation)

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

**Current conversion workflow** (what we want to replace): extract from FSYS -> use vgmstream CLI or Audacity with vgmstream plugin -> WAV. The "Audacity fork with Nintendo support" is actually standard Audacity + the vgmstream input plugin.

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
- **Operation tests** (`GODOpsTests`): two layers, both required when adding an operation.
  1. *Routing*: `DispatchRoutingTests` feeds a JSON config through `GODOps.runConfig` with a `SpyOperationHandler` (the `OperationHandler` seam in `Dispatch.swift`) and asserts the case + decoded parameters. Adding a `GoddessConfig.Operations` case means extending the handler protocol, `EngineOperationHandler`, the spy, and adding a routing test.
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
- [x] Nintendo engine: U8 (`.arc`) + NARC (`.narc`) parse/rebuild, big and
      little endian, byte-identical on all 30 real PBR archives; manifest +
      FST `nintendoArchive` entry type + single/bulk dump & repack ops
      (see "Nintendo archives")
- [x] Project setup from ISO (auto-detect game, create folder structure, generate configs)
- [x] Configuration system (JSON configs, operation chains, toggle enable/disable)
- [x] Logging framework
- [x] GTX texture decode + encode (all pixel formats, palette rebuild)
- [x] ATX wrapper decode + encode (1:1 roundtrip on wrapper; texture body reuses GTX)
- [x] GSFont parse + rebuild (byte-identical) and atlas export/import
- [x] GSW flash menu parse + serialize (byte-identical non-texture bytes)
- [x] ColoXD build ops: font, flash menu, FST, GSfsys TOC, message
- [x] ColoXD dump ops: flash menu (GSW → PNG + metadata), message (MSG → JSON)
- [x] MSG (Colo/XD) parse + rebuild (byte-identical on FSYS-hosted MSGs; the three DOL-embedded XD MSGs re-encode +546 bytes total — writer re-derives string layout; self-consistent, and DOL shiftability tracks the growth) and JSON roundtrip via GSString pretty tokens
- [x] FileFormat protocol + FileFormatRegistry — inject-at-use-site; builtins registers MSG, FNT, GTX, ATX, GSW; DOL/REL disassembly `.file` chunks route through it
- [x] DOL typed data reassembly — a `.struct` chunk is JSON (`StructData(definition:json:)`), a `.table` chunk is **CSV** (see "Struct tables as CSV"). Pointers resolve through `LabelTable`; edits land in the built DOL; the dumped artifact is the only source for typed chunks (no `.bin` sidecars, no legacy fallback). A chunk that can't round-trip demotes to a raw `.binary` chunk. `ProjectSetup` emits a disabled `dolAssembly` ahead of the disc build on both platforms, mirroring the dump's symbol and type maps
- [x] Colosseum script decompiler + compiler: full binary ↔ source-text round trip byte-exact on all 142 US scripts (four verified stages; `ColoScriptSourceEmitter`/`ColoScriptTextParser`/`ColoScriptCompiler`; `ColoScriptDecomp --roundtrip` + `ColoScriptRoundTripTests`). Dialect + GS code-gen conventions in `Documentation/File Formats/Shared/SCD - Script Bytecode.md`; engine-declared builtin signatures (246, int/float/bool/string only) generated into `defaultBuiltInFunctions` with reference doc `Documentation/File Formats/Colosseum/Script Builtin Functions.md`
- [x] REL disassembly + reassembly — a module dumps to a source tree the assembler reads back in full (see "REL source tree"): the `<name>.rel.json` manifest carries header, imports, per-section chunk lists with each file's path and mapped type, a symbol table and at-rest words, but **no bytes**; text is `textN.s` with symbolic relocations, data is per-chunk `.bin`/`.s`/`.csv`/embedded-file artifacts, and relocations are re-derived from the source. Edits to any chunk file land in the rebuilt `.rel`. `RelOperationsGate` is kept as the one place that turns the whole family off if a regression appears
- [x] Per-region type maps — the DOL and `common.rel` maps ship as `_us`/`_eu`/`_jp` variants for both XD and Colosseum, and `ProjectSetup` installs the disc's own region under a single fixed name, so operations stay region-blind. `GeniusSonorityEngine.Data.chunkTypeMapRoutes` adds any further typed file (`tableres2.rel`) as data rather than a new branch. PBR has no DOL type map on purpose: the same header scan over its US/PAL/JP `main.dol` (`scripts/analysis/scan_dol_textures.py`) finds no embedded textures — the Wii System Menu draws the health warning and the disc is readable from boot, so PBR loads everything from FSYS
- [x] XD `common.rel` fully typed — the last four tables (`PokemonStats`, `Battles`, `Pokespots`, `Rooms`) have struct definitions taken from the game's own accessors (`pokemonDataBios*`, `fightEncountDataBios*`, `esaba*`, `floorDataBios*`; docs under `Documentation/Assembly Analysis/Data Structures/`), and the four Pokespot encounter lists are typed too. Two tables change stride between builds, so the region maps name distinct structs: PAL `Battles` → `BattleEU` (four extra per-language intro ids, 0x4C not 0x3C) and JP `Rooms` → `RoomJP` (one fsys id up front, 0x30 not 0x40). Verified on the real US/PAL/JP discs: all 31 declared tables dump as CSV with the row count the REL's own `NumberOf*` word declares (`CommonRelTableCSVCorpusTests`, skips without a dump; `GODDESS_COMMON_REL_CORPUS` points it at a project). The five legacy-derived definitions that used to demote — `Items`, `Moves`, `Natures`, `Types`, `TreasureBoxData` — were re-derived from the accessors: `Treasure` is 0x1C not 0x28, `Nature` 0x28 not 0x20, `Move` carries a `fightKoukaDataId` word and three effect-type bytes, `Item` has two flag bytes and a 32-bit parameter where padding was declared, and `Type`'s matchup array starts at +0x0C. The DOL's `ShinyPKXModel` is 12 bytes (two pad bytes after the species), which is why its CSV read `VENUSAUR` then nonsense
- [x] Colosseum `common.rel` fully typed — all 28 tables have struct definitions (`Colosseum/Structs/entries/CommonRelStructs.swift`; reference in `Documentation/File Formats/Colosseum/common.rel Tables.md`), derived from byte scans of all three discs against the legacy layouts, with the Colosseum disassembly used only where a routine's stride identified it (its function names are positional matches from XD's map). Colosseum keeps its trainers here rather than in deck files. PAL widens three records by per-language copies of one field, so its map names `RoomEU`, `BattleEU` and `BattleFieldEU`; `Trainers` and `Keyboard3Characters` declare explicit counts because the next symbol isn't their end. `CharacterModel` is 0x2C, not the 0xDC an earlier derivation claimed (150 × 0x2C is exactly the chunk). Verified on the real US/PAL/JP discs: 28/28 tables dump as CSV with the row counts the count words declare (`CommonRelTableCSVCorpusTests`, env `GODDESS_COLO_COMMON_REL_CORPUS`). Two findings worth knowing: the US disc stores species height and weight in feet/inches and tenths of a pound where PAL and JP are metric, and a room's shadow cutoff distance is not a table field — the room's floor kind selects one of three constants (0, 70, 80 units) and the shadow-map size at load. Both games' `Room` structs type that kind as the `RoomKind` enum (None, Field, Battle, MoveViewer, Scene, SystemMenu…, named from the rooms that carry each value); Colosseum keeps it in the top three bits of the record's first byte, and since the low five bits are zero on every room of every disc the whole byte is the enum with raw values kind × 32 — there is no sub-byte field support in `StructData`, and this case doesn't need it
- [x] PBR fonts — `.FNT` bitmap glyphs (byte-identical on all 21 shipped fonts / 20,898 glyphs) and the `.f3d` 3D font (contours are the only stored geometry; strips and bounding boxes are re-derived on write), plus atlas/SVG artifacts and `pbrFont{,s}{Dump,Build}` operations
- [x] PBR dump + build operations (`pbrDump` / `pbrBuild`)

### In Progress
- [ ] ColoXD FSYS dump (organizing extracted files by type into asset folders)
- [ ] ColoXD FSYS rebuild — 1:1 achieved on 500 real archives across both games (see "FSYS byte-identical rebuild"); remaining work is the dump/pack *operation* layer, not the format
- [ ] Validate font dump + rebuild end-to-end on full ROM (unit tests pass; need project-level validation)
- [ ] Validate GSW rebuild end-to-end on full ROM (unit tests pass; need project-level validation)
- [ ] MSG — PBR variant (Colo/XD done)
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

      Remaining: a dump/build *operation*; the name-pool 16-bit hash is
      unidentified (see below); `PokemonModelEffects`, `FightAIBattlePass`,
      `FightAIPokemonPartData` and `FightAIExpectData` have no field
      accessors so their interiors stay byte arrays. See
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

### Planned (in order)
- [ ] Game data table export (custom human-readable format for StructData)
- [ ] Image/texture export (GTX format)
- [ ] Model file export
- [ ] Script decompiler/compiler (XD format needs tweaks; Colosseum format not fully figured out)
- [ ] DOL disassembly (split into sections, PowerPC disassembly, symbol map support for XD, shiftable output)
- [ ] REL (relocatable module) handling
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
- [ ] ISH/ISD audio decode/encode (DSP ADPCM ↔ WAV, replaces vgmstream/Audacity workflow)

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
