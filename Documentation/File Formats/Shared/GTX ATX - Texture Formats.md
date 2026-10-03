# GTX / ATX — Texture Formats

## Overview

GTX and ATX are the texture formats used in Pokemon Colosseum and XD. GTX files contain a single static texture; ATX files contain multiple frames played in sequence (animated textures, like GIF). Both use the same header structure and underlying GameCube GX pixel encoding.

Textures are also embedded within other formats: DAT/RDAT models, PKX battle models, and GSW flash animations all contain inline texture data using the same encoding.

## Identification

| Format | Type ID | Extension | Description |
|--------|---------|-----------|-------------|
| GTX | `0x12` | `.gtx` | Single static texture |
| ATX | `0x32` | `.atx` | Animated texture (multiple sequential frames) |

**Byte order:** Big-endian

## Header Structure

Each texture (or each frame in an ATX) has a header of approximately 0x80 bytes. The texture data pointer field determines where pixel data actually begins.

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | u16 | Width | Texture width in pixels |
| 0x02 | 2 | u16 | Height | Texture height in pixels |
| 0x04 | 1 | u8 | Bits per pixel | See BPP column in format table |
| 0x05 | 1 | u8 | Unknown, always 1 | Previously documented as an indexed flag, but it is 1 on every retail texture measured — all 22 embedded in the six Colo/XD DOLs, and all 4314 standalone `.gtx` files across the Colosseum, XD and PBR dumps, indexed or not. Likely an image or mip count. The encoder writes the constant; deriving it from the format was the one byte between a non-indexed texture and a byte-identical rebuild. (The only zeros anywhere are in headers the *legacy* tool synthesized around textures it pulled out of DAT/PKX/WZX models — 582 of them — which are not retail bytes.) |
| 0x06 | 5 | — | Reserved | |
| 0x0B | 1 | u8 | Texture format | GS texture format ID (see table below) |
| 0x0C | 3 | — | Reserved | |
| 0x0F | 1 | u8 | Palette format | GS palette format ID (see palette section) |
| 0x10 | 24 | — | Reserved | |
| 0x28 | 4 | u32 | Texture data offset | Relative offset from header start to pixel data |
| 0x2C | 28 | — | Reserved | |
| 0x48 | 4 | u32 | Palette data offset | Relative offset to palette (0 if non-indexed) |
| 0x4C | 4 | u32 | Texture data length | Zero in every standalone GTX measured, including all 2480 in PBR's US archives; do not rely on it (the length is derived from dimensions and format) |

Texture data typically starts at offset **0x80** from the header start, but always use the pointer at 0x28 for the actual offset.

### File extent

A texture's total length is derivable from its own header, which matters
wherever one is embedded in a larger buffer: an indexed texture ends at
`palette offset + entry count x 2`, a non-indexed one at
`texture offset + padded width x padded height x bpp / 8`. Do not infer it
from the surrounding container. XD's health-warning texture is the case that
proves it: its 16-entry palette carries its own symbol (`tex_warning`) in the
DOL's symbol map, so the disassembler's "a chunk ends at the next symbol"
rule cut the texture 32 bytes short, the palette decoded as empty, and the
PNG came out blank.

## GS Texture Format IDs

The format ID stored at header offset 0x0B uses Genius Sonority's own numbering, NOT the standard GX `GXTexFmt` values. Both ID systems are listed for cross-reference.

| GS ID | GX ID | Name | BPP | Block | Indexed | Description |
|-------|-------|------|-----|-------|---------|-------------|
| 0x40 | 0 | I4 | 4 | 8×8 | No | 4-bit intensity (grayscale) |
| 0x41 | 2 | IA4 | 8 | 8×4 | No | 4-bit intensity + 4-bit alpha |
| 0x42 | 1 | I8 | 8 | 8×4 | No | 8-bit intensity (grayscale) |
| 0x43 | 3 | IA8 | 16 | 4×4 | No | 8-bit intensity + 8-bit alpha |
| 0x44 | 4 | RGB565 | 16 | 4×4 | No | 16-bit color (5R, 6G, 5B) |
| 0x45 | 6 | RGBA32 | 32 | 4×4 | No | 32-bit color (8 bits per channel) |
| 0x90 | 5 | RGB5A3 | 16 | 4×4 | No | 16-bit; high bit: opaque 5/5/5 or alpha 3 + 4/4/4 |
| 0x00 | 8 | C4 | 4 | 8×8 | Yes | 4-bit indexed (16-color palette) |
| 0x01 | 9 | C8 | 8 | 8×4 | Yes | 8-bit indexed (256-color palette) |
| 0x30 | 10 | C14X2 | 16 | 4×4 | Yes | 14-bit indexed (16384 colors, 2 bits unused) |
| 0xB0 | 14 | CMPR | 4 | 8×8 | No | S3TC/DXT1 compressed |

## Block-Based Encoding

All GX texture formats store pixels in tiles (blocks) of fixed size, arranged in row-major order. Dimensions are padded up to the next block boundary.

```
blocks_wide = ceil(width / block_width)
blocks_high = ceil(height / block_height)
data_bytes  = blocks_wide * blocks_high * block_width * block_height * bpp / 8
```

### I4 / I8 / IA4 / IA8

Straightforward intensity/alpha formats. Each pixel stored at the given BPP within blocks.

- **I4:** 4 bits per pixel, 2 pixels per byte. 8×8 blocks = 32 bytes/block.
- **I8:** 8 bits per pixel. 8×4 blocks = 32 bytes/block.
- **IA4:** Upper 4 bits = alpha, lower 4 bits = intensity. 8×4 blocks = 32 bytes/block.
- **IA8:** Upper byte = alpha, lower byte = intensity. 4×4 blocks = 32 bytes/block.

### RGB565

16 bits per pixel: `[RRRRR GGGGGG BBBBB]`. 4×4 blocks = 32 bytes/block.

### RGB5A3

16 bits per pixel with conditional alpha:
- If high bit is **1**: opaque, `[1 RRRRR GGGGG BBBBB]` (5/5/5 RGB)
- If high bit is **0**: translucent, `[0 AAA RRRR GGGG BBBB]` (3-bit alpha + 4/4/4 RGB)

4×4 blocks = 32 bytes/block.

### RGBA32

32 bits per pixel stored in a special split layout. Each 4×4 block is 64 bytes, split into two 32-byte halves:
1. **First half (AR):** Alpha and Red channels interleaved — `[A0 R0 A1 R1 ... A15 R15]`
2. **Second half (GB):** Green and Blue channels interleaved — `[G0 B0 G1 B1 ... G15 B15]`

### C4 / C8 / C14X2 (Indexed)

Pixel values are palette indices. The palette is stored separately (see Palette section).

- **C4:** 4 bits per index, 16-color palette. 8×8 blocks.
- **C8:** 8 bits per index, 256-color palette. 8×4 blocks.
- **C14X2:** 16 bits per entry, upper 14 bits are the index, lower 2 bits unused. 4×4 blocks.

### CMPR (S3TC/DXT1)

Each 8×8 CMPR block contains four 4×4 DXT1 sub-blocks (8 bytes each = 32 bytes total per 8×8 block):

Per 4×4 sub-block (8 bytes):
1. **Color 0** (2 bytes): RGB565
2. **Color 1** (2 bytes): RGB565
3. **Index table** (4 bytes): 4×4 grid of 2-bit indices

The 4-color palette is derived:
- If color0 > color1: colors 2 and 3 are 1/3 and 2/3 interpolations
- If color0 ≤ color1: color 2 is 1/2 interpolation, color 3 is transparent black

### Re-encoding a CMPR texture

A decoded DXT1 block cannot be *re-compressed* back into itself, and the
reason is structural rather than a matter of search quality:

- An endpoint reaches the decoded image only where some pixel actually
  used index 0 or 1. 22 % of real blocks use neither.
- The two interpolated entries are 1/3 and 2/3 points of the endpoint
  pair, and those do not land back on the 5/6/5 grid. Quantizing one
  loses the pair it came from.
- 36 % of real blocks use a **single** index, so they decode to one flat
  color. Their endpoints described the spread of the *original
  uncompressed* block, which the decoded image no longer holds.

So the encoder **inverts** a block before it compresses one: given the
sixteen decoded pixels it solves for endpoints whose palette reproduces
them exactly. The arithmetic is per channel and the grid is coarser than
the truncation slack — `(2a + b) / 3 == s` pins `2a + b` to a three-wide
window, and the channel step is 8 (4 for green) — so one known endpoint
plus one interpolated color determines the other endpoint outright, and
two interpolated colors determine both. Compression is reached only for
an image that has actually been edited.

Measured on all 1,437 CMPR textures in the Colosseum, XD and Battle
Revolution dumps (3,354,460 sub-blocks):

| | re-compress | invert |
|---|---|---|
| pixel-identical blocks | 55.5 % | **100 %** |
| byte-identical blocks | 45.7 % | **71.6 %** |
| worst channel delta | 41 | 0 |

Per game, byte-identical: XD 54.7 % → **78.3 %**, Colosseum 45.6 % →
**76.4 %**, Battle Revolution 29.4 % → **55.7 %**. PBR is lower because
43 % of its blocks are flat against 26 % of the GameCube games', not
because anything about it is handled worse — each figure is within a
point of the ceiling its own flat-block share allows.

The gap to 100 % byte-identical is the flat blocks above: nothing in the
decoded image distinguishes the endpoint pairs that interpolate to the
same color, so the encoder picks one that reproduces the pixels and the
bytes differ. Two sub-shapes do have a convention, and it holds across
all three games, so they are reproduced:

- **One opaque color, at index 0.** The color, then a second endpoint one
  step above it in red (`+0x0800`), which reads as three-color. Where red
  is at its maximum the step moves to blue. 90–99 % per game of 178,010
  blocks.
- **White.** Neither step is available, so the color goes to index 1
  above a zero endpoint 0. 99 % of 67,180 blocks.
- **Wholly transparent.** Zero endpoints with every index 3 — 71 % of
  61,524 blocks; the rest keep leftover source color in endpoints that
  nothing displays.

Two further details are load-bearing:

- **A block that needs no interpolated entry is written three-color**,
  with the lower endpoint first — 98 % of such real blocks, against the
  four-color a compressor would reach for. Getting this backwards also
  changes the *colors*, because four-color's 1/3 points replace
  three-color's midpoint.
- **A padded edge block only has to reproduce its visible pixels.** A
  texture whose dimensions aren't multiples of 8 pads out to the block
  grid, and nothing displays those pixels. The games pad with
  transparency themselves on 69 % of such blocks, so the whole block is
  tried first; only when that fails do the invisible positions become
  free, which is what lets an edge block whose visible colors need the
  opaque four-color palette still come back exactly.

**CMPR is still not a declared 1:1 target** — a flat block's endpoints are
not recoverable from anything the file holds, so the gap is a
re-derivation that cannot be closed rather than a nameable divergence.
What it *is* now is pixel-lossless, which is the property that matters:
a round trip no longer degrades an image, and repeated ones no longer
compound. Held by `GXTextureCMPRCorpusTests`
(`GODDESS_CMPR_LIMIT=all` for a full sweep).

## Palette Formats

Indexed textures (C4, C8, C14X2) require a color palette. Each entry is **2 bytes**. The palette format determines how those bytes are interpreted.

| GS Palette ID | Name | Description |
|----------------|------|-------------|
| 0 | IA8 | 8-bit intensity + 8-bit alpha |
| 1 | RGB565 | 5 red, 6 green, 5 blue |
| 2 | RGB5A3 | Same as texture RGB5A3 (used in DAT model textures) |
| 3 | RGB5A3 | Same as above (used in standalone GTX files in Colo/XD) |

**Note:** Palette format ID 2 and 3 both decode as RGB5A3. ID 2 is used within DAT model embedded textures and other games; ID 3 is used in Colo/XD standalone GTX files.

### Re-encoding an indexed texture

The tool dumps a texture's pixels as an RGBA PNG, so an indexed one does
not come back byte-identical: RGBA cannot say which index carried which
color, and real palettes carry duplicate entries — XD's `lbl_803FA760`
(C8, 122×38) uses 125 indices holding only 56 distinct colors, and the
health-warning texture has 16 indices over 15 colors. A re-encode
therefore rebuilds the palette in first-seen-color order and assigns
different index numbers.

**This is cosmetic, and deliberately left as is.** A palette's entry
count is fixed by the format, so the texture keeps its byte length and
nothing downstream of it moves; and every pixel still resolves to the
color it had, because each GTX carries its own palette and nothing
indexes into it by number. Measured on all six Colosseum/XD discs: the
only bytes that differ in a rebuilt `main.dol` are the bodies of three
indexed textures per XD disc (7,398 bytes) and rather more on Colosseum
(23–24 KB).

Contrast the GameCube card icon, where the same loss *is* a correctness
problem: its frames share one palette, so per-frame re-indexing has no
single palette to store. Those are written as indexed PNGs — see
`GCI - GameCube Memory Card Save.md`. If GTX ever needs the same
treatment (a title that animates a palette at runtime, say), the fix is
the same: dump indices and palette rather than flattened color.

C14X2 could not use that route anyway — its palette holds up to 16,384
entries and an indexed PNG caps at 256.

**Palette sizes:**
| Texture Format | Entries | Palette Size |
|----------------|---------|-------------|
| C4 | 16 | 32 bytes |
| C8 | 256 | 512 bytes |
| C14X2 | up to 16,384 | up to 32,768 bytes |

The palette immediately follows the texture data in the file. Its location is given by the palette data pointer at header offset 0x48.

## ATX — Animated Textures

ATX files contain multiple GTX frames stored sequentially. Each frame has its own 0x80-byte header + texture data + optional palette. Frames are played in order at a fixed rate.

**Usage:**
- Animated Pokemon sprites in menus and storage boxes
- Animated UI elements (buttons, indicators)
- Looping background effects

ATX frames can be extracted as PNG sequences and re-imported.

## Textures in Other Formats

The same GX texture encoding appears embedded in:

| Container | How textures appear |
|-----------|-------------------|
| **DAT/RDAT** | Embedded in model node tree with texture headers (TObj nodes) |
| **PKX** | Within the DAT model section, plus shiny filter texture data |
| **GSW** | Identified by `[0x03, 0x00, 0x00, id]` section markers; texture data at marker+0x20, palette at marker+0x68 |
| **WZX** | Within embedded DAT sub-models |

## Runtime System

The game manages textures through the **GStexture** runtime (18 functions in XD):

| Function | Purpose |
|----------|---------|
| `GStextureCreate` | Allocate texture object |
| `GStextureCreateFromMemory` | Create from raw data |
| `GStextureLoad` | Load into GX hardware |
| `GStextureConvertFromHW` | Convert from GX to CPU-accessible format |
| `GStextureConvertToHW` | Convert from CPU to GX format |
| `GStextureLockImage` / `UnlockImage` | CPU access to texture data |
| `GStextureSetFilter` | Set minification/magnification filters |
| `GStextureSetWrap` | Set S/T wrap modes |
| `GStextureGetFormat` | Query pixel format |
| `GStextureGetGXformat` | Get GX-native format ID |
| `GStextureGetTlutFormat` | Get palette (TLUT) format |
| `GStextureGetXsize` / `GetYsize` | Query dimensions |
| `GStextureGetMiplevels` | Query mipmap count |
| `GStextureInit` | Initialize texture subsystem |
| `GStextureFree` | Release texture resources |

## Game-Specific Differences

The GTX/ATX format is identical between Colosseum and XD. Both games support all 11 texture formats listed above.
