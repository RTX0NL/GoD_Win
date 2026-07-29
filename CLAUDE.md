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

### Nintendo Archive Formats (future support candidates)

**GameCube/Wii:**
| Format | Extension(s) | Description |
|--------|-------------|-------------|
| RARC | `.rarc`, `.arc`, `.szs` | JSystem resource archive (Mario Sunshine, Zelda Wind Waker). Often Yaz0-compressed. |
| U8 | `.arc`, `.szs`, `.app` | Primary Wii archive for non-JSystem games (NSMBW, MKWii). Magic: `U\xAA8-`. |
| WAD | `.wad` | Installable Wii channel/title container (ticket + TMD + content). |
| WBFS | `.wbfs` | Sparse Wii disc image storage format. |
| WIA/RVZ | `.wia`, `.rvz` | Compressed GC/Wii disc images. RVZ is the newer variant. |
| BRRES | `.brres` | NW4R resource container (models, textures, animations). |
| BRSAR | `.brsar` | NW4R sound archive. |

**DS/3DS:**
| Format | Extension(s) | Description |
|--------|-------------|-------------|
| NARC | `.narc` | Nitro ARChive. Primary DS archive with FNTB + FATB sections. |
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
| Yaz0 | GC, Wii, 3DS, Wii U, Switch | LZ77 variant, wraps archives as `.szs`. Nintendo's standard for 20+ years. |
| Yay0 | GC (early) | Predecessor to Yaz0. |
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
- [x] DOL typed data reassembly — struct/table chunk JSON decodes via `StructData(definition:json:)`, pointers resolve through `LabelTable`; JSON edits land in the built DOL; JSON is the only source for typed chunks (no `.bin` sidecars, no legacy fallback). If JSON encoding fails the dump demotes the chunk to a raw `.binary` chunk. Table dump JSON reuses StructData's encoder (arrays/sub-structs/enums/padding round-trip)
- [x] Colosseum script decompiler + compiler: full binary ↔ source-text round trip byte-exact on all 142 US scripts (four verified stages; `ColoScriptSourceEmitter`/`ColoScriptTextParser`/`ColoScriptCompiler`; `ColoScriptDecomp --roundtrip` + `ColoScriptRoundTripTests`). Dialect + GS code-gen conventions in `Documentation/File Formats/Shared/SCD - Script Bytecode.md`; engine-declared builtin signatures (246, int/float/bool/string only) generated into `defaultBuiltInFunctions` with reference doc `Documentation/File Formats/Colosseum/Script Builtin Functions.md`

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

### TODO
- [ ] REL disassembly and reassembly — **temporarily disabled** via `RelOperationsGate` (all REL ops throw on entry, incl. common.rel/map.rel wrappers) until migrated to the same typed-data import flow as DOL

### Planned (in order)
- [ ] Game data table export (custom human-readable format for StructData)
- [ ] Image/texture export (GTX format)
- [ ] Model file export
- [ ] Script decompiler/compiler (XD format needs tweaks; Colosseum format not fully figured out)
- [ ] DOL disassembly (split into sections, PowerPC disassembly, symbol map support for XD, shiftable output)
- [ ] REL (relocatable module) handling
- [ ] WBFS / WAD / U8 containers, and wiring up the existing RVZ/WIA parsers
      (ProjectSetup still throws for `.wiaOrRVZ` and `.nkitWii`)
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
