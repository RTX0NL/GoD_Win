# GCI — GameCube Memory Card Save Export

## Overview

`.gci` is the on-disk export format used by Dolphin and most third-party
memory-card managers (`gcitool`, `GCMM`, `gctool`) for a single save file
extracted from a GameCube memory card. It is **not** an on-card format —
the card itself stores files in fixed-size blocks indexed by a directory
table. A `.gci` is the directory entry concatenated with that file's
block contents.

**Byte order:** big-endian
**Block size:** `0x2000` (8192) bytes
**Total size:** `0x40 + blockCount * 0x2000`

For Pokémon Colosseum and Pokémon XD: Gale of Darkness the body is
exactly `0x56000` bytes, so a complete `.gci` is `0x56040` bytes.

## File header — 0x40 DEntry

The first `0x40` bytes are the on-card directory entry (`DEntry`) for
the file, copied verbatim out of the memory-card directory sector. The
layout matches Dolphin's `GCMemcardDirEntry` (see
[`Source/Core/Core/HW/GCMemcard/GCMemcard.h`](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/HW/GCMemcard/GCMemcard.h),
struct `DEntry`).

| Offset | Size | Type | Field | Notes |
|-------:|-----:|------|-------|-------|
| `0x00` | 4 | char[4] | `gamecode` | e.g. `GXXE`, `GXXJ`, `GXXP`, `GC6E` |
| `0x04` | 2 | char[2] | `makercode` | publisher code (e.g. `01` for Nintendo) |
| `0x06` | 1 | u8 | `unused1` | always `0xFF` |
| `0x07` | 1 | u8 | `bannerAndIconFlags` | bit0..1 = banner format, bit2 = icon animation |
| `0x08` | 32 | char[32] | `filename` | NUL-padded ASCII; Pokémon XD writes `pokemon_storys` |
| `0x28` | 4 | u32 | `modtime` | seconds since `2000-01-01 00:00:00` |
| `0x2C` | 4 | u32 | `imageOffset` | byte offset of banner image inside the file body |
| `0x30` | 2 | u16 | `iconFmt` | 2-bit-per-icon format flags (8 icons max) |
| `0x32` | 2 | u16 | `animSpeed` | 2-bit-per-icon animation speed |
| `0x34` | 1 | u8 | `permissions` | `PERM_PUBLIC` (`0x04`) etc. |
| `0x35` | 1 | u8 | `copyCounter` | bumped each time the file is copied |
| `0x36` | 2 | u16 | `firstBlock` | first block on the card; not meaningful in `.gci` |
| `0x38` | 2 | u16 | `blockCount` | number of `0x2000`-byte blocks that follow |
| `0x3A` | 2 | u16 | `unused2` | always `0xFFFF` |
| `0x3C` | 4 | u32 | `commentsAddr` | byte offset of the two 32-byte comment strings inside the file body |

`firstBlock` is preserved on dump but ignored on rebuild — the on-card
position is assigned by the card directory at copy time.

## File body — CARD-file payload

The `blockCount * 0x2000` bytes after the header are exactly the bytes
that lived in the file's blocks on the card. For Pokémon XD the body is
`0x56000` bytes laid out as:

| Offset (in body) | Size | Contents |
|-----------------:|-----:|----------|
| `0x00000` | `0x2000` | CARD banner / icon images + comments |
| `0x02000` | `0x2000` | Header sector #0 — slot-header records + flag/state area |
| `0x04000` | `0x2000` | Header sector #1 — spare / GBA-exchange bookkeeping |
| `0x06000` | `0x28000` | **Slot A** — encrypted serialised `SystemSaveData` |
| `0x2E000` | `0x28000` | **Slot B** — encrypted serialised `SystemSaveData` |

The two slots are independent ping-ponged copies; the game writes
whichever has the lower counter and reads whichever has the higher
counter. Slot internals (encryption, sub-block TOC, per-block sizes) are
documented in
[`Documentation/Assembly Analysis/Overview/Save System.md`](../../Assembly%20Analysis/Overview/Save%20System.md).

Pokémon Colosseum uses the same `0x56000` body shape but its slot
encryption has not yet been reverse-engineered — see the open work item
in `Save System.md` §11 and the GoD-Tool roadmap.

## Roundtrip

GCI is a pure container: the header bytes and body bytes can both be
read and rewritten without loss, so a parse → reserialise of any `.gci`
produces a byte-identical file. Once we re-encrypt the slot payload
inside the body, the `.gci` itself will *not* round-trip (the per-save
random key seed produces fresh ciphertext) — the 1:1 invariant only
holds at the *decrypted slot* level.

## References

- Dolphin `GCMemcard.h` — DEntry layout, permission/banner/icon flags.
- YAGCD §10 (Memory Card) — block size, directory format, BAT.
- `Documentation/Assembly Analysis/Overview/Save System.md` — slot
  framing, encryption, sub-block TOC for Pokémon XD.
- Legacy GoD tool `XGSaveManager.swift` — first-pass `.gci` consumer
  (delegates decryption to `gcitool`).
