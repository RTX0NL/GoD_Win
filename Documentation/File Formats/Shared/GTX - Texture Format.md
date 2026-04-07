# GTX - Texture Format

GTX is the texture format used in Pokemon Colosseum and Pokemon XD for standalone texture assets stored within FSYS archives. It wraps GameCube GX texture data with a header containing dimensions, format metadata, and pointers to the texture and palette data. The format supports all standard GX texture formats including indexed (paletted) and direct-color modes.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x12` |
| Extension | `.gtx` |
| Byte Order | Big-endian |

## Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | UInt16 | Width | Texture width in pixels |
| 0x02 | 2 | UInt16 | Height | Texture height in pixels |
| 0x04 | 1 | UInt8 | BPP | Bits per pixel |
| 0x05 | 1 | UInt8 | Indexed flag | Non-zero if texture uses a palette |
| 0x06 | 5 | - | Unknown | |
| 0x0B | 1 | UInt8 | Texture format ID | GX texture format (see table below) |
| 0x0C | 3 | - | Unknown | |
| 0x0F | 1 | UInt8 | Palette format ID | GX palette format (IA8, RGB565, or RGB5A3) |
| 0x10 | 24 | - | Unknown | |
| 0x28 | 4 | UInt32 | Texture data pointer | Offset to raw texture data |
| 0x2C | 28 | - | Unknown | |
| 0x48 | 4 | UInt32 | Palette data pointer | Offset to palette data (0 if non-indexed) |
| 0x4C | 52 | - | Unknown | |

Texture data typically starts at approximately offset 0x80, though the exact offset should be read from the texture data pointer field.

## GX Texture Formats

All GX texture formats use block-based encoding. The texture is divided into tiles (blocks) of a fixed pixel size, and blocks are stored in row-major order.

| Format ID | Name | Block Size | BPP | Description |
|-----------|------|-----------|-----|-------------|
| 0x00 | I4 | 8x8 | 4 | 4-bit intensity (grayscale) |
| 0x01 | I8 | 8x4 | 8 | 8-bit intensity (grayscale) |
| 0x02 | IA4 | 8x4 | 8 | 4-bit intensity + 4-bit alpha |
| 0x03 | IA8 | 4x4 | 16 | 8-bit intensity + 8-bit alpha |
| 0x04 | RGB565 | 4x4 | 16 | 16-bit direct color (5 red, 6 green, 5 blue) |
| 0x05 | RGB5A3 | 4x4 | 16 | 16-bit; if high bit set: 5/5/5 RGB opaque; else 3-bit alpha + 4/4/4 RGB |
| 0x06 | RGBA32 | 4x4 | 32 | 32-bit direct color (8 bits per channel, stored as AR+GB pairs) |
| 0x08 | C4 | 8x8 | 4 | 4-bit indexed (16-color palette) |
| 0x09 | C8 | 8x4 | 8 | 8-bit indexed (256-color palette) |
| 0x0A | C14X2 | 4x4 | 16 | 14-bit indexed (16384-color palette, 2 bits unused) |
| 0x0E | CMPR | 8x8 | 4 | S3TC/DXT1 compressed (4 sub-blocks of 4x4) |

## Block Encoding Details

### Block Size and Data Size

Each block contains `block_width * block_height` pixels at the given BPP. The texture dimensions are padded up to the next multiple of the block size. Total data size:

```
blocks_wide = ceil(width / block_width)
blocks_high = ceil(height / block_height)
data_size = blocks_wide * blocks_high * block_width * block_height * bpp / 8
```

### RGBA32 Special Layout

RGBA32 blocks are stored in two 32-byte sub-blocks per 4x4 tile: the first sub-block contains alpha and red channels interleaved (AR), and the second contains green and blue channels interleaved (GB).

### CMPR (S3TC/DXT1) Layout

Each 8x8 CMPR block consists of four 4x4 DXT1 sub-blocks. Each sub-block is 8 bytes: two 16-bit RGB565 colors followed by a 4x4 grid of 2-bit indices selecting from a 4-color palette derived from the two base colors.

## Palette Formats

Indexed texture formats (C4, C8, C14X2) require a palette. Each palette entry is 2 bytes. The palette format determines how those 2 bytes are interpreted:

| Format | Description |
|--------|-------------|
| IA8 | 8-bit intensity + 8-bit alpha |
| RGB565 | 5 red, 6 green, 5 blue |
| RGB5A3 | Same interpretation as the texture format |

Palette entry count depends on the texture format:
- C4: 16 entries (32 bytes)
- C8: 256 entries (512 bytes)
- C14X2: up to 16384 entries (32768 bytes)

## Runtime System: GStexture

The game manages GTX textures through the `GStexture` runtime system. Disassembly of XD reveals 18 functions handling:

- Texture loading and GX format setup
- Palette (TLUT) initialization and binding
- Texture object (TObj) configuration for the GX pipeline
- Mipmap management
- Wrap mode and filter mode configuration
- Texture cache invalidation

## Game-Specific Differences

The GTX format is identical between Colosseum and XD. Both games support the full range of GX texture formats listed above.
