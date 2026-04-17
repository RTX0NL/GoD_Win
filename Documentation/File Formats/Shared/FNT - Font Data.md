# FNT — Font Data

## Overview

Genius Sonority bitmap font format used in Pokemon Colosseum and XD. Each `.fnt` file contains a **linked list of font blocks** (typically a 22×22 primary, an 18×18 secondary, and sometimes 13×13 or further-nested variants). Glyphs are stored as 4-bit-per-pixel intensity bitmaps and indexed by character code for binary-search lookup at runtime.

**File type ID:** `0x0C`
**Extension:** `.fnt`
**Byte order:** Big-endian
**Runtime entry point:** `GSmsgFontOpen` (at `text1/GSmsg/`) walks the linked list; `_msgGetCodeInfo` binary-searches each block's char table.

## Block layout

Every block in the chain has the same structure:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | u16 | `fontId` | Sequential ID (0, 1, 2…). `0xFFFF` terminates the list; checked at the top of `GSmsgFontOpen`'s loop. |
| 0x02 | 1 | u8 | `glyphWidth` | Font-wide max glyph width (22, 18, or 13 observed). |
| 0x03 | 1 | u8 | `glyphHeight` | Font-wide max glyph height. |
| 0x04 | 4 | u32 | `nextBlockOffset` | **Relative** to this block's start (matches the asm `r31 += r0`). `0` = last block in the file. |
| 0x08 | 2 | u16 | `count` | Number of searchable char-table entries. |
| 0x0A | 2 | u16 | reserved | Always 0. |
| 0x0C | 2 | u16 | reserved | Always 0. |
| 0x0E | 2 | u16 | `lastEntryOffset` | Offset (from block start) of the final char-table entry. Equals `0x18 + (count - 1) × 8`. |
| 0x10 | 8 | — | chain-ptr slot | Reserved for runtime next/prev linked-list pointers. `GSmsgFontOpen` writes to offsets 0x18 and 0x1C of this region at load time. Always zero on disk. |
| 0x18 | `count × 8` | — | char table | Sorted-by-code entries, binary-searched by `_msgGetCodeInfo`. |
| `lastEntryOffset + 8` | — | — | bitmap data | 4bpp scanline data; each glyph's `bmpOff` is relative to this base. |

### Char-table entry (8 bytes)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | u16 | `code` | Character code (ASCII / Shift-JIS mapped to Unicode). Table is sorted by this. |
| 0x02 | 1 | u8 | `advance` | Horizontal advance (cursor step after drawing). |
| 0x03 | 1 | u8 | `height` | Per-glyph height. |
| 0x04 | 2 | u16 | `flags` | High byte varies per glyph; runtime usage not yet identified (not a row-rotation despite earlier guesses). |
| 0x06 | 2 | u16 | `bmpOff` | Offset into the bitmap region. For fonts with > 64 KB of glyph data, this UInt16 wraps every `0x10000` bytes — iterate entries in order and track a bank counter. |

### Glyph bitmap

```
bytes_per_glyph = ⌈advance / 2⌉ × height
```

4bpp scanline layout, **upper nibble = left pixel**, lower nibble = right pixel. `_msgMakeTexture` (`text1/GSmsg/_msgMakeTexture__FP13MSG_TASK_WORKPUcsss.s`) writes bytes to the render texture in natural order — no rotation, mirror, or row transform.

## Example: Font_Data_14

```
0x0000  primary block (fontId=0, 22×22, 6 entries)
0x0600  secondary block (fontId=1, 18×18, 6 entries; nextOffset=0 = end)
```

Same character codes appear in both blocks, with smaller glyph bitmaps in the 18×18 variant.

## Observed block topologies across the 26 XD fonts

- **1 block** — Font_Data_24 (jis_1, comprehensive 2919-glyph CJK set).
- **2 blocks** (22×22 + 18×18) — most fonts (19 of 26).
- **3 blocks** — Font_Data_1, 5, 13, 21 (add a second 18×18).
- **5 blocks** — Font_Data_8 (22×22 + 18×18 + 18×18 + 13×13 + 13×13).

The 13×13 variant exists but is rare. Callers select which block to render from via the font ID; the selection logic lives outside the format itself.

## Runtime data flow

1. **Load** — `floorReadFontPostFunc` (`text1/floorRead/`) pulls a `.fnt` buffer from FSYS and calls `GSmsgFontOpen(bufferPtr)`.
2. **Register** — `GSmsgFontOpen` walks the block list, registering each in the font manager at `*(-0x7ad8(r13)) + 0x20` and writing next/prev chain pointers into the 8-byte reserved slot at block+0x10.
3. **Lookup** — `_msgGetCodeInfo(task, charCode, out)`:
   - `r6 = fontInfo.charTablePtr` (= block start + 0x08)
   - `r9 = *(u16 at r6+0)` = `count`
   - `r7 = r6 + 0x10` = char-table base (which is block+0x18, past the chain-ptr slot)
   - Binary-search `count` entries at `r7`, comparing `u16 code`.
4. **Render** — `_msgSetChar` feeds the found entry's `bmpOff`-derived bitmap pointer into `_msgMakeTexture`, which stbx-copies bytes into the render texture.

## References

- Disassembly: `scripts/Disassembly-XD/text1/GSmsg/GSmsgFontOpen.s`, `_msgGetCodeInfo__*.s`, `_msgMakeTexture__*.s`, `_msgSetChar__*.s`, `floorRead/floorReadFontPostFunc.s`.
- In-memory `tagFONT_INFO` layout: inferred from `GSmsgFontOpen` writes — `{ u16 code, u8 adv, u8 h, u32 charTablePtr, u32 next, u32 prev }`.
