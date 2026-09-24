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

Everything a `.gci` says about itself lives in the 0x40-byte directory
entry. That entry is **fully generic**: it describes the save's banner,
its animated icon and its two comment strings for every GameCube title,
with no per-game knowledge. The body past that metadata is the game's
own and is opaque without a game-specific parser.

## File header — 0x40 DEntry

The first `0x40` bytes are the on-card directory entry (`DEntry`) for
the file, copied verbatim out of the memory-card directory sector. The
layout matches Dolphin's `GCMemcardDirEntry` (see
[`Source/Core/Core/HW/GCMemcard/GCMemcard.h`](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/HW/GCMemcard/GCMemcard.h),
struct `DEntry`) and libogc's `card_direntry`.

| Offset | Size | Type | Field | Notes |
|-------:|-----:|------|-------|-------|
| `0x00` | 4 | char[4] | `gamecode` | e.g. `GXXE`, `GXXJ`, `GXXP`, `GC6E`, `GLME` |
| `0x04` | 2 | char[2] | `makercode` | publisher code (`01` = Nintendo) |
| `0x06` | 1 | u8 | `unused1` | always `0xFF` |
| `0x07` | 1 | u8 | `bannerAndIconFlags` | bits 0–1 = banner format, bit 2 = icon animation order |
| `0x08` | 32 | char[32] | `filename` | NUL-padded; XD writes `PokemonXD`, Colosseum `pokemon_colosseum` |
| `0x28` | 4 | u32 | `modtime` | seconds since `2000-01-01 00:00:00` |
| `0x2C` | 4 | u32 | `imageOffset` | byte offset of the image block inside the body; `0xFFFFFFFF` = none |
| `0x30` | 2 | u16 | `iconFormat` | 2 bits per icon frame, 8 frames max |
| `0x32` | 2 | u16 | `animationSpeed` | 2 bits per icon frame, 8 frames max |
| `0x34` | 1 | u8 | `permissions` | bit 2 public, bit 3 no-copy, bit 4 no-move |
| `0x35` | 1 | u8 | `copyCounter` | bumped each time the file is copied |
| `0x36` | 2 | u16 | `firstBlock` | first block on the card; not meaningful in `.gci` |
| `0x38` | 2 | u16 | `blockCount` | number of `0x2000`-byte blocks that follow |
| `0x3A` | 2 | u16 | `unused2` | always `0xFFFF` |
| `0x3C` | 4 | u32 | `commentsAddress` | byte offset of the two 32-byte comment strings inside the body |

`firstBlock` is preserved on dump but ignored on rebuild — the on-card
position is assigned by the card directory at copy time.

### Banner and icon flags (`0x07`)

| Bits | Meaning |
|---|---|
| 0–1 | `0` no banner, `1` CI8 (paletted), `2` RGB5A3 (direct), `3` no banner |
| 2 | icon animation order: `0` loop, `1` ping-pong |

### Icon format (`0x30`) — 2 bits per frame

| Value | Meaning |
|---|---|
| `0` | no icon in this slot |
| `1` | CI8, palette shared with the other CI8-shared frames |
| `2` | RGB5A3 |
| `3` | CI8, unique palette stored immediately after the frame |

### Animation speed (`0x32`) — 2 bits per frame

| Value | Meaning |
|---|---|
| `0` | no frame |
| `1` | frame lasts 4 video frames |
| `2` | 8 video frames |
| `3` | 12 video frames |

## The image block

`imageOffset` points at a run of banner and icon data whose length is
computable from the three format fields alone. Dimensions are fixed:
banner 96×32, icon 32×32, palette 256 entries of 2 bytes.

| Piece | Size |
|---|---|
| Banner, CI8 | `3072 + 512` = `0xE00` |
| Banner, RGB5A3 | `6144` = `0x1800` |
| Icon frame, CI8 shared palette | `1024` = `0x400` |
| Icon frame, RGB5A3 | `2048` = `0x800` |
| Icon frame, CI8 unique palette | `1024 + 512` = `0x600` |
| Shared palette, if any CI8-shared frame exists | `512` = `0x200` |

Layout order: the banner, then each icon frame in slot order, then the
single shared palette if at least one frame used format 1. A format-3
frame carries its own palette inline, directly after its pixels; it does
not contribute to the shared palette.

Pixel data is in the standard GX tiled order — 4×4 blocks for CI8, 4×4
for RGB5A3 — the same ordering `GXTexture` already decodes.

### Two divergences between references

**libogc's RGB5A3 icon stride is wrong.** `__card_updateiconoffsets` in
`libogc/card.c` advances by `3072` for a format-2 icon. The correct
value is `2048`: a 32×32 icon at 2 bytes per pixel. `3072` is the
banner's CI8 pixel count, evidently pasted from the branch above.
Dolphin and YAGCD both say `2048`. No save in the corpus uses format 2,
so the bug is unobservable there, but an implementation copying libogc
would mislay every later frame.

**Frame-list termination is ambiguous.** Dolphin stops at the first
frame whose *speed* is 0 and ignores everything after it. libogc instead
forces that frame's *format* to 0 and keeps walking all 8 slots. The two
agree whenever the speed field is a contiguous run, which is every save
in the corpus. They disagree only on a save with a zero speed followed
by a live frame, where libogc would find later frames Dolphin drops.
libogc mirrors the SDK the games were built against, so it is the safer
rule; a save that distinguishes them is malformed either way and is
worth a warning.

## Comments

`commentsAddress` points at two consecutive 32-byte NUL-padded strings:
a title and a subtitle, in that order. The pair is addressed
independently of the image block and need not sit next to it.

**Encoding depends on the card, and the card is not in the file.** The
memory card header carries an encoding word at `+0x24` (`0` = ANSI,
`1` = Shift-JIS), but a `.gci` has no card header, so a standalone file
has to infer it. The gamecode's region character is the available proxy:
`J` means Shift-JIS, anything else means CP1252. Corpus confirms both —
`POKéMON XD` on US and PAL saves, `ポケモンＸＤ` in Shift-JIS on JP.

## Where a game's own data begins

The metadata extent is the end of the image block or the end of the
comment pair, whichever is further. Nothing generic can be said about
what follows: it is the game's save data, and where it starts is a
per-game fact.

Two worked examples from the corpus show how far apart the conventions
are. Note that the comments come **first** in one and **last** in the
other.

| | Pokémon XD / Colosseum | Luigi's Mansion |
|---|---|---|
| `imageOffset` | `0x40` | `0x0` |
| `commentsAddress` | `0x0` | `0x1C00` |
| banner format | RGB5A3 | CI8 |
| icon frames | 8, all CI8-shared | 3, in slots 0, 3 and 7 |
| image block | `0x40`–`0x3A40` | `0x0`–`0x1C00` |
| comments | `0x0`–`0x40` | `0x1C00`–`0x1C40` |
| metadata ends | `0x3A40` | `0x1C40` |
| game data starts | `0x6000` | `0x2000` |

Luigi's Mansion is the useful counter-example for anything claiming to
be generic: its icon frames are sparse, occupying slots 0, 3 and 7 with
empty slots between, and its comments sit after its images rather than
before them.

## Genius Sonority conventions

Everything in this section is XD and Colosseum only.

**A `u32` checksum of the metadata region sits at `0x3A40`**, directly
after the image block. It is the sum of the preceding `0x3A40` bytes
read as big-endian `u32` words, truncated to 32 bits. XD verifies it in
[`_memcardJobMain__FUlUl`](../../../scripts/Disassembly-XD/text1/memcard/_memcardJobMain__FUlUl.s)
with a 233-iteration loop over 16 words each — `233 × 0x40 = 0x3A40` —
comparing against the word at `0x3A40` and raising a header-invalid flag
on mismatch. It holds on **72 of 72** real saves across both games and
all three regions. **Any edit to the banner, icons or comments of one of
these saves invalidates it and must recompute it.**

**`0x3A44` to the start of the slots is zero** on all 72. The claim in
earlier revisions of this document and in `Save System.md` that the body
holds "header sector #0 — 2 × 0x200 slot header records + flag/state
area" at `0x2000` and a "spare / GBA-exchange bookkeeping" sector at
`0x4000` is **not supported by the data**: `0x2000` and `0x4000` fall
inside the icon run, and everything after the checksum is zero. What the
disassembly actually establishes is that the game writes the first
`0x6000` (or `0x4000`) bytes as one unit, which is a write granularity,
not a record layout.

Slot geometry differs between the two games:

| | XD | Colosseum |
|---|---|---|
| body size | `0x56000` (43 blocks) | `0x60000` (48 blocks) |
| slots | 2 × `0x28000` at `0x6000`, `0x2E000` | 3 × `0x1E000` at `0x6000`, `0x24000`, `0x42000` |

Slot internals — encryption, sub-block TOC, per-block sizes — are in
[`Save System.md`](../../Assembly%20Analysis/Overview/Save%20System.md),
[`XD Save Encryption.md`](../XD/XD%20Save%20Encryption.md) and
[`Colosseum Save File.md`](../Colosseum/Colosseum%20Save%20File.md).

Both games also begin each slot with a small plaintext header, typed and
dumped as `slot-header.json`: XD's is 0xA8 (magic, save counter, cipher
key seed, checksum tags, and the sub-block size and offset tables),
Colosseum's is 8 bytes (magic, counter). Their magic differs in one
byte — `01 01 01` on XD, `01 01 00` on Colosseum — and is **not** the
gamecode.

## Adjacent container formats

Two other single-save containers wrap the same DEntry and body. Both are
straightforward to accept wherever `.gci` is accepted.

| Format | Total header | DEntry at | Notes |
|---|---|---|---|
| `.gci` | `0x40` | `0x00` | the DEntry *is* the header |
| `.gcs` (GameShark) | `0x150` | `0x110` | stored `blockCount` is unreliable; derive from file size |
| `.sav` (MaxDrive) | `0xC0` | `0x80` | magic `DATELGC_SAVE`; 11 field pairs are byte-swapped |

The `.sav` byte swap applies to the byte at each of `0x06`, `0x2C`,
`0x2E`, `0x30`, `0x32`, `0x34`, `0x36`, `0x38`, `0x3A`, `0x3C`, `0x3E`
and the one after it.

## Raw memory card images

A raw card (`.raw`, Dolphin's `MemoryCardA.*.raw`; also `.gcp`) is the
whole card. Extracting a `.gci` from one means walking its tables:

| Offset | Contents |
|---|---|
| `0x0000` | card header — serial, format time, encoding at `+0x24`, size at `+0x22`, update counter at `+0x1FA`, checksums at `+0x1FC` |
| `0x2000` | directory — 127 × `0x40` DEntry, update counter at `+0x1FFA`, checksums at `+0x1FFC` |
| `0x4000` | directory backup |
| `0x6000` | block allocation table — checksums at `+0x00`, update counter at `+0x04`, free blocks at `+0x06`, map from `+0x0A` |
| `0x8000` | BAT backup |
| `0xA000` | data area, block 5 onward |

Pick the live copy of each redundant pair by its update counter, with
`0xFFFF` meaning uninitialised. A file's blocks are a linked list: start
at the entry's `firstBlock` and follow `map[block - 5]` until `0xFFFF`.
A `.gci` is then the DEntry followed by those blocks in chain order.

Both the directory and the BAT carry a checksum pair — a plain 16-bit
word sum and the sum of each word XOR `0xFFFF`, with `0xFFFF` normalised
to `0`. Any write to a card has to fix both.

`scripts/save-audit/extract_gci.py` implements this read path.

## Round trip

GCI is a pure container: the header bytes and body bytes can both be
read and rewritten without loss, so parse → reserialize of any `.gci`
produces a byte-identical file.

Re-encoding the *contents* is a different question per piece:

- **RGB5A3 is exactly invertible.** Both branches of the format widen by
  a factor the encoder divides back out (`×8` and `÷8` for 5-bit
  channels, `×0x11` and `÷0x11` for 4-bit, `×0x20` and `÷0x20` for
  3-bit alpha), and the opaque branch is the only one that yields alpha
  255, so branch selection round-trips too.
- **CI8 is not, through an RGBA image.** Decoding to RGBA loses which
  index carried which color and collapses duplicate palette entries, so
  re-encoding rebuilds a different palette for identical pixels. Exact
  round-trip requires preserving indices and palette order — an indexed
  PNG does, an RGBA one does not.

  For a lone image that costs only byte-exactness, but format `1` frames
  **share one palette across the whole animation**, and there the loss is
  visible rather than cosmetic. Re-indexing each frame on its own gives
  as many palettes as there are frames, each in first-seen-color order,
  and no single one of them can be stored; pick the first frame's and
  every color the later frames have that it lacks resolves to index 0.
  A save with `iconFormat` `0x5555` — eight shared-palette frames, which
  is what XD writes — would come back with a mangled icon. Note this is
  *not* a checksum argument: the metadata checksum at `0x3A40` is
  recomputed on rebuild, so a changed image byte would carry a valid
  checksum regardless.
- **Encrypted slot payloads never round-trip** once re-encrypted, since
  the per-save key seed produces fresh ciphertext. The 1:1 invariant for
  those lives at the decrypted-slot level.

## Corpus

73 saves on the development machine, 61 distinct by content: 72 Genius
Sonority (50 XD, 22 Colosseum, all three regions each) and 1 Luigi's
Mansion, drawn from loose `.gci` files and from the directory and BAT of
the Dolphin raw card images. `scripts/analysis/scan_gci.py` reproduces
the inventory and the checksum check.

The save round-trip audit uses a narrower cut of the same material — 62
saves holding real game data, plus 13 blank never-saved cards — built by
`scripts/save-audit/build_corpus.py`. Five of those live only in
`~/Documents/Emulation/GC/Saves/GoD-Tool audit corpus/`, including the
one Colosseum PAL save on this machine with real game data; every local
PAL card is blank, so deleting that folder drops a whole game/region
pair from the audit.

A card image carries no magic, so anything ending `.raw` has to be
validated before its directory is walked — the local set includes a RAM
dump whose bytes at `0x2000` parse as plausible directory entries. The
directory's own checksum pair is the discriminator, which is what
Dolphin uses.

## References

- Dolphin `GCMemcard.h` / `GCMemcard.cpp` / `GCMemcardUtils.cpp` —
  DEntry layout, banner and icon decoding, checksums, GCS/SAV headers.
- libogc `card.h` / `card.c` — `__card_updateiconoffsets` image layout,
  `__card_checksum`, `CARD_*` constants.
- YAGCD §12 (Memory Card) — DEntry field table, banner and icon sizes.
- `Documentation/Assembly Analysis/Overview/Save System.md` — slot
  framing, encryption, sub-block TOC for Pokémon XD.
- Legacy GoD tool `XGSaveManager.swift` — first-pass `.gci` consumer
  (delegates decryption to `gcitool`).
