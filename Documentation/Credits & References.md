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
