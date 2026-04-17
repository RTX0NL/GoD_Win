# GoD-Tool

## Overview

GoD-Tool is a CLI utility for unpacking, editing, and rebuilding GameCube and Wii ROM files. It replaces the [legacy GoD tool](https://github.com/PekanMmd/Pokemon-XD-Code.git) which was an AppKit GUI that edited ROMs directly via byte patching. The new tool instead exports ROMs into a structured, human-readable project filesystem and rebuilds from scratch.

**Primary targets:** Pokemon XD: Gale of Darkness, Pokemon Colosseum, Pokemon Battle Revolution — but the architecture is intentionally general for any GameCube/Wii title.

**Executable name:** `GODDESS`

## Philosophy

- **Export → Edit → Rebuild**, not direct ROM injection
- **Data-driven engines**: Game-specific knowledge lives in JSON definitions (structs, enums), not hardcoded Swift. New games should be addable without code changes.
- **Minimal assumptions**: Don't couple to specific game structures. The legacy tool broke when making complex modifications because it assumed too much about the data.
- **1:1 rebuild accuracy**: Each dump/rebuild stage must produce bit-identical output to the original input before implementing the next stage.
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

### Wii ISO Encryption Spec (for future implementation)

Wii discs use **AES-128-CBC** encryption. Structure:

1. **Disc header** (unencrypted): disc ID, partition table at 0x40000
2. **Each partition contains:**
   - **Ticket** (unencrypted): holds the title key (AES-encrypted with the Wii common key, IV = title ID)
   - **TMD** (unencrypted): content hashes
   - **H3 hash table** (unencrypted): 0x18000 bytes, top-level integrity hashes
   - **Partition data** (encrypted): game content in 0x8000-byte groups

3. **Data group structure** (each 0x8000 bytes):
   - 0x000-0x3FF: hash metadata (H0, H1, H2) — encrypted with title key, IV = all zeros
   - 0x400-0x7FFF: file data — encrypted with title key, IV = bytes 0x3D0-0x3DF of decrypted hash block

4. **Hash chain**: H0 (per-block SHA-1) -> H1 (per-subgroup) -> H2 (per-group) -> H3 (in H3 table)

**Decryption flow:**
1. Read encrypted title key from Ticket (offset 0x1BF)
2. Read title ID from Ticket (offset 0x1DC) — used as IV
3. Decrypt title key with AES-128-CBC using Wii common key + title ID IV
4. Decrypt each 0x8000-byte group using the title key

**Encryption (rebuild) additionally requires:** H0/H1/H2/H3 hash recalculation (SHA-1), re-encryption, ticket fakesigning.

**Implementation notes:**
- Pure Swift implementations of AES-128-CBC and SHA-1 (no CryptoKit/CommonCrypto — those are Apple-only, not cross-platform)
- Common key must NOT be in source code — load from user config file
- Reference: Dolphin `VolumeWii.cpp`, Wiimm's wit `lib-std.c`
- wit obfuscates the key via XOR masks + SHA-1 derivation at startup (effectively hardcoded but not as plaintext)
- Estimated ~800-1200 lines of Swift (excluding crypto primitives)

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
- Tests in `Tests/Shared Tests/Dependency Tests/`
- Target: as close to 100% coverage as possible
- Test targets: `GoDFoundationTests`, `GoDStructTests`

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

### In Progress
- [ ] ColoXD FSYS dump (organizing extracted files by type into asset folders)
- [ ] ColoXD FSYS rebuild (must achieve 1:1 match before proceeding)

### TODO
- [ ] ATX texture decoding and encoding
- [ ] GTX texture decoding and encoding
- [ ] GSW flash menu decoding and encoding
- [ ] MSG message file decoding and encoding
- [ ] REL disassembly and reassembly
- [ ] Validate font dump and repack (1:1 accuracy)

### Planned (in order)
- [ ] Game data table export (custom human-readable format for StructData)
- [ ] Image/texture export (GTX format)
- [ ] Model file export
- [ ] Script decompiler/compiler (XD format needs tweaks; Colosseum format not fully figured out)
- [ ] DOL disassembly (split into sections, PowerPC disassembly, symbol map support for XD, shiftable output)
- [ ] REL (relocatable module) handling
- [ ] Wii ISO decryption/encryption (AES-128-CBC, partition-based, ~800-1200 lines estimated)
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
