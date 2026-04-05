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

> TODO: Retroactively add credits for the PowerPC 750CL ISA implementation (disassembler, assembler, and instruction definitions).
