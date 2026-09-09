# REL - Relocatable Module

REL is the standard GameCube relocatable module format used in Pokemon Colosseum and Pokemon XD for dynamically loaded code and data. REL files contain PowerPC executable code and data that is linked at load time against the main DOL executable and other loaded REL modules. The game uses REL modules extensively for per-map code, game data tables (common.rel), and subsystem-specific functionality.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x1C` |
| Extension | `.rel` |
| Byte Order | Big-endian |
| Architecture | PowerPC 750CL (32-bit) |

## Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Module ID | Unique identifier for this module |
| 0x04 | 4 | UInt32 | Next link | Runtime linked list pointer (0 in file) |
| 0x08 | 4 | UInt32 | Prev link | Runtime linked list pointer (0 in file) |
| 0x0C | 4 | UInt32 | Section count | Number of sections in the section table |
| 0x10 | 4 | UInt32 | Section table offset | File offset of the section table |
| 0x14 | 4 | UInt32 | Name offset | File offset of the module name string (may be 0) |
| 0x18 | 4 | UInt32 | Name size | Length of the module name |
| 0x1C | 4 | UInt32 | Version | REL format version |
| 0x20 | 4 | UInt32 | BSS size | Size of the uninitialized data section |
| 0x24 | 4 | UInt32 | Relocation table offset | File offset of the relocation table |
| 0x28 | 4 | UInt32 | Import table offset | File offset of the import table |
| 0x2C | 4 | UInt32 | Import table size | Size of the import table in bytes |
| 0x30 | 1 | UInt8 | Prolog section | Section index containing the _prolog function |
| 0x31 | 1 | UInt8 | Epilog section | Section index containing the _epilog function |
| 0x32 | 1 | UInt8 | Unresolved section | Section index for _unresolved handler |
| 0x33 | 1 | UInt8 | Padding | |
| 0x34 | 4 | UInt32 | Prolog offset | Offset within prolog section to _prolog |
| 0x38 | 4 | UInt32 | Epilog offset | Offset within epilog section to _epilog |
| 0x3C | 4 | UInt32 | Unresolved offset | Offset within section to _unresolved |
| 0x40 | 4 | UInt32 | Align | Section alignment (version >= 2) |
| 0x44 | 4 | UInt32 | BSS align | BSS alignment (version >= 2) |
| 0x48 | 4 | UInt32 | Fix size | Offset after which relocations are not applied at link time (version >= 3) |

Header size varies by version: 0x40 (v1), 0x48 (v2), 0x4C (v3).

## Section Table

The section table contains `section_count` entries of 8 bytes each:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Offset / Exec | File offset to section data; bit 0 is the executable flag |
| 0x04 | 4 | UInt32 | Size | Size of the section in bytes |

The lowest bit of the offset field serves as the executable flag:
- Bit 0 = 1: section contains executable code
- The actual file offset is obtained by masking off bit 0: `offset & ~1`

A section with offset 0 and nonzero size is the BSS (uninitialized data) section, which has no file data but is allocated in memory at load time.

## Import Table

The import table lists all modules this REL depends on. Each entry is 8 bytes:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Module ID | ID of the module being imported (0 = main DOL) |
| 0x04 | 4 | UInt32 | Relocations offset | File offset to the relocation chain for this module |

Module ID 0 refers to the main DOL executable. The REL's own module ID in the import table contains self-referencing relocations used for internal fixups.

## Relocation Entries

Each relocation entry is 8 bytes:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | UInt16 | Seek offset | Byte offset to advance the write cursor |
| 0x02 | 1 | UInt8 | Command | Relocation type |
| 0x03 | 1 | UInt8 | Target section | Section index in the target module |
| 0x04 | 4 | UInt32 | Addend | Value to add (symbol offset within target section) |

Relocations are applied sequentially. The write cursor starts at the beginning of the current section and advances by `seek_offset` bytes before each relocation is applied.

### Relocation Commands

| Value | Name | Description |
|-------|------|-------------|
| 1 | R_PPC_ADDR32 | Write full 32-bit address |
| 4 | R_PPC_ADDR16_LO | Write low 16 bits of address |
| 6 | R_PPC_ADDR16_HA | Write high-adjusted 16 bits (high 16 + 1 if bit 15 of low is set) |
| 10 | R_PPC_REL24 | 24-bit relative branch offset (for `b`/`bl` instructions) |
| 201 | R_DOLPHIN_SECTION | Set the current write section (no relocation applied; addend is section index) |
| 202 | R_DOLPHIN_NOP | No operation (skip entry, used for padding/alignment) |
| 203 | R_DOLPHIN_END | End of relocation chain for this import |

## Symbol Recovery

REL files do not contain a symbol table. However, symbol information can be partially recovered from self-referencing relocations (import table entries where the module ID matches the REL's own ID). Each self-referencing relocation with `R_PPC_ADDR32` targeting a code section provides a function pointer, and deduplicating these gives a list of referenced symbols.

External symbol maps (from debugging builds or community reverse engineering) can be applied to provide human-readable function and data names.

## Special REL Files

### common.rel

The largest and most important REL module. Contains global game data tables shared across the entire game:

- Pokemon species data
- Move data
- Item data
- Type effectiveness tables
- Trainer data
- Global message string tables
- Interaction point tables
- And many more

Nearly all game data editing involves modifying tables within common.rel.

### Map RELs

Each game map has an associated REL containing:

- Character/NPC placement data
- Map entry point definitions
- Map-specific script function bindings
- Spawn point coordinates

### pocket_menu.rel

Contains shop inventory data and menu-related tables.

## Game-Specific Differences

- **Colosseum** and **XD** both use standard GameCube REL format with no structural differences
- The specific data tables within common.rel differ significantly between games (different struct layouts, different table sizes, different offsets)
- XD's common.rel is substantially larger than Colosseum's, reflecting XD's additional game systems (Shadow Pokemon purification, Pokespots, etc.)
- Module IDs are assigned differently between the two games

## Disassembly Layout

GoD-Tool dumps a REL to a source tree and rebuilds it from that tree; the
bytes of the module live only in the source files. The `<name>.rel.json`
manifest carries the header scalars, the import-table order, one chunk list
per data section (each chunk's file path relative to the module folder and
the type it was mapped to), a symbol table, and at-rest words.

| Path | Contents |
|------|----------|
| `<name>.rel.json` | Manifest (`RelManifest`). No bytes. |
| `sections.txt` | Human summary. |
| `textN.s` | One per text section. Relocated fields are written as `sym@ha`, `sym@h`, `sym@l`, `sym@l(rN)` or `.4byte sym`; a branch to a label in the same section is PC-relative and not relocated. |
| `dataN.s` | A data section nothing points into. |
| `dataN/` | A data section with self symbols: one file per chunk, cut at every symbol the module's relocations target — `<sym>.bin`, `<sym>.s` (`.4byte sym` at pointer slots), `<sym>.csv` (typed table), `<sym>/…` (typed file via the format registry), `<sym>_tail.bin`, `dataN_start.bin`. |

The assembler re-derives every relocation from the source. A symbol
resolves to a label defined in any section of the module first, then to the
manifest's `symbols` table (targets the source cannot define: the DOL,
other modules, this module's BSS). `restWords` records the at-rest word at a
relocation site when it is not the zero-field default — 87 ADDR32 slots in
Colosseum's `common.rel`, none elsewhere. An `lbl_XXXXXXXX` name that is not a
known symbol assembles as that literal word, which is how a typed exporter
spells an unrelocated, non-zero pointer slot.

Measured over both US discs: text relocations are exclusively ADDR16_HA/LO
pairs (10 077 each) with zero at-rest fields, and data relocations are
exclusively ADDR32 (3 339 sites). All 430 RELs rebuild byte-identically from
their source trees.

## References

- GameCube SDK REL documentation
- Dolphin emulator source: `Source/Core/Common/GekkoDisassembler.cpp` (for PowerPC disassembly of code sections)
- XD and Colosseum disassembly: OSLink module (REL loader)
