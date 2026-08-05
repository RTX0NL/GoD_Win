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
