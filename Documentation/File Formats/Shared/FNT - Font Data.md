# FNT — Font Data

## Overview

FNT files contain bitmap font data for text rendering in Pokemon Colosseum and XD. Each file defines a set of character glyphs as 4-bit-per-pixel bitmaps (16 shades of intensity), indexed by Unicode code point. Font files range from minimal single-table files (336 bytes, ~40 characters) to comprehensive Japanese character sets (730 KB, ~2900 kanji).

**File type ID:** `0x0C`
**Extension:** `.fnt`
**Byte order:** Big-endian

## File Structure

```
┌──────────────────┐ 0x00
│  Header (16 B)   │
├──────────────────┤ 0x10
│  Character Table  │ entry_count × 8 bytes
│  (sorted by code) │
├──────────────────┤ bitmap_offset (= 0x10 + entry_count × 8)
│  Glyph Bitmaps   │ ~242 bytes per glyph
│                   │
└──────────────────┘
```

## Header (0x10 bytes)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | u16 | Reserved | Always `0x0000` |
| 0x02 | 1 | u8 | Glyph width | Max glyph width in pixels (typically 22) |
| 0x03 | 1 | u8 | Glyph height | Max glyph height in pixels (typically 22) |
| 0x04 | 2 | u16 | Reserved | Always `0x0000` |
| 0x06 | 2 | u16 | Data size | Size of glyph bitmap data section, or 0 for large files |
| 0x08 | 2 | u16 | Entry count | Number of entries in the character table (includes null entry 0) |
| 0x0A | 2 | u16 | Reserved | Always `0x0000` |
| 0x0C | 2 | u16 | Reserved | Always `0x0000` |
| 0x0E | 2 | u16 | Bitmap offset | Offset to glyph bitmap data = `0x10 + entry_count × 8` |

## Character Table

Immediately follows the header at offset 0x10. Each entry is **8 bytes**, sorted by character code for binary search lookup.

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | u16 | Character code | Unicode code point (0x0020 = space, 0x4E00+ = CJK, etc.) |
| 0x02 | 1 | u8 | Advance width | Horizontal advance in pixels (how far to move after this glyph) |
| 0x03 | 1 | u8 | Glyph height | Height of this specific glyph |
| 0x04 | 2 | u16 | Flags | Rendering flags (varies per character) |
| 0x06 | 2 | u16 | Bitmap offset | Offset within the bitmap data section to this glyph's pixels |

Entry 0 is always null (all zeros) — a sentinel for lookup failures.

### Character Code Encoding

The runtime supports multiple character encoding schemes via `GetFontCode`:

| Encoding | Range | Mapping |
|----------|-------|---------|
| ASCII | 0x0020–0x00FF | Direct Unicode code points |
| Zenkaku (full-width Japanese) | 0x8140–0x879E, 0x8840–0x9872 | Shift-JIS to Unicode via lookup table |
| Hankaku (half-width katakana) | 0x0020–0x00DF | Via `HankakuToCode` lookup table |

## Glyph Bitmap Data

Glyph bitmaps are stored as **4-bit-per-pixel intensity data** (16 shades from transparent to fully opaque). Each glyph for a 22×22 font uses **242 bytes** (22 × 22 / 2).

```
Bytes per glyph = ceil(glyph_width / 2) × glyph_height
```

For the standard 22×22 glyph: `11 × 22 = 242 bytes`

Each byte contains two horizontally adjacent pixels:
- **Upper nibble (bits 7-4):** Left pixel intensity (0x0 = transparent, 0xF = opaque)
- **Lower nibble (bits 3-0):** Right pixel intensity

The bitmap data section starts at the offset specified in the header (0x0E) and contains glyphs packed sequentially. Each character table entry's bitmap offset field points to the start of its glyph within this section.

## File Size Calculation

```
file_size = 0x10 + (entry_count × 8) + (num_glyphs × bytes_per_glyph)
```

### Observed File Sizes

| File | Entries | Glyphs | Size |
|------|---------|--------|------|
| Map room fonts (D1_*, M1_*, etc.) | 1 | ~40 chars | 336 B |
| system_tool.fnt | 2 | ~148 chars | 1,200 B |
| D2_rest_2.fnt | 3 | ~163 chars | 1,328 B |
| jis_1.fnt | 2,919 | ~2,918 kanji | 729,776 B |

## Runtime System

### Font Manager

The global font manager (at TOC offset `r13 - 0x7AD8`) maintains:

| Offset | Size | Field |
|--------|------|-------|
| 0x02 | 2 | Number of open fonts |
| 0x10 | 4 | Render texture pointer |
| 0x14 | 2 | Current render X position |
| 0x16 | 2 | Current render Y position |
| 0x18 | 1 | Current glyph height |
| 0x20 | 4 | Font entry array pointer |
| 0x24 | 4 | Character encode function pointer |

### API Functions

| Function | Module | Purpose |
|----------|--------|---------|
| `GSmsgFontOpen` | GSmsg | Load font into manager, register character table |
| `GSmsgFontClose` | GSmsg | Unload font, free slot |
| `_msgGetCodeInfo` | GSmsg | Look up character code → glyph info (binary search) |
| `_msgSetChar` | GSmsg | Set current glyph for rendering |
| `_msgMakeTexture` | GSmsg | Render glyph to runtime texture |
| `_msgGetSize` | GSmsg | Calculate rendered string size |
| `_msgGetLength` | GSmsg | Calculate string length in characters |
| `GetFontCode` | OSFont | Convert input encoding to Unicode |
| `ReadFont` | OSFont | Read font file from disc/card |
| `OSLoadFont` | OSFont | Load font into memory |
| `OSGetFontTexel` | OSFont | Read individual glyph pixel |

### Character Lookup Flow

1. `GetFontCode` converts input encoding (ASCII/Shift-JIS) to Unicode code point
2. `_msgGetCodeInfo` binary-searches the character table by code point
3. Returns glyph metrics (advance width, height) and bitmap offset
4. `_msgMakeTexture` copies the 4bpp glyph bitmap to the render texture

## Game-Specific Notes

- Both Colosseum and XD use the same FNT format
- Per-room FNT files contain only the characters needed for that room's text
- `jis_1.fnt` provides the comprehensive Japanese character set
- Font rendering supports control sequences for bold, superscript, and color changes (handled by the message system, not the font format)

## References

- **Disassembled code:** `text1/GSmsg/` (font open/close, text rendering), `text1/OSFont/` (font loading, encoding)
- **Old GoD tool:** `enums/XGFontColours.swift` (font color definitions)
